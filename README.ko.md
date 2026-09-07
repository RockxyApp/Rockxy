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
  <strong>macOS용 오픈소스, 감사 가능한 디버깅 프록시.</strong>
</p>

<p align="center">
  직접 검사하고 빌드하며 신뢰할 수 있는 네이티브 Swift 앱으로 HTTP/HTTPS/WebSocket/GraphQL 트래픽을 가로채고, 검사하고, 수정하세요.<br>
  Rockxy가 진화하면서 API, 모바일, MCP 지원, AI, 블록체인 시대의 디버깅 워크플로까지 품도록 설계되었습니다.<br>
  <a href="#rockxy-vs-대안-도구">Proxyman과 Charles Proxy</a>를 대체하는 local-first, AGPL-3.0 선택지.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="릴리스" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="플랫폼" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="라이선스" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PR 환영" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="후원" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/26380?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-26380" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/26380/daily?language=Swift" alt="RockxyApp/Rockxy | Trendshift" width="250" height="55" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="macOS에서 실행 중인 Rockxy" width="800" />
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

## 현재 브랜치 하이라이트

- AI Assistant는 내장 로컬 분석 또는 설정된 Ollama/provider model로 선택한 하나 이상의 request를 조사하며, 명시적 Review Data, 제한된 redaction, streaming response, evidence reveal, 사용자 주도 handoff를 제공합니다.
- 네이티브 sidebar에 app/domain/path scope를 재사용하는 Focus Sets와 capture를 멈추지 않고 일치하는 domain/path를 숨기는 workspace별 Noise Control이 추가되었습니다.
- Main workspace는 Context Dock과 bottom inspector에 네이티브 세로/가로 split view를 사용해 전체 높이 divider, 정렬된 toolbar/footer separator, 자동 layout resize를 유지합니다.
- Upstream Proxy는 이제 `DIRECT`, HTTP, HTTPS route를 위한 PAC URL routing 기반 free/core Automatic Proxy Configuration을 포함하며, 기존 SOCKS5 및 인증 policy boundary를 유지합니다.
- Export workflow는 이제 OpenAPI YAML/HTML과 redaction-aware payload building을 적용한 selected-traffic Gist publishing을 지원합니다.
- Inspector tools는 이제 JSONPath/key/value filtering과 JWT 같은 선택된 payload text의 quick preview를 포함합니다.
- AI/Web3 traffic inspection은 인식된 model call, JSON-RPC traffic, x402-style payment hint에 protocol label, inspector tab, debug summary를 제공합니다.
- Node.js Developer Setup은 validation 중 선택된 client를 mirror하며, 더 충실한 localhost sample guide를 제공합니다.
- Developer Setup Hub는 런타임, 브라우저, 클라이언트, 디바이스, 프레임워크, 환경 전반을 대상으로 타깃별 스니펫, 검증 워처, 정직한 가이드를 제공합니다.
- WebSocket binary-frame inspection은 capture hot path에 decoder work를 추가하지 않는 제한적 온디맨드 Protobuf wire-format heuristic을 지원합니다.
- Public roadmap은 더 깊은 protocol-aware rules, replay, comparison, 안전한 redacted evidence sharing에 집중합니다.

## 기능

브라우저 DevTools만으로 부족할 때 손이 가는 도구들. Mac과 iOS 작업을 위한 핵심 트래픽 디버깅 — macOS 네이티브, 공개 릴리스, 로컬 우선 워크플로우.

### 트래픽 캡처

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

모든 Mac 앱, CLI 또는 iOS 기기의 HTTP, HTTPS, WebSocket, GraphQL 트래픽을 검사합니다. 브라우저 DevTools는 브라우저에서 끝나지만 — Rockxy는 스택의 나머지 부분까지 봅니다.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### 고급 필터 및 검색

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

