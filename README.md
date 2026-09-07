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
  <strong>The AGPL-licensed Community source edition of Rockxy for macOS.</strong>
</p>

<p align="center">
  Intercept, inspect, and modify HTTP/HTTPS/WebSocket/GraphQL traffic with a native Swift app you can inspect, build, and trust.<br>
  Built for API, mobile, MCP-assisted, AI, and blockchain-era debugging workflows as Rockxy evolves.<br>
  A local-first, AGPL-3.0 alternative to <a href="#rockxy-vs-alternatives">Proxyman and Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/source-AGPL--3.0--or--later-green" alt="Source license" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Support Rockxy on Open Collective" /></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/26380?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-26380" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/26380/daily?language=Swift" alt="RockxyApp/Rockxy | Trendshift" width="250" height="55" /></a>
</p>

> [!TIP]
> Translation improvements are welcome in every language. Found wording that is
> awkward, inaccurate, culturally inappropriate, truncated, or too literal? Open
> a [translation issue](https://github.com/RockxyApp/Rockxy/issues/new?template=4-Translation_Improvement.md)
> or send a focused PR. Small repairs can be made without Xcode. See the
> [localization guide](docs/development/localization.mdx) for both repair and new-language workflows.

> [!IMPORTANT]
> This repository contains the public Rockxy Community source edition under
> AGPL-3.0-or-later. Builds made solely from this repository are AGPL builds.
> Official signed Rockxy downloads are produced from a separate downstream
> distribution, run in free Community mode by default, can unlock paid Pro
> capabilities, and—when they include or present Binary EULA v1.0—are licensed
> under that [Rockxy Binary EULA](legal/BINARY-EULA-v1.0.md). Earlier downloads
> remain subject to the terms represented with their release.
> This repository is not represented as the complete source tree used to build
> the official DMG. See [LICENSING.md](LICENSING.md) for the artifact-by-artifact
> licensing boundary.

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

## Current Branch Highlights

- AI Assistant now investigates one or more selected requests with built-in local analysis, optional Ollama or configured provider models, explicit Review Data confirmation, bounded redaction, streaming responses, evidence reveal, and user-initiated handoffs.
- The native sidebar now includes reusable Focus Sets for app/domain/path scopes plus workspace-scoped Noise Control that hides matching domains or paths without stopping capture.
- The main workspace now uses native vertical and horizontal split views for the Context Dock and bottom inspector, preserving full-height dividers, coordinated toolbar/footer separators, and automatic layout resizing.
- Upstream Proxy now includes free/core Automatic Proxy Configuration with PAC URL routing for `DIRECT`, HTTP, and HTTPS routes while preserving existing SOCKS5 and authentication policy boundaries.
- Export workflows now cover OpenAPI YAML/HTML and selected-traffic Gist publishing with redaction-aware payload building.
- Inspector tools now include JSONPath/key/value filtering and quick previews for selected payload text such as JWTs.
- AI and Web3 traffic inspection now adds protocol labels, inspector tabs, and debug summaries for recognized model calls, JSON-RPC traffic, and x402-style payment hints.
- Node.js Developer Setup now mirrors the selected client during validation and has a fuller localhost sample guide.
- Developer Setup Hub now covers runtimes, browsers, clients, devices, frameworks, and environments with target-specific snippets, validation watchers, and honest guide content.
- WebSocket binary-frame inspection now includes bounded, on-demand Protobuf wire-format heuristics without adding decoder work to the capture hot path.
- Public roadmap planning now focuses on deeper protocol-aware rules, replay, comparison, and safer redacted evidence sharing.

## Features

The tools you reach for when browser DevTools are not enough. Core traffic debugging for Mac and iOS work — native on macOS, with public releases and a local-first workflow.

### Traffic Capture

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Inspect HTTP, HTTPS, WebSocket, and GraphQL traffic from any Mac app, CLI, or iOS device. Browser DevTools end at the browser — Rockxy sees the rest of your stack.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Advanced Filter & Search

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Narrow thousands of captured requests in seconds. Combine method, host, status, header, body, and process filters — or run a full-text search across the whole session.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets & Noise Control

Turn recurring investigations into reusable sidebar scopes. Focus Sets combine application, domain, and path includes with domain or path exclusions, persist across launches, and remain available in every workspace. Noise Control keeps telemetry and other low-value domains or paths captured but hidden from the current workspace.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant explaining selected captured traffic beside the native request table and sidebar" width="820" />

Select one or more captured requests and ask what happened, what failed, what changed, or what to verify next. Rockxy starts with evidence-grounded analysis on this Mac; a configured Ollama or provider model runs only after Review Data shows the exact bounded, redacted context. Responses can reveal their source request and prepare native follow-up workflows, but the Assistant never mutates traffic or executes those actions automatically.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Read the AI Assistant guide](docs/features/ai-assistant.mdx).

