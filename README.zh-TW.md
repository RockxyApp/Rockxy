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
  <strong>適用於 macOS 的開源、可審核的調試代理程式。</strong>
</p>

<p align="center">
  使用您可以檢查、建置和信任的本機 Swift 應用程式攔截、檢查和修改 HTTP/HTTPS/WebSocket/GraphQL 流量。<br>
  隨著 Rockxy 的發展，專為 API、行動、MCP 輔助、人工智慧和區塊鏈時代調試工作流程而建置。<br>
  <a href="#rockxy-與替代品">Proxyman 和 Charles Proxy</a> 的 local-first、AGPL-3.0 替代方案。
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/26380?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-26380" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/26380/daily?language=Swift" alt="RockxyApp/Rockxy | Trendshift" width="250" height="55" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy running on macOS" width="800" />
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

## 目前分行亮點

- AI Assistant 現在可透過內建本機分析或選用的 Ollama/provider model 調查一個或多個已選 request，並提供明確的 Review Data 確認、有限度的 redaction、串流回應、evidence reveal 以及使用者主動觸發的 handoff。
- 原生 sidebar 現在提供可重複使用的 Focus Sets，用於 app/domain/path scope，並提供 workspace 層級的 Noise Control，在不停止 capture 的情況下隱藏相符的 domain 或 path。
- 主 workspace 現在為 Context Dock 與底部 inspector 使用原生垂直與水平 split view，保留全高度分隔線、協調的 toolbar/footer separator，並自動調整 layout。
- 上游代理現在包括免費/核心自動代理設定和 PAC URL 路由 `DIRECT` 、HTTP 和 HTTPS 路由，同時保留現有的 SOCKS5 和驗證原則邊界。
- 匯出工作流程現在涵蓋 OpenAPI YAML/HTML 和選定流量 Gist 發布以及編輯感知有效負載建置。
- 檢查器工具現在包括 JSONPath/鍵/值過濾以及所選負載文字（例如 JWT）的快速預覽。
- AI 與 Web3 流量檢查現在為已識別的 model call、JSON-RPC 流量與 x402 風格付款提示新增協定標籤、inspector 分頁與除錯摘要。
- Node.js 開發人員設定現在會在驗證期間鏡像所選用戶端，並具有更完整的本機主機範例指南。
- 開發人員設定中心現在涵蓋執行時間、瀏覽器、用戶端、裝置、框架和環境，以及特定於目標的程式碼片段、驗證觀察程式和誠實的指南內容。
- WebSocket binary-frame inspection 現在提供有限度、隨選的 Protobuf wire-format heuristic，不會把 decoder work 加入 capture hot path。
- 公開路線圖現在聚焦更深入的協定感知規則、replay、comparison 與更安全的編輯證據分享。

## 特點

當瀏覽器 DevTools 不夠用時，您可以使用的工具。適用於 Mac 和 iOS 的核心流量偵錯工作 — macOS 本機，具有公開版本和本地優先工作流程。

### 流量捕獲

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

檢查來自任何 Mac 應用程式、CLI 或 iOS 裝置的 HTTP、HTTPS、WebSocket 和 GraphQL 流量。瀏覽器 DevTools 在瀏覽器結束 — Rockxy 可以看到堆疊的其餘部分。

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### 進階過濾和搜尋

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

在幾秒鐘內縮小數千個捕獲的請求。組合方法、主機、狀態、標頭、正文和進程過濾器 - 或在整個會話中執行全文搜尋。

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets 與 Noise Control

將重複調查變成側邊欄內可重複使用的 scope。Focus Sets 結合 app/domain/path include 與 domain/path exclude，跨啟動保存並可供每個 workspace 使用。Noise Control 會繼續 capture telemetry 與其他低價值流量，但在目前 workspace 中將它們隱藏。

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant 在原生 request table 與側邊欄旁解釋已選流量" width="820" />

