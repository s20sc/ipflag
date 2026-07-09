# ipflag

一个 macOS 菜单栏小工具：在菜单栏显示当前公网 IP 所在国家的国旗 emoji。
切换 VPN 或更换网络时会自动更新。

原生 Swift（AppKit），无第三方依赖，无 Dock 图标。

## 构建

```bash
./build.sh
```

生成 `build/ipflag.app`。

## 运行

```bash
open build/ipflag.app
```

菜单栏会先显示 🌐，几秒后变成当前所在国家的国旗（如 🇯🇵）。

点击图标展开菜单：

- **IP / 国家** — 当前公网 IP 与国家（中文名 + 两位代码），只读
- **立即刷新** — 手动重新定位
- **开机自启** — 登录时自动启动（勾选切换）
- **退出** — 关闭程序

## 工作原理

1. 依次请求 HTTPS 定位服务（`ipinfo.io` → `ipwho.is` → `api.ip.sb`），
   任一成功即用，拿到公网 IP 和两位国家代码。
2. 国家代码转成 Regional Indicator，即国旗 emoji。
3. 国家中文名由系统 `Locale` 本地生成，不依赖接口。
4. 刷新时机：启动时、每 15 分钟一次、网络路径变化时
   （`NWPathMonitor`，切 VPN / 换 Wi-Fi 都会触发），以及打开菜单时
   （距上次请求超过 60 秒才会重新定位，避免频繁点菜单反复打接口）。

## 说明

- **隐私**：IP 定位需要把你的公网 IP 发给上述服务商，这是 IP 定位的固有特性。
- **开机自启**：使用 `SMAppService`。本地未签名/临时签名的 App 一般也能注册；
  若不生效，把 `ipflag.app` 移动到「应用程序」后再试。可在
  「系统设置 › 通用 › 登录项」中查看/管理。
- 依赖的系统框架：`AppKit`、`Foundation`、`Network`、`ServiceManagement`。