### MCP Server for External AI Clients

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Let Claude Desktop or Cursor inspect captured traffic through ten read-only tools in Rockxy's local MCP server. Ask "why did this 500?" instead of pasting headers into chat. The implementation is open source, token-authenticated, and keeps sensitive-data redaction enabled by default.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Copy-paste proxy snippets for Python, Node.js, Go, Rust, cURL, Docker, and browsers, then click Run Test to confirm traffic is actually flowing.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Certificate Management for HTTPS Debugging

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

A P-256 ECDSA root CA generated on first launch, sealed in your Keychain. Decrypt HTTPS on the first try; pinned hosts pass through automatically.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL Proxy & HTTPS Decryption

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Pick which hosts get TLS decryption. Decrypted traffic shows real headers and JSON; everything else passes through encrypted. Wildcard rules let you scope by domain in one click.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Skip specific hosts so cert-pinned apps, internal services, or noisy telemetry never enter the capture. Wildcards keep the list short and your request log focused on what you actually care about.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Make any host fail. Drop ad networks, third-party trackers, or a flaky dependency to see how your app degrades when it's gone — without changing a line of code.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Serve a saved file or a directory tree in place of a live response. Swap a JSON payload, replay a snapshot, or pin a flaky third-party API to a local copy while you debug.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Rewrite the destination of a captured request without touching app code or /etc/hosts. Point production traffic at staging, your dev server, or a colleague's machine for a reproducible bug repro.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Breakpoints & Rules

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Pause a request or response, edit method, headers, body, or status, then continue. The fastest way to test "what if the API returns 401?" without touching the backend.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Modify Headers

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Add, remove, or replace headers on any host without redeploying. Test CORS, auth, or cache changes in seconds with built-in presets.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Custom Request & Response Headers

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Promote any request or response header into a first-class traffic-table column. Keep request and response sources separate, save the headers you care about, then scan request IDs, trace IDs, cache state, or custom metadata without opening each inspector.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Network Conditions

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Throttle to 3G, EDGE, LTE, WiFi, or a custom delay. Your laptop is on fiber; your users aren't — see the UX at 400 ms RTT before they do.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — Edit & Replay

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Rebuild any captured HTTP request — change method, URL, headers, query params, or body — and re-send without leaving Rockxy. No Postman, Insomnia, or curl copy-paste loop. Iterate on LLM prompts, fuzz auth boundaries, or reproduce a failing case for OpenAI, Anthropic, and Cohere endpoints in seconds.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Compare

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Stack two captured transactions or pasted payloads side-by-side and spot every field that flipped — status, headers, JSON keys, or body bytes. Catch silent API regressions, non-deterministic LLM outputs, and prompt drift without piping anything into a third-party diff tool.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Custom Previewer Tabs

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Render request and response bodies the way you want. Pin extra tabs to the inspector for JSON, GraphQL, JWT, image, or your own format — reusable across every captured request.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sessions & Export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Save sessions, import/export HAR for cross-tool handoff, copy any request as cURL or JSON. Redact authorization headers, cookies, and bearer tokens before sharing — hand a teammate a working bug repro without leaking secrets.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Projects & Traffic Tabs

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces showing independently filtered views of the same live capture" width="820" />

Group work into local Projects — one Project for checkout, another for authentication, each with tabs for errors, devices, or environments. New requests are assigned to the active Project when they begin; switching back restores that Project's in-memory traffic and durable tab setup.

`3 Local Projects` · `Project-Scoped Traffic` · `Durable Tab Filters` · `Per-Tab Inspector` · `Config Import / Export` · `No Captured Bodies in Catalog`

