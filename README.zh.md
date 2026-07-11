<p align="center">
  <img src="docs/logo/logo.png" alt="Rockxy" width="128" />
</p>

<h1 align="center">Rockxy</h1>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.vi.md">Tiếng Việt</a> |
  <a href="README.zh.md">中文</a> |
  <a href="README.zh-TW.md">繁體中文</a> |
  <a href="README.es.md">Español</a> |
  <a href="README.pt-BR.md">Português do Brasil</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a> |
  <a href="README.fr.md">Français</a> |
  <a href="README.de.md">Deutsch</a> |
  <a href="README.it.md">Italiano</a> |
  <a href="README.tr.md">Türkçe</a> |
  <a href="README.pl.md">Polski</a> |
  <a href="README.nl.md">Nederlands</a> |
  <a href="README.ru.md">Русский</a> |
  <a href="README.uk.md">Українська</a> |
  <a href="README.ar.md">العربية</a> |
  <a href="README.fa.md">فارسی</a> |
  <a href="README.bn.md">বাংলা</a> |
  <a href="README.ro.md">Română</a> |
  <a href="README.ka.md">ქართული</a>
</p>

<p align="center">
  <strong>macOS 上开源、可审计的调试代理。</strong>
</p>

<p align="center">
  使用可检查、可构建、可信任的原生 Swift 应用拦截、检查和修改 HTTP/HTTPS/WebSocket/GraphQL 流量。<br>
  随着 Rockxy 演进，面向 API、移动端、MCP 辅助、AI 与区块链时代的调试工作流构建。<br>
  <a href="#rockxy-vs-其他方案">Proxyman 和 Charles Proxy</a> 的 local-first、AGPL-3.0 替代方案。
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="版本" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="平台" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="许可证" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="欢迎 PR" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="赞助" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy 在 macOS 上运行" width="800" />
  </a>
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.29.0** — 2026-07-11

### Added

- Added dedicated model API traffic inspection with provider and model hints, streaming state, usage details when available, tool-call summaries, retrieval hints, and clear unavailable-field warnings.
- Added Web3 JSON-RPC inspection for EVM and Solana-style HTTP RPC traffic, including provider host, request ID, method, batch summary, error, chain, transaction, payload, and debug-intent details.
- Added x402-style payment-flow hints for payment-required and retry-oriented HTTP traffic.
- Added a default Protocol column and protocol filters that make model API, Web3 RPC, gRPC, GraphQL, WebSocket, and HTTP traffic easier to scan in the request list.

### Changed

- Kept model API, Web3, and gRPC inspector tabs together at the end of the inspector tab row for a more consistent response-review workflow.
- Clarified that rules and debugging tools continue to match URL, HTTP method, and headers rather than model names, tool calls, chain IDs, JSON-RPC methods, or batch subcalls.
- Refined General settings so proxy controls, certificate status, and certificate actions are easier to scan.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## 当前分支亮点

- Upstream Proxy 现在包含 free/core 的 Automatic Proxy Configuration，支持通过 PAC URL 路由 `DIRECT` 、HTTP 和 HTTPS，同时保留现有 SOCKS5 与认证策略边界。
- 导出流程现在覆盖 OpenAPI YAML/HTML，以及带脱敏感知 payload 构建的 selected-traffic Gist 发布。
- Inspector 工具现在包含 JSONPath/key/value 过滤，以及对 JWT 等选中 payload 文本的快速预览。
- Node.js Developer Setup 现在会在验证时镜像所选客户端，并提供更完整的 localhost 示例指南。
- Developer Setup Hub 现在覆盖运行时、浏览器、客户端、设备、框架与环境，并提供按目标生成的代码片段、验证监视器和清晰的操作指引。
- WebSocket Protobuf 工作继续作为 Rockxy 更丰富协议检查方向的一部分。
- 公开路线图规划现在包含 AI 流量、Web3/RPC flow、x402-style payment flow 的协议感知调试，以及更安全的脱敏证据分享。

## 功能特性

当浏览器 DevTools 已经不够用时,你会伸手去拿的工具。面向 Mac 与 iOS 工作的核心流量调试 — 原生 macOS,公开发布,以本地优先的工作流。

### 流量捕获

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

检查来自任意 Mac 应用、CLI 或 iOS 设备的 HTTP、HTTPS、WebSocket 和 GraphQL 流量。浏览器 DevTools 止步于浏览器 — Rockxy 看见你整个技术栈的其余部分。

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### 高级筛选与搜索

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