選取一個或多個已 capture request，詢問發生了什麼、哪裡失敗、有哪些變化，或下一步應驗證什麼。Rockxy 先在這台 Mac 上進行 evidence-grounded analysis；只有 Review Data 顯示精確、有限度且已編輯的 context 後，才會執行已設定的 Ollama 或 provider model。回應可定位來源 request 並準備原生 follow-up workflow，但 Assistant 不會自動修改流量或執行 action。

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[閱讀 AI Assistant 指南](docs/features/ai-assistant.mdx)。

### 外部 AI 用戶端的 MCP 伺服器

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

讓 Claude Desktop 或 Cursor 透過 Rockxy 本機 MCP 伺服器中的十個唯讀工具檢查已捕獲的流量。直接問「為什麼這個 500？」而不是把 header 貼進聊天。此實作為開源、以 token 驗證，並預設保持敏感資料 redaction 開啟。

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### 開發者設定中心

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

複製貼上 Python、Node.js、Go、Rust、cURL、Docker 和瀏覽器的代理片段，然後按一下「執行測試」以確認流量確實在流動。

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### HTTPS 偵錯的憑證管理

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

首次啟動時產生的 P-256 ECDSA 根 CA，密封在您的鑰匙圈中。第一次嘗試就解密 HTTPS；固定的主機會自動通過。

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL 代理程式和 HTTPS 解密

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

選擇哪些主機進行 TLS 解密。解密後的流量顯示真實的標頭和 JSON；其他一切都經過加密。通配符規則讓您可以一鍵按域確定範圍。

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### 繞過代理

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

跳過特定主機，因此憑證固定的應用程式、內部服務或雜訊的遙測永遠不會進入擷取範圍。通配符使清單保持簡短，並且您的請求日誌集中於您真正關心的內容。

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### 阻止列表

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

使任何主機發生故障。放棄廣告網路、第三方追蹤器或片狀依賴項，即可查看應用程式在消失後如何降級，而無需更改任何程式碼。

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### 本地地圖

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

提供已儲存的檔案或目錄樹來代替即時回應。在偵錯時交換 JSON 負載、重播快照或將不穩定的第三方 API 固定到本機副本。

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### 地圖遙控

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

重寫捕獲的請求的目標，而不觸及應用程式代碼或 /etc/hosts。將生產流量指向登台、您的開發伺服器或同事的機器，以進行可重現的錯誤重現。

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### 斷點和規則

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

暫停請求或回應，編輯方法、標頭、正文或狀態，然後繼續。測試「如果 API 回傳 401 該怎麼辦？」的最快方法無需觸及後端。

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### 修改標題

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

在任何主機上新增、刪除或取代標頭，無需重新部署。使用內建預設在幾秒鐘內測試 CORS、身份驗證或快取變更。

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### 自訂請求和回應標頭

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

把任意 request 或 response header 提升為流量表格中的一等欄位。保持 request 與 response 來源分離，儲存你關心的 header，然後無需開啟每個 inspector 即可掃視 request ID、trace ID、cache 狀態或自訂 metadata。

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### 網路狀況

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

調整至 3G、EDGE、LTE、WiFi 或自訂延遲。您的筆記型電腦使用光纖；您的用戶還沒有——在他們之前查看 400 毫秒 RTT 的用戶體驗。

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### 撰寫 — 編輯與重播

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

重建任何捕獲的 HTTP 請求 - 更改 method、URL、header、query 參數或 body - 並在不離開 Rockxy 的情況下重新發送。無需 Postman、Insomnia 或 curl 的複製貼上循環。迭代 LLM prompt、模糊 auth 邊界，或在幾秒鐘內重現 OpenAI、Anthropic 和 Cohere 端點的失敗案例。

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### 比較

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