### JavaScript Scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS hooks on requests and responses for the cases a static rule can't cover — redact PII, sign tokens, rewrite payloads. Errors surface inline instead of corrupting traffic.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Protocol-Aware Inspection

Rockxy ships protocol-aware AI, Web3 RPC, and x402 inspection inside the normal HTTP debugging workflow.

### AI Traffic Inspection

Rockxy detects recognized AI requests inside the normal capture workflow. Inspect selected model calls, streaming state, usage fields when present, warnings, retrieval hints, and tool-call summaries without pasting sensitive payloads into another service.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC Inspection

Rockxy turns blockchain-era network calls into readable debugging evidence. Inspect EVM and Solana-style HTTP JSON-RPC traffic with provider host, request ID, method, batch summary, error, chain, transaction, payload, and debug-intent details without turning Rockxy into a wallet or block explorer.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 Payment Flow Hints

Rockxy highlights payment-required and retry-oriented hints so payment-gated HTTP flows are understandable from the network layer while debugging evidence stays local and redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Future Work

The following sections describe public direction rather than current behavior.

### Protocol-Aware Rules

Rockxy can label and inspect AI and Web3 traffic today. Deeper rule matching by model, tool call, JSON-RPC method, chain, transaction hash, or batch subcall remains future work; current traffic modification tools still match URL, HTTP method, and headers.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Redacted Evidence Bundles `Coming Soon`

Share the facts needed to reproduce a bug without leaking secrets. Package selected traffic with protocol summaries, redaction previews, and source-backed context a teammate can audit.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Team Sharing & Collaboration `Coming Soon`

Send a captured session to a teammate with one click. Annotate failing requests inline, see who's looking at what in real time, and pair-debug HTTPS traffic without screen-sharing. Targeted for a future release.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Native macOS app shell — no Electron. SwiftUI + AppKit + SwiftNIO, with WebKit used only for HTML body preview.

## Quick Start

These commands build the public AGPL Community source edition. That build is
not the same artifact as the official signed DMG published on GitHub Releases.

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Build and run in Xcode. The Welcome window guides you through root CA setup, helper installation, and proxy activation.

**Requirements:** macOS 14.0+, Xcode 16+, Swift 5.9

If you want to connect Rockxy to a local MCP client after installation, see the [MCP Integration guide](docs/features/mcp.mdx).

## Rockxy vs. Alternatives

The main matrix covers general-purpose web-debugging proxies. Security-testing
suites and browser/API-oriented interceptors with substantial workflow overlap
are listed separately so unlike products are not presented as interchangeable.
Packet analyzers and API-only clients are outside this comparison.