수천 개의 캡처된 요청을 몇 초 안에 좁힙니다. 메서드, 호스트, 상태, 헤더, 본문, 프로세스 필터를 조합하거나 전체 세션에 대한 전체 텍스트 검색을 실행하세요.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets & Noise Control

반복 조사를 sidebar의 재사용 가능한 scope로 만듭니다. Focus Sets는 application/domain/path include와 domain/path exclude를 결합하고 재실행 후에도 유지되며 모든 workspace에서 사용할 수 있습니다. Noise Control은 telemetry 같은 낮은 가치의 traffic을 계속 capture하되 현재 workspace에서는 숨깁니다.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="네이티브 request table과 sidebar 옆에서 선택 traffic을 설명하는 Rockxy AI Assistant" width="820" />

하나 이상의 capture request를 선택하고 무슨 일이 있었는지, 무엇이 실패했는지, 무엇이 바뀌었는지, 다음에 무엇을 확인할지 물어보세요. Rockxy는 먼저 이 Mac에서 evidence-grounded analysis를 수행하며, 설정된 Ollama/provider model은 Review Data가 제한되고 redaction된 context를 명확히 보여준 뒤에만 실행됩니다. 응답은 source request를 reveal하고 follow-up workflow를 준비할 수 있지만 traffic 수정이나 action을 자동 실행하지 않습니다.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[AI Assistant 가이드 읽기](docs/features/ai-assistant.mdx).

### 외부 AI 클라이언트용 MCP 서버

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Claude Desktop 또는 Cursor가 Rockxy의 로컬 MCP 서버에 있는 10개의 읽기 전용 도구로 캡처한 트래픽을 검사하게 합니다. 채팅에 헤더를 붙여넣는 대신 "왜 500이 났지?"라고 바로 물어보세요. 구현은 오픈소스이며 토큰 인증을 사용하고 민감 데이터 redaction을 기본으로 유지합니다.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Python, Node.js, Go, Rust, cURL, Docker 및 브라우저용 프록시 스니펫을 복사 붙여넣기한 다음 Run Test를 클릭해 트래픽이 실제로 흐르는지 확인하세요.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### HTTPS 디버깅용 인증서 관리

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

처음 실행 시 생성된 P-256 ECDSA 루트 CA를 Keychain에 봉인합니다. HTTPS를 첫 시도에 복호화하고, 핀된 호스트는 자동으로 우회됩니다.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL 프록시 및 HTTPS 복호화

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

어떤 호스트에서 TLS 복호화할지 선택합니다. 복호화된 트래픽은 실제 헤더와 JSON을 보여주고, 나머지는 암호화된 상태로 통과합니다. 와일드카드 규칙으로 한 번의 클릭으로 도메인 단위 범위를 지정할 수 있습니다.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

특정 호스트를 건너뛰어 인증서가 핀된 앱, 내부 서비스 또는 시끄러운 텔레메트리가 캡처에 들어오지 않게 합니다. 와일드카드로 목록을 짧게 유지하고 요청 로그를 정말 신경 쓰는 것에 집중시킵니다.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

어떤 호스트든 실패시킵니다. 광고 네트워크, 서드파티 트래커 또는 불안정한 종속성을 잘라내 사라졌을 때 앱이 어떻게 저하되는지 — 코드 한 줄 바꾸지 않고 — 봅니다.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

실제 응답 대신 저장된 파일이나 디렉토리 트리를 제공합니다. JSON 페이로드를 바꾸거나 스냅샷을 재생하거나 디버깅 중에만 불안정한 서드파티 API를 로컬 복사본으로 고정할 수 있습니다.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

앱 코드나 /etc/hosts를 건드리지 않고 캡처된 요청의 목적지를 다시 작성합니다. 프로덕션 트래픽을 스테이징, 개발 서버 또는 동료의 머신으로 보내 재현 가능한 버그 repro를 만듭니다.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### 브레이크포인트 & 규칙

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