在几秒内将数千条捕获请求收窄到你需要的那几条。组合 method、host、status、header、body 和进程过滤器 — 或者在整个会话上跑全文搜索。

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### 面向 AI 助手的 MCP 服务器

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

让 Claude Desktop 或 Cursor 通过本地 MCP 服务器读取你捕获的流量。直接问 "为什么这条请求 500 了?",不用再把 header 粘进聊天框。本地、脱敏感知、开源。

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

为 Python、Node.js、Go、Rust、cURL、Docker 和浏览器复制粘贴代理片段,然后点击 Run Test 确认流量确实经过 Rockxy。

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### HTTPS 调试的证书管理

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

首次启动时生成的 P-256 ECDSA 根 CA,密封在你的 Keychain 中。第一次就能解密 HTTPS;被 pin 的主机自动放行通过。

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL 代理与 HTTPS 解密

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

挑选哪些主机需要 TLS 解密。解密后的流量显示真实的 header 与 JSON;其余仍以加密形式通过。通配符规则让你一键按域名圈定范围。

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

跳过特定主机,让证书 pin 应用、内部服务或嘈杂的 telemetry 永远不会进入捕获。通配符让列表保持精简,请求日志聚焦于真正关心的内容。

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

让任何主机失败。切掉广告网络、第三方追踪器或不稳定的依赖,看看缺了它你的应用如何降级 — 不用改一行代码。

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

用一个已保存的文件或目录树替代真实响应。换掉一个 JSON payload、replay 一个快照,或者在调试时把不稳定的第三方 API 钉到本地副本上。

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

重写一条捕获请求的目的地,不需要碰应用代码或 /etc/hosts。把生产流量指向 staging、你的开发服务器,或同事的机器,做出可重复的 bug 复现。

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### 断点与规则

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

暂停某个请求或响应,编辑 method、header、body 或 status 后继续。测试 "如果 API 返回 401 会怎样?" 最快的方式 — 完全不用碰后端。

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### 修改 Header

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

在任何主机上添加、删除或替换 header,不用重新部署。借助内置预设,几秒内测试 CORS、auth 或 cache 的修改。

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### 自定义请求与响应 Header

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

按主机覆盖 header,对两端 phase 都有完整控制。给出站请求注入 auth token,从响应中剥掉 Set-Cookie,或固定一个自定义 User-Agent — 保存为命名规则,随时切换。

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### 网络条件

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

限速到 3G、EDGE、LTE、WiFi 或自定义延迟。你笔记本走的是光纤;你的用户不是 — 在他们之前感受 400 ms RTT 下的体验。

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — 编辑并重放

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

重建任何捕获到的 HTTP 请求 — 修改 method、URL、header、查询参数或 body — 不离开 Rockxy 即可重发。不用再走 Postman、Insomnia 或 curl 的复制粘贴循环。在几秒内迭代 LLM prompt、模糊 auth 边界,或为 OpenAI、Anthropic、Cohere 端点复现一个失败用例。

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### 比较

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

把两条捕获响应并排叠放,捕捉每一个翻转的字段 — status、header、JSON 键、body 字节。识别静默的 API 回归、不确定的 LLM 输出和 prompt drift,不用把任何东西塞进第三方 diff 工具。并排 diff 突出差异;深度 JSON 比较忽略键顺序。

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### 自定义预览标签

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

按你想要的方式渲染请求与响应 body。给 inspector 钉上额外的标签页,用于 JSON、GraphQL、JWT、图片或你自己的格式 — 在所有捕获请求上复用。

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### 会话与导出

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

保存会话,在不同工具间用 HAR 互通,把任意请求复制为 cURL 或 JSON。在分享前对 authorization header、cookie 和 bearer token 做脱敏 — 给同事一个能跑的 bug 复现,而不泄漏 secret。

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### 多标签工作区

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

并排运行独立的捕获会话 — 一个标签给 staging,一个给 prod,一个给 iOS 设备 build。每个标签都有自己的过滤器、选择和 inspector 状态,所以切换上下文几乎零成本。

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript 脚本

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

在请求与响应上用 JS hook 处理静态规则覆盖不到的情况 — 脱敏 PII、签发 token、改写 payload。错误以 inline 方式出现,而不是把流量弄坏。

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## 更多即将推出的功能

未来功能会公开跟踪，并且只在实现、测试、隐私行为和文档都准备好之后发布。

### AI 流量检查 `即将推出`

