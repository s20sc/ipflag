import AppKit
import Foundation
import Network
import ServiceManagement

// MARK: - Country code → flag emoji

/// Turn a 2-letter ISO 3166-1 alpha-2 code into its flag emoji by mapping each
/// letter to its Regional Indicator Symbol (U+1F1E6 is 'A').
func flagEmoji(_ code: String) -> String {
    let cc = code.uppercased()
    guard cc.count == 2, cc.allSatisfy({ $0.isLetter && $0.isASCII }) else { return "🏳️" }
    let base: UInt32 = 0x1F1E6
    var scalars = String.UnicodeScalarView()
    for ch in cc.unicodeScalars {
        guard let s = UnicodeScalar(base + (ch.value - 65)) else { return "🏳️" }
        scalars.append(s)
    }
    return String(scalars)
}

// MARK: - Geolocation

struct GeoResult {
    let ip: String
    let countryCode: String
}

/// Ordered list of HTTPS providers. Each returns (ip, countryCode). We try them
/// in order and use the first that succeeds, so one provider being down or
/// rate-limited doesn't break the app.
enum Geo {
    private struct Provider {
        let url: URL
        let parse: ([String: Any]) -> GeoResult?
    }

    private static let providers: [Provider] = [
        Provider(url: URL(string: "https://ipinfo.io/json")!) { json in
            guard let cc = json["country"] as? String, !cc.isEmpty else { return nil }
            let ip = json["ip"] as? String ?? "—"
            return GeoResult(ip: ip, countryCode: cc)
        },
        Provider(url: URL(string: "https://ipwho.is/")!) { json in
            guard let cc = json["country_code"] as? String, !cc.isEmpty else { return nil }
            let ip = json["ip"] as? String ?? "—"
            return GeoResult(ip: ip, countryCode: cc)
        },
        Provider(url: URL(string: "https://api.ip.sb/geoip")!) { json in
            guard let cc = json["country_code"] as? String, !cc.isEmpty else { return nil }
            let ip = json["ip"] as? String ?? "—"
            return GeoResult(ip: ip, countryCode: cc)
        },
    ]

    static func fetch() async -> GeoResult? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        for provider in providers {
            do {
                var req = URLRequest(url: provider.url)
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue("ipflag/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = provider.parse(obj)
                else { continue }
                return result
            } catch {
                continue
            }
        }
        return nil
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.ipflag.app.monitor")

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 900 // 15 minutes

    /// Point size for the menu-bar glyph. Larger than the ~13pt default so the
    /// flag reads clearly; bump this if you want it bigger still.
    private let statusFontSize: CGFloat = 17

    private var isFetching = false
    private var lastResult: GeoResult?

    // Menu items whose content we update.
    private let ipItem = NSMenuItem(title: "IP: —", action: nil, keyEquivalent: "")
    private let countryItem = NSMenuItem(title: "定位中…", action: nil, keyEquivalent: "")
    private var launchItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusTitle("🌐")

        buildMenu()
        statusItem.menu = menu

        // Refresh on any network path change (Wi-Fi switch, VPN toggle, etc.).
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start(queue: monitorQueue)

        // Periodic fallback refresh.
        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        refresh()
    }

    private func buildMenu() {
        menu.delegate = self

        ipItem.isEnabled = false
        countryItem.isEnabled = false
        menu.addItem(ipItem)
        menu.addItem(countryItem)

        menu.addItem(.separator())

        let refreshMenuItem = NSMenuItem(title: "立即刷新", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshMenuItem.target = self
        menu.addItem(refreshMenuItem)

        launchItem = NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    /// Sets the menu-bar glyph at an enlarged point size. Emoji honor the font
    /// size; a small baseline nudge keeps it vertically centered in the bar.
    private func setStatusTitle(_ text: String) {
        guard let button = statusItem.button else { return }
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: statusFontSize),
                .baselineOffset: -1.5,
            ]
        )
    }

    // MARK: Refresh

    @objc private func refreshClicked() { refresh(force: true) }

    private func refresh(force: Bool = false) {
        if isFetching && !force { return }
        isFetching = true
        Task { [weak self] in
            let result = await Geo.fetch()
            self?.apply(result)
        }
    }

    private func apply(_ result: GeoResult?) {
        isFetching = false
        guard let result else {
            // Keep the last known flag if we have one; otherwise show a warning.
            if lastResult == nil { setStatusTitle("⚠️") }
            ipItem.title = "IP: 获取失败"
            countryItem.title = "无法定位（网络或服务不可用）"
            return
        }
        lastResult = result
        setStatusTitle(flagEmoji(result.countryCode))

        let cc = result.countryCode.uppercased()
        let localizedName = Locale.current.localizedString(forRegionCode: cc) ?? cc
        ipItem.title = "IP: \(result.ip)"
        countryItem.title = "\(localizedName) (\(cc))"
    }

    // MARK: Launch at login

    private func syncLaunchItemState() {
        let registered = SMAppService.mainApp.status == .enabled
        launchItem.state = registered ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机自启设置"
            alert.informativeText = "\(error.localizedDescription)\n\n如果反复失败，可把 ipflag.app 移动到「应用程序」后重试。"
            alert.alertStyle = .warning
            alert.runModal()
        }
        syncLaunchItemState()
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        syncLaunchItemState()
        refresh()
    }
}

// Program entry runs on the main thread; enter the main actor for AppKit setup.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