요청이나 응답을 일시 정지하고 method, header, body, status를 편집한 다음 계속합니다. 백엔드를 건드리지 않고 "API가 401을 반환하면?"을 가장 빠르게 테스트하는 방법입니다.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### 헤더 수정

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

재배포 없이 모든 호스트의 헤더를 추가, 제거 또는 교체합니다. 내장 프리셋으로 CORS, 인증 또는 캐시 변경을 몇 초 안에 테스트하세요.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### 커스텀 요청 & 응답 헤더

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

모든 요청 또는 응답 헤더를 트래픽 테이블의 일급 열로 승격합니다. 요청과 응답 소스를 분리해 유지하고, 관심 있는 헤더를 저장한 뒤 각 inspector를 열지 않고도 request ID, trace ID, cache 상태, 커스텀 메타데이터를 훑어볼 수 있습니다.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### 네트워크 조건

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

3G, EDGE, LTE, WiFi 또는 커스텀 지연으로 throttle합니다. 당신의 노트북은 광섬유지만 사용자는 그렇지 않습니다 — 사용자가 보기 전에 400 ms RTT에서 UX를 확인하세요.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — 편집 & 재생

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

캡처된 모든 HTTP 요청을 다시 구성 — method, URL, header, 쿼리 파라미터, body 변경 — 후 Rockxy를 떠나지 않고 재전송합니다. Postman, Insomnia, curl 복사 붙여넣기 루프가 필요 없습니다. LLM 프롬프트를 반복하고 인증 경계를 퍼지하고 OpenAI, Anthropic, Cohere 엔드포인트의 실패 케이스를 몇 초 안에 재현합니다.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### 비교

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

캡처된 두 transaction 또는 붙여넣은 payload를 나란히 쌓고 뒤집힌 모든 필드를 찾아냅니다 — status, header, JSON 키, body 바이트. 서드파티 diff 도구에 아무것도 넘기지 않고 조용한 API 회귀, 비결정적 LLM 출력, 프롬프트 드리프트를 잡아냅니다.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### 커스텀 프리뷰어 탭

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

요청과 응답 body를 원하는 방식으로 렌더링합니다. JSON, GraphQL, JWT, 이미지 또는 자체 포맷용 탭을 inspector에 고정 — 모든 캡처 요청에서 재사용할 수 있습니다.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### 세션 & 내보내기

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

세션을 저장하고 도구 간 핸드오프를 위해 HAR을 import/export하며, 모든 요청을 cURL 또는 JSON으로 복사합니다. 공유 전에 authorization 헤더, 쿠키 및 bearer 토큰을 redact — 비밀을 누출하지 않고 동료에게 작동하는 버그 repro를 건넵니다.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### 멀티탭 워크스페이스

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="같은 live capture의 독립적으로 filter된 view를 보여주는 Rockxy multi-tab workspace" width="820" />

같은 live capture에 대한 독립적인 조사 view를 나란히 유지합니다 — 한 tab은 staging 트래픽, 하나는 production, 하나는 iOS 기기 플로우용. 각 tab은 자체 filter, sort, selection, sidebar scope, inspector state를 가지면서 proxy와 capture transaction을 공유합니다.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript 스크립팅

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

정적 규칙으로 다룰 수 없는 경우를 위해 요청과 응답에 JS 훅을 답니다 — PII redact, 토큰 서명, 페이로드 재작성. 오류는 트래픽을 손상시키지 않고 inline으로 표시됩니다.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## 프로토콜 인식 검사

Rockxy는 일반 HTTP debugging workflow 안에서 AI, Web3 RPC, x402 protocol-aware inspection을 제공합니다.

### AI 트래픽 검사

Rockxy는 일반 capture workflow 안에서 인식된 AI request를 감지합니다. 선택한 model call, streaming state, 존재할 때의 usage 필드, warning, retrieval hint, tool-call summary를 민감한 payload를 다른 서비스에 붙여넣지 않고 검사합니다.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC 검사