將兩個捕獲的 transaction 或貼上的 payload 並排堆疊，找出每個翻轉的欄位 - 狀態、header、JSON key 或 body 位元組。捕捉靜默的 API 迴歸、非確定性的 LLM 輸出和 prompt drift，而無需將任何內容送入第三方 diff 工具。

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### 自訂預覽器標籤

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

按照您想要的方式呈現請求和回應正文。將額外的選項卡固定到 JSON、GraphQL、JWT、圖像或您自己的格式的檢查器上 - 可在每個捕獲的請求中重複使用。

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### 會話和導出

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

儲存會話，匯入/匯出 HAR 以進行跨工具切換，將任何請求複製為 cURL 或 JSON。在共享之前編輯授權標頭、cookie 和不記名令牌 — 在不洩露秘密的情況下向隊友提供工作錯誤重現。

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### 多選項卡工作區

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy 多分頁工作區顯示同一即時 capture 的獨立 filter view" width="820" />

在同一個即時 capture 上並排保留獨立調查 view — 一個分頁用於 staging 流量，一個用於 production，一個用於 iOS 裝置流程。每個分頁擁有自己的 filter、sorting、selection、sidebar scope 與 inspector state，同時共用 proxy 和已 capture transaction。

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript 腳本

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS 掛鉤靜態規則無法涵蓋的情況的請求和回應 - 編輯 PII、簽名令牌、重寫有效負載。錯誤會內聯顯示，而不是破壞流量。

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## 協定感知檢查

Rockxy 已在一般 HTTP debugging workflow 中提供協定感知的 AI、Web3 RPC 與 x402 檢查。

### AI 流量檢查

Rockxy 在一般 capture workflow 中偵測已識別的 AI 請求。檢查選定的 model call、串流狀態、可用時的 usage 欄位、警告、retrieval hint 與 tool-call 摘要，而無需將敏感 payload 貼到其他服務。

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC 檢查

Rockxy 將區塊鏈時代的網路呼叫變成可讀的除錯證據。檢查 EVM 與 Solana-style HTTP JSON-RPC 流量，包括 provider host、request ID、method、batch summary、error、chain、transaction、payload 和 debug-intent detail，而不會把 Rockxy 變成 wallet 或 block explorer。

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 支付流程提示

Rockxy 突顯 payment-required 與 retry 導向的提示，讓 payment-gated HTTP 流程可從網路層理解，同時除錯證據維持在本機且 redaction-aware。

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## 未來工作

以下章節描述公開方向，而不是目前行為。

### 協定感知規則

Rockxy 現在已可標記並檢查 AI 與 Web3 流量。按 model、tool call、JSON-RPC method、chain、transaction hash 或 batch subcall 進行更深入的規則比對仍屬未來工作；目前的流量修改工具仍以 URL、HTTP method 和 header 進行比對。

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### 已編輯的證據包 `即將推出`

分享重現錯誤所需的事實而不洩露秘密。將選定的流量與協議摘要、編輯預覽和團隊成員可以審核的來源支援的上下文打包在一起。

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### 團隊共享與協作 `即將推出`

一鍵將捕獲的會話傳送給隊友。內嵌註解失敗的請求，即時查看誰在查看什麼內容，並在無需螢幕共享的情況下對 HTTPS 流量進行配對偵錯。面向未來版本。

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 原生 macOS 應用程式外殼 — 沒有 Electron。SwiftUI + AppKit + SwiftNIO，WebKit 僅用於 HTML body 預覽。

## 快速入門

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

在 Xcode 中建置並運行。歡迎視窗將引導您完成根 CA 設定、幫助程式安裝和代理程式啟動。

**要求：** macOS 14.0+、Xcode 16+、Swift 5.9

如果您想在安裝後將 Rockxy 連接到本機 MCP 用戶端，請參閱 [MCP 整合指南](docs/features/mcp.mdx).

## Rockxy 與替代方案

主要矩陣涵蓋通用網路調試代理。安全測試
套件和麵向瀏覽器/API 的攔截器具有大量工作流程重疊
單獨列出，因此不同的產品不能互換。
封包分析器和僅 API 的用戶端不在此比較範圍內。

