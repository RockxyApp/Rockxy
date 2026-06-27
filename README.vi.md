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
  <strong>Debugging proxy mã nguồn mở, có thể kiểm tra cho macOS.</strong>
</p>

<p align="center">
  Chặn bắt, kiểm tra và chỉnh sửa lưu lượng HTTP/HTTPS/WebSocket/GraphQL bằng app Swift native mà bạn có thể kiểm tra, build và tin tưởng.<br>
  Được xây dựng cho workflow debug API, mobile, MCP-assisted, AI và blockchain-era khi Rockxy tiếp tục phát triển.<br>
  Giải pháp local-first, AGPL-3.0 thay thế cho <a href="#rockxy-vs-các-giải-pháp-khác">Proxyman và Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Phiên bản" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Nền tảng" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Giấy phép" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="Chào đón PR" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Tài trợ" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Light.png" alt="Rockxy chạy trên macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.27.2** — 2026-06-18

### Changed

- Enhance metadata privacy controls
- Refine metadata disclosure layout

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Các Điểm Nổi Bật Trên Nhánh Hiện Tại

- Upstream Proxy hiện bao gồm Automatic Proxy Configuration miễn phí/core với PAC URL routing cho các route `DIRECT`, HTTP và HTTPS, trong khi vẫn giữ nguyên boundary policy cho SOCKS5 và authentication.
- Export workflow hiện hỗ trợ OpenAPI YAML/HTML và publish selected traffic lên Gist với payload builder có awareness về redaction.
- Inspector tools hiện có JSONPath/key/value filtering và quick preview cho payload text được chọn, như JWT.
- Node.js Developer Setup hiện mirror selected client trong quá trình validation và có localhost sample guide đầy đủ hơn.
- Developer Setup Hub giờ bao phủ runtime, browser, client, device, framework và environment với snippet theo từng target, validation watcher, và guide content trung thực.
- WebSocket Protobuf vẫn tiếp tục là một phần trong hướng protocol inspection phong phú hơn của Rockxy.
- Public roadmap planning hiện bao gồm protocol-aware debugging cho AI traffic, Web3/RPC flows, x402-style payment flows, và chia sẻ debugging evidence đã redaction an toàn hơn.

## Tính Năng

Những công cụ bạn cần khi browser DevTools không còn đủ. Debug lưu lượng cốt lõi cho công việc Mac và iOS — native trên macOS, có public release và quy trình ưu tiên local.