Rockxy는 블록체인 시대의 네트워크 호출을 읽기 쉬운 디버깅 증거로 바꿉니다. EVM 및 Solana 스타일 HTTP JSON-RPC traffic을 provider host, request ID, method, batch summary, error, chain, transaction, payload, debug-intent detail과 함께 inspect하되 Rockxy를 wallet이나 block explorer로 만들지 않습니다.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 Payment Flow Hints

Rockxy는 payment-required 및 retry 지향 힌트를 강조해 payment-gated HTTP flow를 네트워크 계층에서 이해할 수 있게 하며, 그동안 디버깅 증거는 로컬에 남고 redaction-aware를 유지합니다.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## 향후 작업

다음 항목은 현재 동작이 아닌 공개 방향입니다.

### Protocol-Aware Rules

Rockxy는 현재 AI/Web3 traffic을 label하고 inspect합니다. model, tool call, JSON-RPC method, chain, transaction hash, batch subcall 기반의 깊은 rule matching은 향후 작업이며, 현재 traffic modification tool은 URL, HTTP method, header로 match합니다.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Redacted Evidence Bundles `곧 출시`

secret을 유출하지 않고 bug repro에 필요한 사실을 공유합니다. selected traffic을 protocol summary, redaction preview, source-backed context와 함께 패키징해 동료가 감사할 수 있게 합니다.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### 팀 공유 & 협업 `곧 출시`

한 번의 클릭으로 캡처된 세션을 동료에게 보냅니다. 실패한 요청에 inline 주석을 달고 누가 무엇을 보고 있는지 실시간으로 확인하며 화면 공유 없이 HTTPS 트래픽을 pair-debug합니다. 향후 릴리스를 목표로 합니다.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 네이티브 macOS 앱 셸 — Electron 없음. SwiftUI + AppKit + SwiftNIO, WebKit은 HTML body 미리보기에만 사용.

## 빠른 시작

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Xcode에서 빌드하고 실행. 환영 윈도우가 루트 CA 설정, 헬퍼 설치, 프록시 활성화를 안내합니다.

**요구 사항:** macOS 14.0+, Xcode 16+, Swift 5.9

설치 후 Rockxy를 로컬 MCP 클라이언트에 연결하려면 [MCP 연동 가이드](docs/features/mcp.mdx)를 참조하세요.

## Rockxy 대 대안

주요 매트릭스는 범용 웹 디버깅 프록시를 다룹니다. 보안 테스트
상당한 작업 흐름이 겹치는 제품군 및 브라우저/API 지향 인터셉터
서로 다른 제품이 별도로 나열되어 있으므로 서로 바꿔 사용할 수 있는 것으로 표시되지 않습니다.
패킷 분석기와 API 전용 클라이언트는 이 비교 대상에서 제외됩니다.

