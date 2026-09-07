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
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/26380?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-26380" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/26380/daily?language=Swift" alt="RockxyApp/Rockxy | Trendshift" width="250" height="55" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy 在 macOS 上运行" width="800" />
  </a>
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.38.1** — 2026-09-05

### Fixed

- Preserved the same Rockxy root certificate across app relaunches, preventing unexpected certificate replacement and repeated HTTPS inspection setup.
- Made certificate installation, trust checks, and removal safer by targeting exact certificates, preserving unrelated roots, and preventing overlapping privileged changes.
- Improved recovery for outdated helpers and unreadable certificate states with clearer recheck, reinstall, and trust guidance.
- Clarified JetBrains IDE proxy setup and surfaced failed HTTPS CONNECT tunnels for easier diagnosis.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## 当前分支亮点

- AI Assistant 现在可通过内置本地分析或已配置的 Ollama/provider 模型调查一个或多个选中请求，并提供明确的 Review Data 确认、受限脱敏、流式响应、证据定位和用户主动触发的 handoff。
- 原生侧边栏现在提供可复用的 Focus Sets，用于 app/domain/path 范围，并提供 workspace 级 Noise Control，在不中断捕获的情况下隐藏匹配的 domain 或 path。
- 主工作区现在为 Context Dock 和底部 inspector 使用原生纵向与横向 split view，保持全高分隔线、对齐 toolbar/footer separator，并自动调整布局。
- Upstream Proxy 现在包含 free/core 的 Automatic Proxy Configuration，支持通过 PAC URL 路由 `DIRECT` 、HTTP 和 HTTPS，同时保留现有 SOCKS5 与认证策略边界。
- 导出流程现在覆盖 OpenAPI YAML/HTML，以及带脱敏感知 payload 构建的 selected-traffic Gist 发布。
- Inspector 工具现在包含 JSONPath/key/value 过滤，以及对 JWT 等选中 payload 文本的快速预览。
- AI 与 Web3 流量检查现在为已识别的模型调用、JSON-RPC 流量和 x402 风格支付提示提供协议标签、inspector 标签和调试摘要。
- Node.js Developer Setup 现在会在验证时镜像所选客户端，并提供更完整的 localhost 示例指南。
- Developer Setup Hub 现在覆盖运行时、浏览器、客户端、设备、框架与环境，并提供按目标生成的代码片段、验证监视器和清晰的操作指引。
- WebSocket 二进制帧检查现在包含受限、按需的 Protobuf wire-format 启发式分析，不会把 decoder 工作加入捕获热路径。
- 公开路线图现在聚焦更深入的协议感知规则、重放、比较以及更安全的脱敏证据共享。

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

### Focus Sets 与 Noise Control

把重复调查变成侧边栏中的可复用范围。Focus Sets 组合 application、domain、path 的包含条件与 domain/path 排除条件，跨启动持久化并可用于每个 workspace。Noise Control 继续捕获 telemetry 和其他低价值流量，但在当前 workspace 中将其隐藏。

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant 在原生请求表格和侧边栏旁解释选中的捕获流量" width="820" />

选择一个或多个已捕获请求，询问发生了什么、哪里失败、发生了哪些变化，或下一步应验证什么。Rockxy 首先在这台 Mac 上进行基于证据的分析；只有在 Review Data 展示准确、受限且已脱敏的上下文后，才会运行已配置的 Ollama 或 provider 模型。响应可定位来源请求并准备原生 follow-up workflow，但 Assistant 不会自动修改流量或执行这些操作。

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[阅读 AI Assistant 指南](docs/features/ai-assistant.mdx)。

### 面向外部 AI 客户端的 MCP 服务器

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

让 Claude Desktop 或 Cursor 通过 Rockxy 本地 MCP 服务器中的十个只读工具检查捕获的流量。直接问 "为什么这条请求 500 了?",不用再把 header 粘进聊天框。该实现开源、基于 token 认证,并默认保持敏感数据脱敏开启。

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

把任意请求或响应 header 提升为流量表格中的一等列。保持请求与响应来源分离,保存你关心的 header,然后无需打开每个 inspector 即可扫视 request ID、trace ID、cache 状态或自定义元数据。

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### 网络条件

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