### Direct web-debugging proxies

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Product shape** | Native macOS debugging proxy | Native macOS app; Electron-based Windows/Linux editions | Cross-platform desktop debugging proxy | Cross-platform CLI/TUI and web UI proxy toolkit | Cross-platform Electron desktop proxy and HTTP client | Cross-platform desktop debugging proxy |
| **Source and build model** | Public Community source under AGPL-3.0-or-later; buildable with Xcode. The official DMG also contains non-public downstream components | Closed source; no public application source identified in the official materials reviewed | Closed source; no public application source identified in the official materials reviewed | Public MIT-licensed source; buildable from source | Public AGPL desktop source; buildable from source; published binaries have additional licensing options | Closed source; distributed as object code under the Fiddler Everywhere EULA |
| **Capture and setup** | Local system proxy with guided setup for Mac apps, runtimes, iOS devices, and Simulator | Automatic setup for Mac apps, runtimes, and mobile devices | Local proxy with macOS, iOS, and cross-platform setup guides | Regular, local-process, WireGuard, reverse, transparent, and other capture modes | Targeted and manual proxy interception for browsers, runtimes, containers, and mobile devices | System, network, browser, terminal, explicit, and remote-device capture modes |
| **Modify and mock** | Breakpoints, Map Local/Remote, header rules, blocking, and latency rules | Breakpoints, Map Local/Remote, block lists, network conditions, and JavaScript rules | Breakpoints, Rewrite, Map Local/Remote, blocking, and throttling | Map Local/Remote, body/header modification, blocking, and server replay | Breakpoints plus rule-based rewrite, redirect, mock, and error injection; some automation is plan-limited | Rules, breakpoints, redirects, response modification, and mocking |
| **Replay and compare** | Compose/replay plus local side-by-side request, header, and body comparison | Compose, Repeat, and Diff | Repeat and edit requests | Client-side and server-side replay | Built-in HTTP client for composing and sending requests | API Composer, traffic replay, and traffic comparison documented as beta |
| **WebSocket workflows** | Text/binary frame inspection with bounded Protobuf heuristics | WS/WSS inspection; scripts can modify handshake URL/headers, not messages | WebSocket support is documented in the official version history | WebSocket interception and scripting; WebSocket replay is not supported | WebSocket inspection plus WebSocket-specific rules | WebSocket capture and inspection |
| **Scripting and extensibility** | Sandboxed JavaScriptCore hooks with a bounded API and execution timeout | JavaScript request/response scripting | Rewrite rules and a control Web Interface; no general JavaScript scripting feature documented | Python addons and command-line automation | Rule-based automation plus public source and proxy libraries | Rule-based automation; no first-party general scripting feature documented |
| **Upstream routing** | [HTTP/HTTPS upstream proxy and PAC URL routing](docs/features/upstream-proxy.mdx); Community policy disables proxy authentication and SOCKS5 and caps bypass rules at three | External HTTP/HTTPS/SOCKS and PAC routing with bypass rules | External HTTP/HTTPS/SOCKS proxies with authentication and bypass rules | HTTP/HTTPS upstream mode plus reverse and SOCKS listener modes | System, HTTP, HTTPS, and SOCKS upstream settings; plan limits may apply | Automatic chaining to system proxies plus reverse-proxy capture |
| **AI and MCP** | [In-app AI Assistant](docs/features/ai-assistant.mdx) and [built-in local MCP](docs/features/mcp.mdx) with 10 read-only tools, token authentication, and redaction on by default | Built-in MCP for external AI clients, including traffic reads and app/rule controls | Not documented | Not documented | A bundled local MCP bridge is present in the current official source; no in-app assistant documented | Built-in MCP plus a Pro-tier Debugging Assistant whose current documentation requires captured traffic details to be pasted into chat |

### Adjacent interception tools

These products overlap meaningfully with Rockxy but lead with security testing,
browser rules, or API-client workflows rather than the same general-purpose
native debugging-proxy focus.

| **Product** | **Why it is adjacent** | **Source and build model** | **Relevant overlap** | **AI and MCP** |
|---|---|---|---|---|
| **Burp Suite** | Web-security testing suite with an intercepting proxy | Closed-source application; its EULA states that users have no right to the application source. Extensions can use separate licenses | Proxy interception and match/replace, Repeater, WebSockets, upstream/SOCKS proxying, and a large extension ecosystem | Burp AI is available in Repeater; PortSwigger also maintains a public MCP Server extension for external AI clients |
| **ZAP** | Security scanner and intercepting proxy | Public Apache-2.0 source; buildable from source | Intercept/edit, manual resend, WebSocket breakpoints and scripts, multi-language scripting, add-ons, and automation | Official MCP Integration and optional LLM Support add-ons |
| **Requestly HTTP Interceptor** | Browser-extension and cross-platform desktop interceptor/mock tool | Public AGPL desktop-interceptor source; the separate Requestly API Client is proprietary according to its public community-repository notice | System-wide/browser capture, redirect, Map Local/Remote, header/body modification, JavaScript transforms, mocks, and delay/error simulation | A separate official MCP server manages rules and groups; no in-app traffic-analysis assistant documented |

Feature availability can vary by edition, plan, platform, or add-on.
"Not documented" means that a capability was not found in the official first-party
sources reviewed on 2026-08-22; it is not proof that the capability is absent.
Product and feature statements above were checked against vendor documentation,
vendor-maintained source repositories, or vendor license terms on that date and
may change. Product names and trademarks belong to their respective owners;
Rockxy is not affiliated with or endorsed by them. Corrections are welcome
through the Rockxy issue tracker.

On the roadmap: deeper protocol-aware rules, safer redacted evidence bundles, stronger replay and comparison workflows, broader Developer Setup guidance, and continued HTTP/2 and HTTP/3 research.