### 직접 웹 디버깅 프록시

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **제품 형태** | macOS 네이티브 디버깅 프록시 | macOS 네이티브 앱, Windows/Linux 버전은 Electron 기반 | 크로스플랫폼 데스크톱 디버깅 프록시 | 크로스플랫폼 CLI/TUI 및 Web UI 프록시 툴킷 | 크로스플랫폼 Electron 데스크톱 프록시 및 HTTP 클라이언트 | 크로스플랫폼 데스크톱 디버깅 프록시 |
| **소스 및 빌드 모델** | Community 소스는 AGPL-3.0-or-later로 공개되며 Xcode로 빌드 가능. 공식 DMG에는 비공개 downstream 구성 요소도 포함 | 비공개 소스. 검토한 공식 자료에서 공개 애플리케이션 소스를 확인하지 못함 | 비공개 소스. 검토한 공식 자료에서 공개 애플리케이션 소스를 확인하지 못함 | MIT 라이선스 공개 소스. 소스에서 빌드 가능 | AGPL 공개 데스크톱 소스. 소스에서 빌드 가능하며 배포 바이너리에는 추가 라이선스 옵션이 있음 | 비공개 소스. Fiddler Everywhere EULA에 따라 object code로 배포 |
| **캡처 및 설정** | Mac 앱, 런타임, iOS 기기 및 Simulator를 위한 안내식 로컬 시스템 프록시 설정 | Mac 앱, 런타임 및 모바일 기기 자동 설정 | macOS, iOS 및 크로스플랫폼 설정 가이드를 제공하는 로컬 프록시 | regular, local-process, WireGuard, reverse, transparent 등 다양한 캡처 모드 | 브라우저, 런타임, 컨테이너 및 모바일 기기를 위한 targeted/manual proxy interception | system, network, browser, terminal, explicit 및 remote-device 캡처 모드 |
| **수정 및 모킹** | Breakpoint, Map Local/Remote, header rule, blocking 및 latency rule | Breakpoint, Map Local/Remote, block list, network condition 및 JavaScript rule | Breakpoint, Rewrite, Map Local/Remote, blocking 및 throttling | Map Local/Remote, body/header 수정, blocking 및 server replay | Breakpoint와 rule 기반 rewrite, redirect, mock, error injection. 일부 automation은 요금제 제한 | rule, Breakpoint, redirect, response 수정 및 mock |
| **리플레이 및 비교** | Compose/replay와 request, header, body의 로컬 나란히 비교 | Compose, Repeat, Diff | request 반복 및 편집 | client-side 및 server-side replay | request 작성 및 전송을 위한 내장 HTTP 클라이언트 | API Composer, traffic replay 및 traffic comparison은 beta로 문서화 |
| **WebSocket 워크플로** | 제한된 Protobuf heuristic을 포함한 text/binary frame 검사 | WS/WSS 검사. script는 handshake URL/header를 수정할 수 있지만 message는 수정하지 못함 | WebSocket 지원은 공식 버전 기록에 문서화 | WebSocket interception 및 scripting. WebSocket replay는 미지원 | WebSocket 검사 및 전용 rule | WebSocket capture 및 inspection |
| **스크립팅 및 확장성** | 제한된 API와 실행 timeout을 갖춘 sandboxed JavaScriptCore hook | JavaScript request/response scripting | Rewrite rule과 Control Web Interface. 일반 JavaScript scripting 기능은 문서화되지 않음 | Python add-on 및 command-line automation | rule 기반 automation, 공개 소스 및 proxy library | rule 기반 automation. first-party 일반 scripting 기능은 문서화되지 않음 |
| **업스트림 라우팅** | [HTTP/HTTPS upstream proxy 및 PAC URL routing](docs/features/upstream-proxy.mdx). Community에서는 proxy authentication과 SOCKS5가 비활성화되고 bypass rule은 최대 3개 | bypass rule을 포함한 external HTTP/HTTPS/SOCKS 및 PAC routing | authentication과 bypass rule을 포함한 external HTTP/HTTPS/SOCKS proxy | HTTP/HTTPS upstream mode, reverse 및 SOCKS listener mode | system, HTTP, HTTPS, SOCKS upstream 설정. 요금제 제한이 적용될 수 있음 | system proxy 자동 chaining 및 reverse-proxy capture |
| **AI 및 MCP** | [앱 내 AI Assistant](docs/features/ai-assistant.mdx)와 [내장 로컬 MCP](docs/features/mcp.mdx). read-only tool 10개, token authentication, 기본 redaction | 외부 AI client용 내장 MCP. traffic read와 app/rule control 포함 | 문서화되지 않음 | 문서화되지 않음 | 현재 공식 소스에 bundled local MCP bridge가 있음. 앱 내 assistant는 문서화되지 않음 | 내장 MCP와 Pro-tier Debugging Assistant. 현재 문서상 capture한 traffic details를 chat에 붙여넣어야 함 |

### 인접 차단 도구

이들 제품은 Rockxy와 의미가 겹치지만 보안 테스트로 이어집니다.
동일한 범용이 아닌 브라우저 규칙 또는 API 클라이언트 워크플로
네이티브 디버깅 프록시 포커스.