### Chặn Bắt Lưu Lượng

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Kiểm tra lưu lượng HTTP, HTTPS, WebSocket và GraphQL từ bất kỳ ứng dụng Mac, CLI hay thiết bị iOS nào. Browser DevTools dừng lại ở trình duyệt — Rockxy nhìn thấy phần còn lại của stack.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Lọc & Tìm Kiếm Nâng Cao

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Thu hẹp hàng nghìn request đã bắt trong vài giây. Kết hợp filter theo method, host, status, header, body và process — hoặc chạy full-text search trên toàn bộ session.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### MCP Server cho AI Assistants

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Để Claude Desktop hoặc Cursor đọc traffic đã bắt qua một MCP server local. Hỏi "tại sao request này 500?" thay vì dán headers vào chat. Local, redaction-aware, và mã nguồn mở.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Copy-paste snippet proxy cho Python, Node.js, Go, Rust, cURL, Docker và browser, sau đó bấm Run Test để xác nhận traffic thực sự đang chạy qua.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Quản Lý Chứng Chỉ cho HTTPS Debugging

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Root CA P-256 ECDSA tạo ngay lần khởi động đầu tiên, niêm trong Keychain. Giải mã HTTPS ngay lần thử đầu; các host bị pin tự động đi qua không can thiệp.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL Proxy & Giải Mã HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Chọn host nào được giải mã TLS. Traffic được giải mã hiển thị header và JSON thật; phần còn lại đi qua dạng mã hoá. Quy tắc wildcard cho phép scope theo domain chỉ với một cú click.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Bỏ qua một số host để app pin chứng chỉ, dịch vụ nội bộ, hay telemetry ồn ào không bao giờ lọt vào capture. Wildcard giữ list ngắn gọn và log request tập trung đúng cái bạn quan tâm.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Khiến bất kỳ host nào fail. Cắt mạng quảng cáo, tracker bên thứ ba, hay dependency hay lỗi để xem app xuống cấp thế nào khi nó biến mất — không cần đổi một dòng code.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Phục vụ một file đã lưu hoặc một cây thư mục thay cho response thực. Đổi một payload JSON, replay một snapshot, hoặc pin một API bên thứ ba hay lỗi về bản local trong khi debug.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Đổi đích đến của request đã bắt mà không cần chạm vào code app hay /etc/hosts. Trỏ traffic production sang staging, dev server của bạn, hoặc máy đồng nghiệp để tái hiện bug có thể lặp lại.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Breakpoint & Rules

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Tạm dừng request hoặc response, sửa method, header, body hay status, rồi tiếp tục. Cách nhanh nhất để thử "điều gì xảy ra nếu API trả 401?" mà không phải đụng backend.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Modify Headers

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Thêm, gỡ hoặc thay header trên bất kỳ host nào mà không cần redeploy. Test thay đổi CORS, auth hay cache trong vài giây với preset có sẵn.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Custom Request & Response Headers

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Override header theo từng host với toàn quyền điều khiển cả hai phase. Inject auth token vào request đi ra, gỡ Set-Cookie ở response, hoặc pin một User-Agent tuỳ chỉnh — lưu lại dưới dạng named rule có thể bật/tắt bất cứ lúc nào.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Network Conditions

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Throttle về 3G, EDGE, LTE, WiFi hoặc delay tuỳ chỉnh. Laptop của bạn dùng fiber; người dùng thì không — xem UX ở 400 ms RTT trước khi họ thấy.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — Sửa & Replay

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Dựng lại bất kỳ request HTTP đã bắt — đổi method, URL, header, query param hay body — rồi gửi lại mà không cần rời Rockxy. Không cần vòng lặp copy-paste qua Postman, Insomnia hay curl. Iterate prompt LLM, fuzz biên auth, hoặc tái hiện một case lỗi cho OpenAI, Anthropic, Cohere endpoint trong vài giây.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### So Sánh

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Xếp hai response đã bắt cạnh nhau và bắt được mọi trường đã đổi — status, headers, JSON keys, body bytes. Bắt được regression API âm thầm, output LLM không deterministic và prompt drift mà không cần đẩy dữ liệu sang công cụ diff bên thứ ba. Side-by-side diff highlight phần đã đổi; deep JSON compare bỏ qua thứ tự key.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Custom Previewer Tabs

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Render body request và response theo cách bạn muốn. Pin thêm tab vào inspector cho JSON, GraphQL, JWT, image hay format riêng — dùng lại được trên mọi request đã bắt.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sessions & Export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Lưu session, import/export HAR cho handoff đa công cụ, copy bất kỳ request nào ra cURL hay JSON. Redact header authorization, cookie và bearer token trước khi chia sẻ — đưa cho đồng đội bug repro hoạt động được mà không lộ secret.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Multi-Tab Workspaces

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

Chạy các session capture độc lập song song — một tab cho staging, một cho prod, một cho build iOS device. Mỗi tab giữ filter, selection và state inspector riêng, nên chuyển context không tốn gì.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript Scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

Hook JS lên request và response cho các case mà rule tĩnh không phủ được — redact PII, ký token, viết lại payload. Lỗi hiện ra inline thay vì làm hỏng traffic.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Nhiều Tính Năng Sắp Ra Mắt

Các tính năng tương lai được theo dõi công khai và chỉ ship khi implementation, test, privacy behavior và documentation đã sẵn sàng.

### AI Traffic Inspection `Sắp Ra Mắt`