### 直接網路偵錯代理

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **產品形態** | 原生 macOS 偵錯代理 | 原生 macOS 應用程式；Windows/Linux 版本以 Electron 為基礎 | 跨平台桌面偵錯代理 | 跨平台 CLI/TUI 與 Web UI 代理工具組 | 跨平台 Electron 桌面代理與 HTTP 用戶端 | 跨平台桌面偵錯代理 |
| **原始碼與建置模式** | Community 原始碼依 AGPL-3.0-or-later 公開，可用 Xcode 建置；官方 DMG 另含非公開 downstream 元件 | 閉源；在已審閱的官方資料中未發現公開的應用程式原始碼 | 閉源；在已審閱的官方資料中未發現公開的應用程式原始碼 | MIT 授權的公開原始碼，可從原始碼建置 | AGPL 公開桌面原始碼，可從原始碼建置；發佈的 binary 另有授權選項 | 閉源；依 Fiddler Everywhere EULA 以 object code 發佈 |
| **擷取與設定** | 本機系統代理，為 Mac 應用程式、runtime、iOS 裝置及 Simulator 提供引導式設定 | 自動設定 Mac 應用程式、runtime 與行動裝置 | 本機代理，提供 macOS、iOS 及跨平台設定指南 | regular、local-process、WireGuard、reverse、transparent 等擷取模式 | 面向瀏覽器、runtime、container 與行動裝置的 targeted/manual proxy interception | system、network、browser、terminal、explicit 及 remote-device 擷取模式 |
| **修改與 Mock** | Breakpoint、Map Local/Remote、header rule、blocking 與 latency rule | Breakpoint、Map Local/Remote、block list、network condition 與 JavaScript rule | Breakpoint、Rewrite、Map Local/Remote、blocking 與 throttling | Map Local/Remote、body/header 修改、blocking 與 server replay | Breakpoint 及 rule-based rewrite、redirect、mock、error injection；部分 automation 受方案限制 | rule、Breakpoint、redirect、response 修改與 mock |
| **重播與比較** | Compose/replay，並在本機並排比較 request、header 與 body | Compose、Repeat、Diff | Repeat 並編輯 request | client-side 與 server-side replay | 內建 HTTP 用戶端用於編寫及傳送 request | API Composer、traffic replay 與 traffic comparison 標示為 beta |
| **WebSocket 工作流程** | 檢查 text/binary frame，並採用有界 Protobuf heuristic | 檢查 WS/WSS；script 可修改 handshake URL/header，但不能修改 message | WebSocket 支援記錄於官方版本歷史 | WebSocket interception 與 scripting；不支援 WebSocket replay | WebSocket 檢查及專用 rule | WebSocket capture 與 inspection |
| **腳本與擴充性** | sandboxed JavaScriptCore hook，API 有界並設有執行 timeout | JavaScript request/response scripting | Rewrite rule 與 Control Web Interface；未記錄通用 JavaScript scripting 功能 | Python add-on 與 command-line automation | rule-based automation，以及公開原始碼與 proxy library | rule-based automation；未記錄 first-party 通用 scripting 功能 |
| **上游路由** | [HTTP/HTTPS upstream proxy 與 PAC URL routing](docs/features/upstream-proxy.mdx)；Community 停用 proxy authentication 與 SOCKS5，bypass rule 最多 3 條 | external HTTP/HTTPS/SOCKS 與 PAC routing，支援 bypass rule | external HTTP/HTTPS/SOCKS proxy，支援 authentication 與 bypass rule | HTTP/HTTPS upstream mode，以及 reverse 與 SOCKS listener mode | system、HTTP、HTTPS、SOCKS upstream 設定；可能受方案限制 | 自動串接 system proxy，並支援 reverse-proxy capture |
| **AI 與 MCP** | [應用程式內 AI Assistant](docs/features/ai-assistant.mdx)與[內建本機 MCP](docs/features/mcp.mdx)：10 個 read-only tool、token authentication，預設啟用 redaction | 面向外部 AI client 的內建 MCP，包括 traffic read 與 app/rule control | 未記錄 | 未記錄 | 目前官方原始碼含 bundled local MCP bridge；未記錄應用程式內 assistant | 內建 MCP 與 Pro-tier Debugging Assistant；目前文件要求將已擷取的 traffic details 貼到 chat |

