# Codex Code Review — ipflag

- **Date**: 2026-07-09
- **Reviewer**: OpenAI Codex CLI (gpt-5.5, reasoning effort high), read-only sandbox
- **Scope**: `main.swift`, `build.sh`, `Info.plist` — concurrency, networking, memory, SMAppService, edge cases, privacy
- **Commit**: initial import (`889d0c5`)

## Critical
None found.

## High
None found.

## Medium
- **`main.swift` — `refresh(force:)`** — a forced refresh can start overlapping fetches; an
  older response can overwrite newer state, and the first completion sets `isFetching = false`
  while another fetch is still in flight.
  *Fix*: store the `Task` and cancel/replace it on force refresh, or use a monotonically
  increasing request id and ignore stale completions.
- **`main.swift` — `toggleLaunchAtLogin` / `syncLaunchItemState`** — launch-at-login treats
  every non-`.enabled` status as "unchecked". `.requiresApproval`, `.notFound`, and unavailable
  states need distinct handling.
  *Fix*: `switch SMAppService.mainApp.status`, surface "requires approval" guidance, don't blindly
  call `register()` again.
- **`main.swift` — `menuWillOpen`** — opening the menu triggers a network request every time no
  fetch is active (privacy / rate-limit).
  *Fix*: add a freshness window — skip non-forced refreshes if the last attempt was < 60–300s ago.

## Low
- **`main.swift` — provider parsers / `flagEmoji`** — parsers accept any non-empty country code,
  and `flagEmoji` uppercases before validating, so some malformed non-ASCII input can normalize to
  ASCII. *Fix*: validate the original value is exactly two ASCII letters before storing/displaying.
- **`main.swift` — `Geo.fetch` response handling** — `URLSession` follows redirects; the final
  response host is not validated (low risk since URLs are static).
  *Fix*: check `http.url?.scheme == "https"` and the host is one of the expected providers.
- **`main.swift` — `Geo.fetch` latency** — worst case is 3 providers × 8s = ~24s stale on a
  blackholed network. *Fix*: shorter per-provider timeout, an overall deadline, or race providers
  concurrently.
- **`main.swift` — `MainActor.assumeIsolated` at entry** — works for this AppKit main-thread entry
  but is a sharp edge. *Fix*: use an explicit `@main` type with `@MainActor static func main()`.

## Note
- NWPathMonitor and the timer both route UI updates through `Task { @MainActor ... }` — no direct
  cross-thread UI access found.
- README discloses providers and refresh triggers; it should also note that menu-open refreshes
  may contact providers unless a cache window is added.