| **제품** | **인접 도구인 이유** | **소스 및 빌드 모델** | **관련 중복 기능** | **AI 및 MCP** |
|---|---|---|---|---|
| **Burp Suite** | intercepting proxy를 포함한 웹 보안 테스트 suite | 비공개 소스 애플리케이션. EULA는 사용자가 애플리케이션 소스에 대한 권리가 없다고 명시하며 extension은 별도 라이선스를 사용할 수 있음 | proxy interception, match/replace, Repeater, WebSocket, upstream/SOCKS proxy 및 대규모 extension ecosystem | Repeater에서 Burp AI 사용 가능. PortSwigger는 외부 AI client용 공개 MCP Server extension도 유지 |
| **ZAP** | 보안 scanner 및 intercepting proxy | Apache-2.0 공개 소스. 소스에서 빌드 가능 | intercept/edit, manual resend, WebSocket breakpoint와 script, 다중 언어 scripting, add-on 및 automation | 공식 MCP Integration add-on과 선택형 LLM Support add-on |
| **Requestly HTTP Interceptor** | browser extension 및 크로스플랫폼 desktop interceptor/mock tool | desktop interceptor는 AGPL 공개 소스. 별도 API Client는 공개 community repository 고지상 proprietary | system-wide/browser capture, redirect, Map Local/Remote, header/body 수정, JavaScript transform, mock, delay/error simulation | 별도 공식 MCP server가 rule과 group을 관리. 앱 내 traffic-analysis assistant는 문서화되지 않음 |

기능 가용성은 에디션, 계획, 플랫폼 또는 추가 기능에 따라 다를 수 있습니다.
"문서화되지 않음"은 공식 자사에서 기능을 찾을 수 없음을 의미합니다.
2026-08-22에서 검토된 소스; 능력이 없다는 증거는 아닙니다.
위의 제품 및 기능 설명은 공급업체 문서와 비교하여 확인되었습니다.
공급업체가 유지 관리하는 소스 리포지토리 또는 해당 날짜의 공급업체 라이선스 조건 및
변경될 수 있습니다. 제품 이름과 상표는 해당 소유자의 자산입니다.
Rockxy는 이들과 제휴하거나 보증하지 않습니다. 수정은 환영합니다
Rockxy 이슈 트래커를 통해.

로드맵: 더 심층적인 프로토콜 인식 규칙, 더 안전하게 수정된 증거 번들, 더 강력한 재생 및 비교 워크플로, 더 광범위한 개발자 설정 지침, 지속적인 HTTP/2 및 HTTP/3 연구.

## 보안

Rockxy는 네트워크 트래픽을 가로챕니다 — 보안은 기반이지 선택이 아닙니다.

- XPC 헬퍼는 bundle ID만이 아닌 **인증서 체인 비교**로 호출자 검증
- 플러그인은 **샌드박스화된 JavaScriptCore**에서 실행, 5초 타임아웃, 파일시스템/네트워크 접근 불가
- 모든 경계에서 **입력 유효성 검사** — body 크기 제한, URI 제한, regex DoS 방지, 경로 순회 방지
- 로그에서 자격 증명 **자동 마스킹**
- 민감한 파일은 **0o600 권한**으로 저장

취약점 보고는 [SECURITY.md](SECURITY.md)를 참조. 자세한 내용은 [보안 아키텍처](docs/development/security.mdx)를 확인하세요.

## 로드맵

Rockxy의 공개 로드맵은 워크플로 중심이며 고정 날짜를 약속하지 않습니다. 안정성, 네이티브 macOS UX, 디버깅 워크플로, 프로토콜 지원, AI/Web3 시대의 traffic visibility, 문서, 기여자 온보딩에 집중합니다.

- [ROADMAP.md](ROADMAP.md): 공개 엔지니어링 방향의 큰 그림
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): 로드맵 이슈의 실행 현황