### 相鄰攔截工具

這些產品與 Rockxy 有意義地重疊，但在安全測試方面處於領先地位，
瀏覽器規則，或 API 用戶端工作流程，而不是相同的通用目的
本機調試代理焦點。

| **產品** | **為何屬於相鄰工具** | **原始碼與建置模式** | **相關重疊能力** | **AI 與 MCP** |
|---|---|---|---|---|
| **Burp Suite** | 具 intercepting proxy 的 Web 安全測試套件 | 閉源應用程式；EULA 聲明使用者無權取得應用程式原始碼；extension 可採用個別授權 | proxy interception、match/replace、Repeater、WebSocket、upstream/SOCKS proxy 與大型 extension ecosystem | Repeater 提供 Burp AI；PortSwigger 亦維護面向外部 AI client 的公開 MCP Server extension |
| **ZAP** | 安全 scanner 與 intercepting proxy | Apache-2.0 公開原始碼，可從原始碼建置 | intercept/edit、manual resend、WebSocket breakpoint 與 script、多語言 scripting、add-on 與 automation | 官方 MCP Integration add-on 與選用 LLM Support add-on |
| **Requestly HTTP Interceptor** | browser extension 與跨平台 desktop interceptor/mock tool | desktop interceptor 為 AGPL 公開原始碼；依公開 community repository 說明，獨立 API Client 為 proprietary | system-wide/browser capture、redirect、Map Local/Remote、header/body 修改、JavaScript transform、mock、delay/error simulation | 獨立的官方 MCP server 管理 rule 與 group；未記錄應用程式內 traffic-analysis assistant |

功能可用性可能會因版本、計劃、平台或附加元件而異。
「未記錄」表示在官方第一方中找不到該功能
2026-08-22 上審查的來源；這並不能證明該能力不存在。
上述產品和功能聲明已根據供應商文件進行檢查，
供應商維護的來源儲存庫，或該日期的供應商授權條款，以及
可能會改變。產品名稱和商標屬於其各自所有者；
Rockxy 不隸屬於他們，也不受他們認可。歡迎指正
透過 Rockxy 問題追蹤器。

路線圖包括：更深入的協定感知規則、更安全的編輯證據包、更強大的重播和比較工作流程、更廣泛的開發人員設定指南以及持續的 HTTP/2 和 HTTP/3 研究。

## 安全性

Rockxy 攔截網路流量－安全性是基礎，而不是可選的。

- XPC 助手透過以下方式驗證呼叫者 **憑證鏈比較**，不僅僅是包 ID
- 插件運行在 **沙盒 JavaScriptCore** 5 秒超時，無檔案系統/網路訪問
- **輸入驗證** 所有邊界 - 正文大小上限、URI 限制、正規表示式 DoS 保護、路徑遍歷預防
- 憑證 **自動編輯** 在捕獲的日誌中
- 儲存的敏感文件 **0o600 權限**

透過報告漏洞 [安全.md](SECURITY.md)。請參閱 [完整的安全架構](docs/development/security.mdx) 了解詳情。

## 路線圖

Rockxy 的公共路線圖以工作流程為導向且無日期限制。它專注於可靠性、原生 macOS UX、調試工作流程、協議支援、AI/Web3 時代的流量可見性、文件和貢獻者入門。