限速到 3G、EDGE、LTE、WiFi 或自定义延迟。你笔记本走的是光纤;你的用户不是 — 在他们之前感受 400 ms RTT 下的体验。

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — 编辑并重放

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

重建任何捕获到的 HTTP 请求 — 修改 method、URL、header、查询参数或 body — 不离开 Rockxy 即可重发。不用再走 Postman、Insomnia 或 curl 的复制粘贴循环。在几秒内迭代 LLM prompt、模糊 auth 边界,或为 OpenAI、Anthropic、Cohere 端点复现一个失败用例。

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### 比较

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

把两条捕获 transaction 或粘贴的 payload 并排叠放,捕捉每一个翻转的字段 — status、header、JSON 键或 body 字节。识别静默的 API 回归、不确定的 LLM 输出和 prompt drift,不用把任何东西塞进第三方 diff 工具。

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy 多标签工作区显示同一实时捕获的独立过滤视图" width="820" />

在同一个实时捕获上并排保留独立调查视图 — 一个标签查看 staging 流量，一个查看 production，另一个查看 iOS 设备流程。每个标签拥有自己的筛选、排序、选择、侧边栏范围和 inspector 状态，同时共享 proxy 与已捕获 transaction。

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript 脚本

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

在请求与响应上用 JS hook 处理静态规则覆盖不到的情况 — 脱敏 PII、签发 token、改写 payload。错误以 inline 方式出现,而不是把流量弄坏。

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## 协议感知检查

Rockxy 已在常规 HTTP 调试工作流中提供协议感知的 AI、Web3 RPC 与 x402 检查。

### AI 流量检查

Rockxy 在常规捕获工作流中识别 AI 请求。检查选中的模型调用、流式状态、可用的 usage 字段、警告、retrieval hint 和 tool-call 摘要，无需将敏感 payload 粘贴到其他服务。

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC 检查

Rockxy 将区块链时代的网络调用变成可读调试证据。检查 EVM 与 Solana 风格的 HTTP JSON-RPC 流量，包括 provider host、request ID、method、batch 摘要、错误、chain、transaction、payload 和 debug intent，而不会把 Rockxy 变成钱包或 block explorer。

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 支付流程提示

Rockxy 突出 payment-required 与 retry 提示，让 payment-gated HTTP 流程可从网络层理解，同时保持调试证据本地化并支持脱敏。

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## 未来工作

以下内容描述公开方向，而不是当前行为。

### 协议感知规则

Rockxy 现在可以标记并检查 AI 与 Web3 流量。按 model、tool call、JSON-RPC method、chain、transaction hash 或 batch subcall 深度匹配规则仍属于未来工作；当前流量修改工具仍按 URL、HTTP method 和 header 匹配。

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### 脱敏证据包 `即将推出`

分享复现 bug 所需的事实，而不泄露 secret。把 selected traffic、protocol summary、redaction preview 和 source-backed context 打包，让同事可以审计。

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### 团队分享与协作 `即将推出`

一键把捕获会话发给同事。对失败请求做 inline 注释,实时看到谁在看什么,无需共享屏幕也能 pair-debug HTTPS 流量。规划在未来版本中推出。

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 原生 macOS 应用外壳 — 没有 Electron。SwiftUI + AppKit + SwiftNIO,WebKit 仅用于 HTML body 预览。

## 快速开始

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

在 Xcode 中构建并运行。欢迎窗口将引导您完成根 CA 设置、Helper 安装和代理激活。

**系统要求：** macOS 14.0+、Xcode 16+、Swift 5.9

如果你想在安装后将 Rockxy 连接到本地 MCP 客户端,请参阅 [MCP 集成指南](docs/features/mcp.mdx)。

## Rockxy 与替代方案

主要矩阵涵盖通用网络调试代理。安全测试
套件和面向浏览器/API 的拦截器具有大量工作流程重叠
单独列出，因此不同的产品不能互换。
数据包分析器和仅 API 的客户端不在此比较范围内。

