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
  <strong>The open-source, auditable HTTP debugging proxy for macOS.</strong>
</p>

<p align="center">
  Intercept, inspect, and modify HTTP/HTTPS/WebSocket/GraphQL traffic with a native Swift app you can inspect, build, and trust.<br>
  A local-first, AGPL-3.0 alternative to <a href="#rockxy-vs-alternatives">Proxyman and Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Light.png" alt="Rockxy running on macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.24.0** — 2026-06-02

### Fixed

- Fixed capture startup so Rockxy begins capturing reliably after launch.
- Fixed pinned and saved requests opened in a new tab so Rockxy shows the exact selected request, even when multiple requests share the same URL.
- Kept full request URLs out of the visible search field when opening pinned or saved requests in a new tab.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Current Branch Highlights

- Upstream Proxy now includes free/core Automatic Proxy Configuration with PAC URL routing for `DIRECT`, HTTP, and HTTPS routes while preserving existing SOCKS5 and authentication policy boundaries.
- Export workflows now cover OpenAPI YAML/HTML and selected-traffic Gist publishing with redaction-aware payload building.
- Inspector tools now include JSONPath/key/value filtering and quick previews for selected payload text such as JWTs.
- Node.js Developer Setup now mirrors the selected client during validation and has a fuller localhost sample guide.
- Developer Setup Hub now covers runtimes, browsers, clients, devices, frameworks, and environments with target-specific snippets, validation watchers, and honest guide content.
- WebSocket Protobuf work continues as part of Rockxy's richer protocol inspection direction.

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

### MCP Server for AI Assistants

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Let Claude Desktop or Cursor read your captured traffic through a local MCP server. Ask "why did this 500?" instead of pasting headers into chat. Free MCP server — no paid AI add-on or upsell, no usage cap.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Override headers per host with full control over both phases. Inject auth tokens on outgoing requests, strip Set-Cookie on responses, or pin a custom User-Agent — saved as named rules you can toggle anytime.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Network Conditions

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Throttle to 3G, EDGE, LTE, WiFi, or a custom delay. Your laptop is on fiber; your users aren't — see the UX at 400 ms RTT before they do.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — Edit & Replay

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Rebuild any captured HTTP request — change method, URL, headers, query params, or body — and re-send without leaving Rockxy. No Postman, Insomnia, or curl copy-paste loop. Iterate on LLM prompts, fuzz auth boundaries, or reproduce a failing case for OpenAI, Anthropic, and Cohere endpoints in seconds.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Compare

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Stack two captured responses side-by-side and spot every field that flipped — status, headers, JSON keys, body bytes. Catch silent API regressions, non-deterministic LLM outputs, and prompt drift without piping anything into a third-party diff tool. Side-by-side diff highlights what changed; deep JSON compare ignores key ordering.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Custom Previewer Tabs

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Render request and response bodies the way you want. Pin extra tabs to the inspector for JSON, GraphQL, JWT, image, or your own format — reusable across every captured request.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sessions & Export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Save sessions, import/export HAR for cross-tool handoff, copy any request as cURL or JSON. Redact authorization headers, cookies, and bearer tokens before sharing — hand a teammate a working bug repro without leaking secrets.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Multi-Tab Workspaces

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

Run independent capture sessions side-by-side — one tab for staging, one for prod, one for the iOS device build. Each tab has its own filters, selection, and inspector state, so context switching costs nothing.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript Scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS hooks on requests and responses for the cases a static rule can't cover — redact PII, sign tokens, rewrite payloads. Errors surface inline instead of corrupting traffic.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

### Team Sharing & Collaboration `Coming Soon`

Send a captured session to a teammate with one click. Annotate failing requests inline, see who's looking at what in real time, and pair-debug HTTPS traffic without screen-sharing. Targeted for a future release.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% native macOS. No Electron. No web views. SwiftUI + AppKit + SwiftNIO.
## Quick Start

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Build and run in Xcode. The Welcome window guides you through root CA setup, helper installation, and proxy activation.

**Requirements:** macOS 14.0+, Xcode 16+, Swift 5.9

If you want to connect Rockxy to a local MCP client after installation, see the [MCP Integration guide](docs/features/mcp.mdx).

## Rockxy vs. Alternatives

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Project model** | AGPL-3.0 open-source project | Proprietary commercial app | Proprietary commercial app |
| **Source code** | Public, auditable, forkable | Closed source | Closed source |
| **Build from source** | Free with Xcode from this repo | Not available from public source | Not available from public source |
| **Native macOS foundation** | Swift + SwiftNIO + SwiftUI/AppKit | Native macOS commercial app | Cross-platform commercial app |
| **Local-first capture** | Local proxy, certificates, helper, and capture data stay on your Mac | Desktop proxy app | Desktop proxy app |
| **Developer setup workflow** | Built-in Developer Setup Hub for runtimes, clients, devices, frameworks, and environments | Product-specific setup guidance | Product-specific setup guidance |
| **External proxy + PAC routing** | HTTP/HTTPS upstream proxy, PAC auto-configuration, and bypass rules | Mature commercial proxy tooling | Mature commercial proxy tooling |
| **MCP/local automation bridge** | Built in, token-authenticated, redaction by default | Not claimed in public docs reviewed | Not claimed in public docs reviewed |
| **Open contribution path** | Public issues, discussions, roadmap, and PRs | Vendor-controlled product | Vendor-controlled product |

On the roadmap: deeper replay/diff/rules/scripting workflows, improved WebSocket and GraphQL inspection, and exploration of gRPC/Protobuf plus HTTP/2 and HTTP/3 support.

## Security

Rockxy intercepts network traffic — security is foundational, not optional.

- XPC helper validates callers via **certificate-chain comparison**, not just bundle ID
- Plugins run in **sandboxed JavaScriptCore** with 5-second timeout, no filesystem/network access
- **Input validation** on all boundaries — body size caps, URI limits, regex DoS protection, path traversal prevention
- Credentials **automatically redacted** in captured logs
- Sensitive files stored with **0o600 permissions**

Report vulnerabilities via [SECURITY.md](SECURITY.md). See the [full security architecture](docs/development/security.mdx) for details.

## Roadmap

Rockxy's public roadmap is workflow-oriented and date-free. It focuses on reliability, native macOS UX, debugging workflows, protocol support, documentation, and contributor onboarding.

- [ROADMAP.md](ROADMAP.md): high-level public engineering direction
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): operational visibility for roadmap-tracked issues

## Documentation

Full documentation available at the [Rockxy Docs](docs/index.mdx):

- [Quickstart Guide](docs/quickstart.mdx) — get up and running in minutes
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — runtime snippets, device guides, validation probes, and support matrix
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

Rockxy is built and maintained by independent developers. Sponsorships fund continued development, security audits, and new features.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

| Tier | Benefits |
|------|----------|
| **Gold Sponsor** | Logo on README + docs site, priority feature requests, direct support channel |
| **Silver Sponsor** | Logo on README, named acknowledgment in release notes |
| **Bronze Sponsor** | Named acknowledgment in README and docs |
| **Partner** | Co-development, integration support, early access to upcoming features |

**Partnership inquiries** — developer tool companies, security firms, and enterprise teams looking for custom integrations or white-label solutions: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Support

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — support Rockxy's development
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — bug reports and feature requests
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — questions and community chat
- **Email** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Security issues** — see [SECURITY.md](SECURITY.md) for responsible disclosure

## License

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## Star History

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Built with Swift, SwiftNIO, SwiftUI, and AppKit.</sub>
</p>