- [路線圖.md](ROADMAP.md)：高層次公共工程方向
- [Rockxy 公共路線圖](https://github.com/orgs/RockxyApp/projects/1)：路線圖追蹤問題的營運可見性

## 文件

完整文檔可在 [Rockxy 文檔](docs/index.mdx):

- [快速入門指南](docs/quickstart.mdx) — 幾分鐘內即可啟動並運行
- [開發者設定中心](docs/features/developer-setup-hub.mdx) — 運行時片段、設備指南、驗證探針和支援矩陣
- [AI Assistant](docs/features/ai-assistant.mdx) — 使用本機分析或經 Review Data 的 configured model 調查所選流量
- [過濾與搜尋](docs/core-features/filters-and-search.mdx) — sidebar scope、Focus Sets、Noise Control、toolbar filter 與搜尋
- [AI 與 Web3 檢查](docs/features/ai-web3-inspection.mdx) — 檢查已識別的 model API、JSON-RPC 與 x402 流量
- [MCP集成](docs/features/mcp.mdx) — 將 Rockxy 連接到本機 MCP 用戶端
- [大樓](docs/development/architecture.mdx) — 代理引擎、參與者模型、資料流
- [安全模型](docs/development/security.mdx) — 信任邊界、XPC 驗證、憑證管理
- [設計決策](docs/development/design-decisions.mdx) — 為什麼要使用 SwiftNIO、NSTableView、actors
- [從源頭構建](docs/development/building.mdx) — 建置、測試、lint 和調試
- [程式碼風格](docs/development/code-style.mdx) — SwiftLint、SwiftFormat 與約定
- [變更日誌](CHANGELOG.md) - 未發布的作品和標記的版本

## 貢獻

歡迎貢獻—程式碼、測試、文件、錯誤報告和使用者體驗回饋。

參見 **[貢獻.md](CONTRIBUTING.md)** 有關設定說明、程式碼樣式和完整的 PR 清單。

好的第一個問題已被標記 [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue)。提交 PR 即表示您同意 [共軛亞麻油酸](CLA.md).

## 贊助商及合作夥伴

Rockxy 由獨立維護。贊助有助於資助持續開發、發布基礎設施、文件和安全工作。

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy 由 [Open Source Collective](https://docs.oscollective.org/) 提供財務託管。所有捐款與專案支出都記錄在 [Rockxy 的公開 Open Collective 頁面](https://opencollective.com/rockxy)，讓支持者能透明查看資金的接收與使用方式。

| 等級 | 贊助金額 | 支援內容 |
|------|----------|----------|
| **Backer** | 每月 $5 起 | 開源維護、文件、測試與版本發布 |
| **Builder** | 每月 $25 起 | 回歸測試、效能改善與日常除錯工作流程 |
| **Sponsor** | 每月 $100 | 長期維護重視隱私且持續免費提供給開發者的工具 |
| **Sustaining Sponsor** | 每月 $500 | 集中維護與產品開發，包括版本發布自動化與協定支援 |

**合作夥伴查詢** — 尋求客製化整合或白標解決方案的開發工具公司、安全公司和企業團隊： [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## 支援

- [Open Collective](https://opencollective.com/rockxy/donate) — 透過透明的專案預算支持 Rockxy
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — 支持Rockxy的發展
- [GitHub 問題](https://github.com/RockxyApp/Rockxy/issues) — 錯誤回報和功能請求
- [GitHub 討論](https://github.com/RockxyApp/Rockxy/discussions) — 問題和社群聊天
- **電子郵件** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **安全問題** — 參見 [安全.md](SECURITY.md) 負責任的揭露

## 許可證

[GNU Affero 通用公共授權 v3.0](LICENSE) — 版權所有 2024–2026 Rockxy 貢獻者。

## 明星歷史

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>製造者： <a href="https://github.com/LocNguyenHuu">Stephen</a>。使用 Swift、SwiftNIO、SwiftUI 和 AppKit 建置。</sub>
</p>