### 直接网络调试代理

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **产品形态** | 原生 macOS 调试代理 | 原生 macOS 应用；Windows/Linux 版基于 Electron | 跨平台桌面调试代理 | 跨平台 CLI/TUI 和 Web UI 代理工具包 | 跨平台 Electron 桌面代理和 HTTP 客户端 | 跨平台桌面调试代理 |
| **源码与构建模式** | Community 源码按 AGPL-3.0-or-later 公开，可用 Xcode 构建；官方 DMG 还包含非公开的 downstream 组件 | 闭源；在已审阅的官方资料中未发现公开的应用源码 | 闭源；在已审阅的官方资料中未发现公开的应用源码 | MIT 许可的公开源码，可从源码构建 | AGPL 公开桌面源码，可从源码构建；发布的二进制另有许可选项 | 闭源；按 Fiddler Everywhere EULA 以 object code 分发 |
| **捕获与设置** | 本地系统代理，为 Mac 应用、runtime、iOS 设备和 Simulator 提供引导式设置 | 自动设置 Mac 应用、runtime 和移动设备 | 本地代理，提供 macOS、iOS 和跨平台设置指南 | regular、local-process、WireGuard、reverse、transparent 等捕获模式 | 面向浏览器、runtime、container 和移动设备的 targeted/manual proxy interception | system、network、browser、terminal、explicit 和 remote-device 捕获模式 |
| **修改与 Mock** | Breakpoint、Map Local/Remote、header rule、blocking 和 latency rule | Breakpoint、Map Local/Remote、block list、network condition 和 JavaScript rule | Breakpoint、Rewrite、Map Local/Remote、blocking 和 throttling | Map Local/Remote、body/header 修改、blocking 和 server replay | Breakpoint 及基于 rule 的 rewrite、redirect、mock、error injection；部分 automation 受套餐限制 | rule、Breakpoint、redirect、response 修改和 mock |
| **重放与比较** | Compose/replay，并在本地并排比较 request、header 和 body | Compose、Repeat、Diff | Repeat 并编辑 request | client-side 和 server-side replay | 内置 HTTP 客户端用于编写和发送 request | API Composer、traffic replay 和 traffic comparison 标注为 beta |
| **WebSocket 工作流** | 检查 text/binary frame，并使用有界 Protobuf heuristic | 检查 WS/WSS；script 可修改 handshake URL/header，但不能修改 message | WebSocket 支持记录于官方版本历史 | WebSocket interception 和 scripting；不支持 WebSocket replay | WebSocket 检查及专用 rule | WebSocket capture 和 inspection |
| **脚本与扩展性** | sandboxed JavaScriptCore hook，API 有界且有执行 timeout | JavaScript request/response scripting | Rewrite rule 和 Control Web Interface；未记录通用 JavaScript scripting 功能 | Python add-on 和 command-line automation | 基于 rule 的 automation，以及公开源码和 proxy library | 基于 rule 的 automation；未记录 first-party 通用 scripting 功能 |
| **上游路由** | [HTTP/HTTPS upstream proxy 和 PAC URL routing](docs/features/upstream-proxy.mdx)；Community 禁用 proxy authentication 和 SOCKS5，bypass rule 最多 3 条 | external HTTP/HTTPS/SOCKS 和 PAC routing，支持 bypass rule | external HTTP/HTTPS/SOCKS proxy，支持 authentication 和 bypass rule | HTTP/HTTPS upstream mode，以及 reverse 和 SOCKS listener mode | system、HTTP、HTTPS、SOCKS upstream 设置；可能受套餐限制 | 自动链接 system proxy，并支持 reverse-proxy capture |
| **AI 与 MCP** | [应用内 AI Assistant](docs/features/ai-assistant.mdx)和[内置本地 MCP](docs/features/mcp.mdx)：10 个 read-only tool、token authentication，默认开启 redaction | 面向外部 AI client 的内置 MCP，包括 traffic read 和 app/rule control | 未记录 | 未记录 | 当前官方源码含 bundled local MCP bridge；未记录应用内 assistant | 内置 MCP 和 Pro-tier Debugging Assistant；当前文档要求把已捕获的 traffic details 粘贴到 chat |

### 相邻拦截工具

这些产品与 Rockxy 有意义地重叠，但在安全测试方面处于领先地位，
浏览器规则，或 API 客户端工作流程，而不是相同的通用目的
本机调试代理焦点。

