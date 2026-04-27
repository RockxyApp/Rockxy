<p align="center">
  <img src="docs/logo/logo.png" alt="Rockxy" width="128" />
</p>

<h1 align="center">Rockxy</h1>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.vi.md">Tiếng Việt</a> |
  <a href="README.zh.md">中文</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a> |
  <a href="README.fr.md">Français</a> |
  <a href="README.de.md">Deutsch</a>
</p>

<p align="center">
  <strong>macOS 上的开源 HTTP 调试代理。</strong>
</p>

<p align="center">
  拦截、检查和修改 HTTP/HTTPS/WebSocket/GraphQL 流量 — 使用 Swift 原生构建。<br>
  <a href="#rockxy-vs-其他方案">Proxyman 和 Charles Proxy</a> 的免费、可审计替代方案。
</p>

<p align="center">
  <a href="https://github.com/LocNguyenHuu/Rockxy/releases"><img src="https://img.shields.io/github/v/release/LocNguyenHuu/Rockxy?label=release&color=blue" alt="版本" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="平台" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="许可证" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="欢迎 PR" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="赞助" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Dark.png" alt="Rockxy 在 macOS 上运行" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.11.0** — 2026-04-25

### Added

- Sparkle-powered automatic updates for signed public releases.
- Bundled Rockxy MCP support for local developer-tool integrations.
- Rockxy Pro activation and entitlement-aware upgrade foundations.

### Fixed

- Improved paid-license activation recovery and product validation reliability.
- Closed release-readiness gaps around production licensing configuration and update metadata.
- Fixed release signing settings required for Apple notarization and Gatekeeper acceptance.

### Changed

- Hardened the release pipeline with production signing, notarization, stapling, checksum, and update-feed validation.
- Refreshed public documentation, localized README content, and release metadata for the 0.11.0 release.
- Improved Xcode project and build configuration reproducibility for fresh checkouts.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## 当前分支亮点

- Developer Setup Hub 现在覆盖运行时、浏览器、客户端、设备、框架与环境，并提供按目标生成的代码片段、验证监视器和清晰的操作指引。
- 当按域名或应用启用/禁用 SSL Proxying 时，HTTPS 响应提示、侧边栏操作和主请求表的展示会保持同步。
- Inspector 与主请求表已完成一轮打磨，包括单行可滚动标签、Query 顶部对齐、更清晰的 Status/Code 区分、Request/Response 字节列、Duration 修正以及实时 SSL 状态图标。

## 功能特性

**流量捕获** — 基于 SwiftNIO 的代理，支持 CONNECT 隧道、自动为每个主机生成 TLS 证书、WebSocket 帧捕获，以及自动检测 GraphQL 操作。

**全面检查** — JSON 树形视图、十六进制检查器、时序瀑布图（DNS/TCP/TLS/TTFB/Transfer）、headers、cookies、查询参数、认证信息 — 全部集成在标签式检查器中。

**Mock 与修改** — Map Local（从本地文件提供响应）、Map Remote（重定向到其他服务器）、Breakpoints（中途暂停并编辑）、Block、Throttle、Modify Headers、Allow List、Bypass Proxy。

**日志关联** — 捕获 macOS 系统日志（OSLog）并按时间戳与网络请求关联。查看每个请求来自哪个应用。

**插件扩展** — 在沙箱化的 JavaScriptCore 运行时中使用 JavaScript 脚本。通过自定义 hook 检查、修改和自动化流量。

**为大规模而生** — NSTableView 虚拟滚动处理 100k+ 请求。环形缓冲区淘汰、磁盘 body 卸载、批量 UI 更新。零延迟。

**Developer Setup Hub** — 面向运行时、浏览器、设备、框架与环境的引导式配置中心，提供可复制片段、验证探针和故障排查说明。

**AI-Ready (MCP Server)** — 内置 Model Context Protocol 服务器，让 Claude CLI、Claude Desktop 及其他 MCP 客户端可直接在对话中查询实时流量、规则和代理状态。仅本地运行，使用 token 认证，敏感数据默认脱敏。

> 100% 原生 macOS。没有 Electron。没有 Web 视图。SwiftUI + AppKit + SwiftNIO。

## 快速开始

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

在 Xcode 中构建并运行。欢迎窗口将引导您完成根 CA 设置、Helper 安装和代理激活。

**系统要求：** macOS 14.0+、Xcode 16+、Swift 5.9