## 문서

전체 문서는 [Rockxy Docs](docs/index.mdx)에서 확인 가능:

- [빠른 시작 가이드](docs/quickstart.mdx) — 몇 분 만에 설정
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — 런타임 스니펫, 디바이스 가이드, 검증 프로브, 지원 매트릭스
- [AI Assistant](docs/features/ai-assistant.mdx) — 로컬 분석 또는 Review Data를 확인한 설정 model로 선택 traffic 조사
- [필터 및 검색](docs/core-features/filters-and-search.mdx) — sidebar scope, Focus Sets, Noise Control, toolbar filter, search
- [AI 및 Web3 검사](docs/features/ai-web3-inspection.mdx) — 인식된 model API, JSON-RPC, x402-style traffic 검사
- [MCP Integration](docs/features/mcp.mdx) — Rockxy를 로컬 MCP 클라이언트에 연결
- [아키텍처](docs/development/architecture.mdx) — 프록시 엔진, Actor 모델, 데이터 플로우
- [보안 모델](docs/development/security.mdx) — 신뢰 경계, XPC 검증, 인증서 관리
- [설계 결정](docs/development/design-decisions.mdx) — SwiftNIO, NSTableView, Actor를 선택한 이유
- [소스에서 빌드](docs/development/building.mdx) — 빌드, 테스트, lint, 디버그
- [코드 스타일](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, 코딩 규칙
- [변경 기록](CHANGELOG.md) — 현재 브랜치 작업과 정식 릴리스 기록

## 기여

모든 종류의 기여를 환영합니다 — 코드, 테스트, 문서, 버그 리포트, UX 피드백.

설정 안내, 코드 스타일, PR 체크리스트는 **[CONTRIBUTING.md](CONTRIBUTING.md)**를 참조하세요.

초보자용 이슈는 [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue)로 표시되어 있습니다. PR을 제출하면 [CLA](CLA.md)에 동의한 것으로 간주합니다.

## 스폰서 및 파트너

Rockxy는 독립적으로 유지됩니다. 후원은 지속적인 개발, 릴리스 인프라, 문서화, 보안 작업 자금을 지원합니다.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Rockxy 후원하기" />
  </a>
</p>

Rockxy는 [Open Source Collective](https://docs.oscollective.org/)의 재정 호스팅을 받습니다. 기부금과 프로젝트 지출은 [Rockxy의 공개 Open Collective 페이지](https://opencollective.com/rockxy)에 기록되어 자금의 수령과 사용 내역을 투명하게 확인할 수 있습니다.

| 등급 | 기여 금액 | 지원 내용 |
|------|-----------|-----------|
| **Backer** | 월 $5부터 | 오픈 소스 유지보수, 문서화, 테스트 및 릴리스 |
| **Builder** | 월 $25부터 | 회귀 테스트, 성능 개선 및 일상적인 디버깅 워크플로 |
| **Sponsor** | 월 $100 | 개인정보 보호를 중시하며 개발자에게 무료로 제공되는 도구의 장기 유지보수 |
| **Sustaining Sponsor** | 월 $500 | 릴리스 자동화와 프로토콜 지원을 포함한 집중적인 유지보수 및 제품 개발 |

**파트너십 문의** — 개발자 도구 회사, 보안 기업, 커스텀 통합 또는 화이트라벨 솔루션이 필요한 엔터프라이즈 팀: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## 지원

- [Open Collective](https://opencollective.com/rockxy/donate) — 투명한 프로젝트 예산을 통해 Rockxy에 기여
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — Rockxy 개발 지원
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — 버그 리포트 및 기능 요청
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — 질문 및 커뮤니티 채팅
- **이메일** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **보안 문제** — 책임 있는 공개를 위해 [SECURITY.md](SECURITY.md) 참조

## 라이선스

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## 스타 히스토리

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Swift, SwiftNIO, SwiftUI, AppKit으로 빌드.</sub>
</p>