Làm cho model traffic dễ debug hơn ngay trong workflow capture bình thường. Detect AI request, inspect model call đã chọn, diagnose streaming response, compare prompt/output behavior, và hiểu tool-call chain mà không phải dán payload nhạy cảm vào dịch vụ khác.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Web3/RPC Inspection `Sắp Ra Mắt`

Biến network call của blockchain-era thành debugging evidence dễ đọc. Inspect JSON-RPC và Solana RPC traffic, group related calls thành flow, giải thích lỗi RPC phổ biến, và replay selected request mà không biến Rockxy thành wallet hay block explorer.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### x402 Payment Flow Debugging `Sắp Ra Mắt`

Hiểu payment-gated HTTP flow từ tầng network. Highlight payment-required response, theo dõi retry path, và giữ debugging evidence local với redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### Redacted Evidence Bundles `Sắp Ra Mắt`

Chia sẻ những dữ kiện cần để reproduce bug mà không leak secret. Package selected traffic với protocol summary, redaction preview, và source-backed context để đồng đội có thể audit.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Protocol-Aware Filters & Rules `Sắp Ra Mắt`

Dùng AI và Web3 metadata ở đúng nơi Rockxy đã hoạt động: filter, badge, optional column, comparison, rule, Developer Setup, và local MCP summary.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Chia Sẻ & Cộng Tác Theo Team `Sắp Ra Mắt`

Gửi một session đã bắt cho đồng đội chỉ với một cú click. Annotate request lỗi inline, thấy ai đang xem cái gì real-time, và pair-debug traffic HTTPS mà không cần share màn hình. Đặt mục tiêu cho một release tương lai.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% native macOS. Không Electron. Không web view. SwiftUI + AppKit + SwiftNIO.

## Bắt Đầu Nhanh

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Build và chạy trong Xcode. Cửa sổ Welcome sẽ hướng dẫn bạn cài đặt root CA, helper tool, và kích hoạt proxy.

**Yêu cầu:** macOS 14.0+, Xcode 16+, Swift 5.9

## Rockxy vs. Các Giải Pháp Khác

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Mô hình dự án** | Dự án mã nguồn mở AGPL-3.0 | Ứng dụng thương mại độc quyền | Ứng dụng thương mại độc quyền |
| **Mã nguồn** | Công khai, có thể kiểm tra, có thể fork | Mã nguồn đóng | Mã nguồn đóng |
| **Build từ mã nguồn** | Miễn phí với Xcode từ repo này | Không có mã nguồn công khai để build | Không có mã nguồn công khai để build |
| **Nền tảng macOS native** | Swift + SwiftNIO + SwiftUI/AppKit | Ứng dụng macOS thương mại native | Ứng dụng thương mại đa nền tảng |
| **Capture local-first** | Proxy, chứng chỉ, helper và dữ liệu capture ở trên máy Mac của bạn | Ứng dụng proxy desktop | Ứng dụng proxy desktop |
| **Workflow thiết lập developer** | Developer Setup Hub tích hợp cho runtime, client, device, framework và environment | Hướng dẫn thiết lập theo sản phẩm | Hướng dẫn thiết lập theo sản phẩm |
| **MCP/local automation bridge** | Tích hợp sẵn, xác thực bằng token, mặc định che giấu dữ liệu nhạy cảm | Chưa được nêu trong tài liệu công khai đã kiểm tra | Chưa được nêu trong tài liệu công khai đã kiểm tra |
| **Đường đóng góp mở** | Issues, discussions, roadmap và PR công khai | Sản phẩm do vendor kiểm soát | Sản phẩm do vendor kiểm soát |

Trên lộ trình: workflow replay/diff/rules/scripting sâu hơn, cải thiện kiểm tra WebSocket và GraphQL, protocol-aware debugging cho AI và Web3/RPC, visibility cho x402-style payment flow, và khám phá hỗ trợ gRPC/Protobuf cùng HTTP/2 và HTTP/3.

## Bảo Mật

Rockxy chặn bắt lưu lượng mạng — bảo mật là nền tảng, không phải tùy chọn.