## Rockxy vs. 其他方案

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **许可证** | AGPL-3.0（开源） | 专有（免费增值） | 专有（$50） |
| **源代码** | 完全可审计 | 闭源 | 闭源 |
| **技术** | Swift + SwiftNIO | Swift + AppKit | Java |
| **HTTPS 拦截** | 是 | 是 | 是 |
| **WebSocket** | 是 | 是 | 是 |
| **GraphQL 检测** | 是 | 是 | 否 |
| **Map Local / Remote** | 是 | 是 | 是 |
| **Breakpoints** | 是 | 是 | 是 |
| **JavaScript 脚本** | 是 | 是 | 否 |
| **OSLog 关联** | 是 | 否 | 否 |
| **进程识别** | 是 | 是 | 否 |
| **请求对比** | 是 | 是 | 否 |
| **HAR 导入/导出** | 是 | 是 | 否 |
| **100k+ 行性能** | 是 | 是 | 慢 |
| **免密码代理设置** | 是（helper 守护进程） | 是 | 否 |
| **社区贡献** | 开放 PR | 否 | 否 |

## 安全性

Rockxy 拦截网络流量 — 安全是基础，不是可选项。

- XPC helper 通过**证书链比对**验证调用者，而不仅仅是 bundle ID
- 插件在**沙箱化 JavaScriptCore** 中运行，5 秒超时，无法访问文件系统/网络
- 在所有边界进行**输入验证** — body 大小限制、URI 限制、防 regex DoS、防路径遍历
- 凭证在日志中**自动脱敏**
- 敏感文件以 **0o600 权限**存储

通过 [SECURITY.md](SECURITY.md) 报告漏洞。查看[完整安全架构](docs/development/security.mdx)了解详情。

## 路线图

- [x] HTTP/HTTPS/WebSocket/GraphQL 拦截
- [x] Map Local、Map Remote、Breakpoints、Block、Throttle
- [x] JavaScript 插件系统（沙箱执行）
- [x] HAR 导入/导出、原生会话文件、请求对比
- [x] OSLog 关联和凭证脱敏
- [x] 面向 AI 助手的 Model Context Protocol (MCP) 服务器（Claude CLI、Claude Desktop）
- [ ] HTTP/2 和 HTTP/3 支持
- [ ] 远程设备代理（iOS 通过 USB/Wi-Fi）
- [ ] CI/CD 流水线的 Headless 模式
- [ ] gRPC / Protocol Buffers 检查
- [ ] 错误分组和分析仪表板

## 文档

完整文档请访问 [Rockxy Docs](docs/index.mdx)：

- [快速入门](docs/quickstart.mdx) — 几分钟内完成设置
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — 运行时代码片段、设备指南、验证探针与支持矩阵
- [MCP 集成](docs/features/mcp.mdx) — MCP 配置与使用指南
- [架构](docs/development/architecture.mdx) — 代理引擎、Actor 模型、数据流
- [安全模型](docs/development/security.mdx) — 信任边界、XPC 验证、证书管理
- [设计决策](docs/development/design-decisions.mdx) — 为什么选择 SwiftNIO、NSTableView、Actors
- [从源码构建](docs/development/building.mdx) — 构建、测试、lint 和调试
- [代码风格](docs/development/code-style.mdx) — SwiftLint、SwiftFormat 和约定
- [更新日志](CHANGELOG.md) — 当前分支变更与已发布版本历史

## 贡献

欢迎各种贡献 — 代码、测试、文档、错误报告和 UX 反馈。

查看 **[CONTRIBUTING.md](CONTRIBUTING.md)** 了解设置指南、代码风格和完整的 PR 检查清单。

适合新手的 issue 标记为 [`good first issue`](https://github.com/LocNguyenHuu/Rockxy/labels/good%20first%20issue)。提交 PR 即表示同意 [CLA](CLA.md)。

## 赞助商与合作伙伴

Rockxy 由独立开发者构建和维护。赞助资金用于持续开发、安全审计和新功能。

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/赞助_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="赞助 Rockxy" />
  </a>
</p>

| 等级 | 权益 |
|------|------|
| **Gold Sponsor** | Logo 展示在 README + 文档站，优先功能请求，专属支持通道 |
| **Silver Sponsor** | Logo 展示在 README，发布说明中致谢 |
| **Bronze Sponsor** | 在 README 和文档中致谢 |
| **Partner** | 联合开发、集成支持、抢先体验即将推出的功能 |

**合作咨询** — 开发者工具公司、安全公司和企业团队，如需定制集成或白标方案：[rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## 支持

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — 支持 Rockxy 的开发
- [GitHub Issues](https://github.com/LocNguyenHuu/Rockxy/issues) — 错误报告和功能请求
- [GitHub Discussions](https://github.com/LocNguyenHuu/Rockxy/discussions) — 问答和社区交流
- **邮箱** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **安全问题** — 查看 [SECURITY.md](SECURITY.md) 了解负责任的披露流程

## 许可证

[GNU Affero General Public License v3.0](LICENSE) — 版权所有 2024–2026 Rockxy Contributors。

## 星标历史

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>使用 Swift、SwiftNIO、SwiftUI 和 AppKit 构建。</sub>
</p>