## Security

Rockxy intercepts network traffic — security is foundational, not optional.

- XPC helper validates callers via **certificate-chain comparison**, not just bundle ID
- Plugins run in **sandboxed JavaScriptCore** with 5-second timeout, no filesystem/network access
- **Input validation** on all boundaries — body size caps, URI limits, regex DoS protection, path traversal prevention
- Credentials **automatically redacted** in captured logs
- Sensitive files stored with **0o600 permissions**

Report vulnerabilities via [SECURITY.md](SECURITY.md). See the [full security architecture](docs/development/security.mdx) for details.

## Roadmap

Rockxy's public roadmap is workflow-oriented and date-free. It focuses on reliability, native macOS UX, debugging workflows, protocol support, AI/Web3-era traffic visibility, documentation, and contributor onboarding.

- [ROADMAP.md](ROADMAP.md): high-level public engineering direction
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): operational visibility for roadmap-tracked issues

## Documentation

Full documentation available at the [Rockxy Docs](docs/index.mdx):

- [Quickstart Guide](docs/quickstart.mdx) — get up and running in minutes
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — runtime snippets, device guides, validation probes, and support matrix
- [AI Assistant](docs/features/ai-assistant.mdx) — investigate selected traffic with local analysis or an explicitly reviewed configured model
- [Filters and Search](docs/core-features/filters-and-search.mdx) — use sidebar scopes, Focus Sets, Noise Control, toolbar filters, and search
- [AI and Web3 Inspection](docs/features/ai-web3-inspection.mdx) — inspect recognized model API, JSON-RPC, and x402-style traffic
- [MCP Integration](docs/features/mcp.mdx) — connect Rockxy to local MCP clients
- [Architecture](docs/development/architecture.mdx) — proxy engine, actor model, data flow
- [Security Model](docs/development/security.mdx) — trust boundaries, XPC validation, certificate management
- [Design Decisions](docs/development/design-decisions.mdx) — why SwiftNIO, NSTableView, actors
- [Building from Source](docs/development/building.mdx) — build, test, lint, and debug
- [Code Style](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, and conventions
- [Changelog](CHANGELOG.md) — unreleased work and tagged releases

## Contributing

Contributions welcome — code, tests, docs, bug reports, and UX feedback.

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for setup instructions, code style, and the full PR checklist.

Good first issues are labeled [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). By opening a PR, you agree to the [CLA](CLA.md).

## Sponsors & Partners

Rockxy is independently maintained. Sponsorships help fund continued development, release infrastructure, documentation, and security work.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Support Rockxy on Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy is fiscally hosted by [Open Source Collective](https://docs.oscollective.org/). Contributions and project expenses are recorded on Rockxy's [public Open Collective page](https://opencollective.com/rockxy), giving supporters a transparent view of how funds are received and used.

| Tier | Contribution | What it supports |
|------|--------------|------------------|
| **Backer** | From $5/month | Open-source maintenance, documentation, testing, and releases |
| **Builder** | From $25/month | Regression testing, performance improvements, and everyday debugging workflows |
| **Sponsor** | $100/month | Long-term maintenance of a privacy-focused tool that remains freely available to developers |
| **Sustaining Sponsor** | $500/month | Focused maintenance and product development, including release automation and protocol support |

**Partnership inquiries** — developer tool companies, security firms, and enterprise teams looking for custom integrations or white-label solutions: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Support

- [Open Collective](https://opencollective.com/rockxy/donate) — contribute to Rockxy through its transparent project budget
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — support Rockxy's development
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — bug reports and feature requests
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — questions and community chat
- **Email** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Security issues** — see [SECURITY.md](SECURITY.md) for responsible disclosure

## License

The source in this public repository is available under the
[GNU Affero General Public License v3.0 or later](LICENSE), except identified
third-party material. Official signed DMG downloads that include or present
Binary EULA v1.0 are governed by that
[Rockxy Binary EULA](legal/BINARY-EULA-v1.0.md). See
[LICENSING.md](LICENSING.md) for the complete artifact boundary and
[COPYRIGHT.md](COPYRIGHT.md) for ownership and attribution information.

## Star History

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Built with Swift, SwiftNIO, SwiftUI, and AppKit.</sub>
</p>