| **产品** | **为何属于相邻工具** | **源码与构建模式** | **相关重叠能力** | **AI 与 MCP** |
|---|---|---|---|---|
| **Burp Suite** | 带 intercepting proxy 的 Web 安全测试套件 | 闭源应用；EULA 声明用户无权获得应用源码；extension 可采用单独许可 | proxy interception、match/replace、Repeater、WebSocket、upstream/SOCKS proxy 和大型 extension ecosystem | Repeater 提供 Burp AI；PortSwigger 还维护面向外部 AI client 的公开 MCP Server extension |
| **ZAP** | 安全 scanner 和 intercepting proxy | Apache-2.0 公开源码，可从源码构建 | intercept/edit、manual resend、WebSocket breakpoint 和 script、多语言 scripting、add-on 和 automation | 官方 MCP Integration add-on 和可选 LLM Support add-on |
| **Requestly HTTP Interceptor** | browser extension 和跨平台 desktop interceptor/mock tool | desktop interceptor 为 AGPL 公开源码；根据公开 community repository 的说明，单独的 API Client 是 proprietary | system-wide/browser capture、redirect、Map Local/Remote、header/body 修改、JavaScript transform、mock、delay/error simulation | 单独的官方 MCP server 管理 rule 和 group；未记录应用内 traffic-analysis assistant |

功能可用性可能因版本、计划、平台或附加组件而异。
“未记录”表示在官方第一方中未找到该功能
2026-08-22 上审查的来源；这并不能证明该能力不存在。
上述产品和功能声明已根据供应商文档进行检查，
供应商维护的源存储库，或该日期的供应商许可条款，以及
可能会改变。产品名称和商标属于其各自所有者；
Rockxy 不隶属于他们，也不受他们认可。欢迎指正
通过 Rockxy 问题跟踪器。

路线图包括：更深入的协议感知规则、更安全的编辑证据包、更强大的重播和比较工作流程、更广泛的开发人员设置指南以及持续的 HTTP/2 和 HTTP/3 研究。

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
- [AI Assistant](docs/features/ai-assistant.mdx) — 使用本地分析或经过明确 Review Data 的配置模型调查选中流量
- [筛选与搜索](docs/core-features/filters-and-search.mdx) — 使用侧边栏范围、Focus Sets、Noise Control、toolbar filter 和搜索
- [AI 与 Web3 检查](docs/features/ai-web3-inspection.mdx) — 检查已识别的模型 API、JSON-RPC 和 x402 风格流量
- [MCP 集成](docs/features/mcp.mdx) — 将 Rockxy 连接到本地 MCP 客户端
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

Rockxy 由独立维护。赞助有助于资助持续开发、发布基础设施、文档和安全工作。

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="赞助 Rockxy" />
  </a>
</p>

Rockxy 由 [Open Source Collective](https://docs.oscollective.org/) 提供财务托管。所有捐款和项目支出都会记录在 [Rockxy 的公开 Open Collective 页面](https://opencollective.com/rockxy)，让支持者可以透明查看资金的接收和使用情况。

| 等级 | 赞助金额 | 支持内容 |
|------|----------|----------|
| **Backer** | 每月 $5 起 | 开源维护、文档、测试和版本发布 |
| **Builder** | 每月 $25 起 | 回归测试、性能改进和日常调试工作流 |
| **Sponsor** | 每月 $100 | 长期维护重视隐私并持续免费提供给开发者的工具 |
| **Sustaining Sponsor** | 每月 $500 | 集中维护和产品开发，包括发布自动化与协议支持 |

**合作咨询** — 开发者工具公司、安全公司和企业团队，如需定制集成或白标方案：[rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## 支持

- [Open Collective](https://opencollective.com/rockxy/donate) — 通过透明的项目预算支持 Rockxy
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — 支持 Rockxy 的开发
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — 错误报告和功能请求
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — 问答和社区交流
- **邮箱** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **安全问题** — 查看 [SECURITY.md](SECURITY.md) 了解负责任的披露流程

## 许可证

[GNU Affero General Public License v3.0](LICENSE) — 版权所有 2024–2026 Rockxy Contributors。

## 星标历史

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. 使用 Swift、SwiftNIO、SwiftUI 和 AppKit 构建。</sub>
</p>