- XPC helper xác thực caller bằng **so sánh chuỗi chứng chỉ**, không chỉ bundle ID
- Plugin chạy trong **JavaScriptCore sandbox** với timeout 5 giây, không truy cập filesystem/network
- **Kiểm tra đầu vào** trên mọi ranh giới — giới hạn kích thước body, giới hạn URI, chống regex DoS, chống path traversal
- Thông tin xác thực **tự động che giấu** trong log
- File nhạy cảm được lưu với **quyền 0o600**

Báo cáo lỗ hổng qua [SECURITY.md](SECURITY.md). Xem [kiến trúc bảo mật đầy đủ](docs/development/security.mdx) để biết chi tiết.

## Lộ Trình

Lộ trình công khai của Rockxy tập trung vào workflow và không cam kết ngày phát hành cố định. Nội dung ưu tiên độ tin cậy, UX macOS native, workflow debug, hỗ trợ giao thức, AI/Web3-era traffic visibility, tài liệu và onboarding cho contributor.

- [ROADMAP.md](ROADMAP.md): định hướng kỹ thuật công khai ở mức cao
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): trạng thái thực thi của các issue trong roadmap

## Tài Liệu

Tài liệu đầy đủ tại [Rockxy Docs](docs/index.mdx):

- [Hướng dẫn nhanh](docs/quickstart.mdx) — thiết lập và chạy trong vài phút
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — snippet theo runtime, guide cho device, validation probe và support matrix
- [Kiến trúc](docs/development/architecture.mdx) — proxy engine, actor model, luồng dữ liệu
- [Mô hình bảo mật](docs/development/security.mdx) — ranh giới tin cậy, xác thực XPC, quản lý chứng chỉ
- [Quyết định thiết kế](docs/development/design-decisions.mdx) — tại sao SwiftNIO, NSTableView, actors
- [Build từ mã nguồn](docs/development/building.mdx) — build, test, lint, và debug
- [Phong cách code](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, và quy ước
- [Changelog](CHANGELOG.md) — thay đổi chưa phát hành và các bản phát hành đã gắn tag

## Đóng Góp

Chào đón mọi đóng góp — code, test, tài liệu, báo lỗi, và phản hồi UX.

Xem **[CONTRIBUTING.md](CONTRIBUTING.md)** để biết hướng dẫn cài đặt, phong cách code, và checklist PR đầy đủ.

Các issue dành cho người mới được gắn nhãn [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Khi mở PR, bạn đồng ý với [CLA](CLA.md).

## Nhà Tài Trợ & Đối Tác

Rockxy được xây dựng và duy trì bởi các developer độc lập. Tài trợ giúp trang trải phát triển liên tục, kiểm tra bảo mật, và các tính năng mới.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Tài_trợ_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Tài trợ Rockxy" />
  </a>
</p>

| Hạng | Quyền lợi |
|------|-----------|
| **Gold Sponsor** | Logo trên README + trang docs, ưu tiên yêu cầu tính năng, kênh hỗ trợ trực tiếp |
| **Silver Sponsor** | Logo trên README, được ghi nhận trong ghi chú phát hành |
| **Bronze Sponsor** | Được ghi nhận trên README và docs |
| **Partner** | Đồng phát triển, hỗ trợ tích hợp, truy cập sớm các tính năng sắp ra mắt |

**Liên hệ hợp tác** — các công ty developer tools, công ty bảo mật, và đội ngũ enterprise cần tích hợp tùy chỉnh hoặc giải pháp white-label: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Hỗ Trợ

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — hỗ trợ phát triển Rockxy
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — báo lỗi và yêu cầu tính năng
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — câu hỏi và thảo luận cộng đồng
- **Email** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Vấn đề bảo mật** — xem [SECURITY.md](SECURITY.md) để báo cáo có trách nhiệm

## Giấy Phép

[GNU Affero General Public License v3.0](LICENSE) — Bản quyền 2024–2026 Rockxy Contributors.

## Lịch Sử Stars

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Xây dựng bằng Swift, SwiftNIO, SwiftUI, và AppKit.</sub>
</p>