让模型流量在正常 capture 工作流中更容易调试。检测 AI 请求，检查选中的模型调用，诊断 streaming response，比较 prompt/output 行为，并理解 tool-call chain，而不需要把敏感 payload 粘贴到其他服务。

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Web3/RPC 检查 `即将推出`

把区块链时代的 network call 变成可读的调试证据。检查 JSON-RPC 和 Solana RPC 流量，把相关调用归组为 flow，解释常见 RPC 错误，并 replay 选中的请求，同时不把 Rockxy 变成钱包或 block explorer。

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### x402 支付流程调试 `即将推出`

从网络层理解 payment-gated HTTP flow。突出 payment-required response，跟随 retry path，并让调试证据保持本地优先与脱敏感知。

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### 脱敏证据包 `即将推出`

分享复现 bug 所需的事实，而不泄露 secret。把 selected traffic、protocol summary、redaction preview 和 source-backed context 打包，让同事可以审计。

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### 协议感知过滤器与规则 `即将推出`

在 Rockxy 已经工作的地方使用 AI 和 Web3 metadata：filter、badge、optional column、comparison、rule、Developer Setup 和 local MCP summary。

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### 团队分享与协作 `即将推出`

一键把捕获会话发给同事。对失败请求做 inline 注释,实时看到谁在看什么,无需共享屏幕也能 pair-debug HTTPS 流量。规划在未来版本中推出。

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% 原生 macOS。没有 Electron。没有 Web 视图。SwiftUI + AppKit + SwiftNIO。

## 快速开始

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

在 Xcode 中构建并运行。欢迎窗口将引导您完成根 CA 设置、Helper 安装和代理激活。

**系统要求：** macOS 14.0+、Xcode 16+、Swift 5.9

## Rockxy vs. 其他方案

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **项目模式** | AGPL-3.0 开源项目 | 专有商业应用 | 专有商业应用 |
| **源代码** | 公开、可审计、可 fork | 闭源 | 闭源 |
| **从源码构建** | 可使用 Xcode 从本仓库免费构建 | 没有公开源码可供构建 | 没有公开源码可供构建 |
| **原生 macOS 基础** | Swift + SwiftNIO + SwiftUI/AppKit | 原生 macOS 商业应用 | 跨平台商业应用 |
| **Local-first 捕获** | 本地代理、证书、helper 和捕获数据保留在你的 Mac 上 | 桌面代理应用 | 桌面代理应用 |
| **开发者设置流程** | 内置 Developer Setup Hub，覆盖 runtime、client、device、framework 和 environment | 产品专属设置指南 | 产品专属设置指南 |
| **MCP/local automation bridge** | 内置，token 认证，默认脱敏 | 已检查的公开文档中未声明 | 已检查的公开文档中未声明 |
| **开放贡献路径** | 公开 issues、discussions、roadmap 和 PR | 厂商控制的产品 | 厂商控制的产品 |

路线图方向：更深入的 replay/diff/rules/scripting 工作流，改进 WebSocket 和 GraphQL 检查，面向 AI 与 Web3/RPC 的协议感知调试，x402-style payment-flow 可见性，并探索 gRPC/Protobuf 以及 HTTP/2、HTTP/3 支持。

## 安全性

Rockxy 拦截网络流量 — 安全是基础，不是可选项。

- XPC helper 通过**证书链比对**验证调用者，而不仅仅是 bundle ID
- 插件在**沙箱化 JavaScriptCore** 中运行，5 秒超时，无法访问文件系统/网络
- 在所有边界进行**输入验证** — body 大小限制、URI 限制、防 regex DoS、防路径遍历
- 凭证在日志中**自动脱敏**
- 敏感文件以 **0o600 权限**存储

通过 [SECURITY.md](SECURITY.md) 报告漏洞。查看[完整安全架构](docs/development/security.mdx)了解详情。

## 路线图

Rockxy 的公开路线图以调试工作流为中心，不承诺固定日期。它关注可靠性、原生 macOS 体验、调试工作流、协议支持、AI/Web3 时代的流量可见性、文档和贡献者入门。

- [ROADMAP.md](ROADMAP.md)：高层公开工程方向
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1)：路线图相关 issue 的执行视图

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

适合新手的 issue 标记为 [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue)。提交 PR 即表示同意 [CLA](CLA.md)。

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
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — 错误报告和功能请求
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — 问答和社区交流
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
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. 使用 Swift、SwiftNIO、SwiftUI 和 AppKit 构建。</sub>
</p>
