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
  <strong>The open-source HTTP debugging proxy for macOS.</strong>
</p>

<p align="center">
  Intercept, inspect, and modify HTTP/HTTPS/WebSocket/GraphQL traffic — built natively in Swift.<br>
  A free, auditable alternative to <a href="#rockxy-vs-alternatives">Proxyman and Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/LocNguyenHuu/Rockxy/releases"><img src="https://img.shields.io/github/v/release/LocNguyenHuu/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Dark.png" alt="Rockxy running on macOS" width="800" />
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

## Current Branch Highlights

- Developer Setup Hub now covers runtimes, browsers, clients, devices, frameworks, and environments with target-specific snippets, validation watchers, and honest guide content.
- HTTPS response prompts, sidebar actions, and the request table now stay in sync when SSL proxying is enabled or disabled by domain or app.
- The inspector and main request table were polished with scrolling tabs, top-aligned query content, clearer status/code separation, request/response byte columns, duration fixes, and live SSL state icons.

## Features

**Traffic Capture** — SwiftNIO proxy with CONNECT tunnel, auto-generated per-host TLS certificates, WebSocket frame capture, and automatic GraphQL operation detection.

**Inspect Everything** — JSON tree viewer, hex inspector, timing waterfall (DNS/TCP/TLS/TTFB/Transfer), headers, cookies, query params, auth — all in a tabbed inspector.

**Mock & Modify** — Map Local (serve from files), Map Remote (redirect to another server), Breakpoints (pause and edit mid-flight), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**Log Correlation** — Capture macOS logs (OSLog) and correlate them with network requests by timestamp. See which app made each request.

**Extend with Plugins** — JavaScript scripting in a sandboxed JavaScriptCore runtime. Inspect, modify, and automate traffic with custom hooks.

**Built for Scale** — NSTableView virtual scrolling handles 100k+ requests. Ring buffer eviction, disk body offloading, batched UI updates. Zero lag.

**Developer Setup Hub** — Guided setup per runtime, browser, device, framework, and environment with copyable snippets, validation probes, and troubleshooting notes.

**AI-Ready (MCP Server)** — Bundled Model Context Protocol server lets Claude CLI, Claude Desktop, and other MCP clients query live traffic, rules, and proxy status directly from chat. Local-only, token-authenticated, sensitive data redacted by default.

> 100% native macOS. No Electron. No web views. SwiftUI + AppKit + SwiftNIO.

## Quick Start

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Build and run in Xcode. The Welcome window guides you through root CA setup, helper installation, and proxy activation.

**Requirements:** macOS 14.0+, Xcode 16+, Swift 5.9

If you want to connect Rockxy to Claude after installation, see the [MCP Integration guide](docs/features/mcp.mdx).

## Rockxy vs. Alternatives

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **License** | AGPL-3.0 (open-source) | Proprietary (freemium) | Proprietary ($50) |
| **Source code** | Fully auditable | Closed | Closed |
| **Technology** | Swift + SwiftNIO | Swift + AppKit | Java |
| **HTTPS interception** | Yes | Yes | Yes |
| **WebSocket** | Yes | Yes | Yes |
| **GraphQL detection** | Yes | Yes | No |
| **Map Local / Remote** | Yes | Yes | Yes |
| **Breakpoints** | Yes | Yes | Yes |
| **JavaScript scripting** | Yes | Yes | No |
| **OSLog correlation** | Yes | No | No |
| **Process identification** | Yes | Yes | No |
| **Request diff** | Yes | Yes | No |
| **HAR import/export** | Yes | Yes | No |
| **100k+ row performance** | Yes | Yes | Slow |
| **No-password proxy setup** | Yes (helper daemon) | Yes | No |
| **Community contributions** | Open PRs | No | No |

## Security

Rockxy intercepts network traffic — security is foundational, not optional.

- XPC helper validates callers via **certificate-chain comparison**, not just bundle ID
- Plugins run in **sandboxed JavaScriptCore** with 5-second timeout, no filesystem/network access
- **Input validation** on all boundaries — body size caps, URI limits, regex DoS protection, path traversal prevention
- Credentials **automatically redacted** in captured logs
- Sensitive files stored with **0o600 permissions**

Report vulnerabilities via [SECURITY.md](SECURITY.md). See the [full security architecture](docs/development/security.mdx) for details.

## Roadmap

- [x] HTTP/HTTPS/WebSocket/GraphQL interception
- [x] Map Local, Map Remote, Breakpoints, Block, Throttle
- [x] JavaScript plugin system with sandboxed execution
- [x] HAR import/export, native session files, request diff
- [x] OSLog correlation and credential redaction
- [x] Model Context Protocol (MCP) server for AI assistants (Claude CLI, Claude Desktop)
- [ ] HTTP/2 and HTTP/3 support
- [ ] Remote device proxy (iOS over USB/Wi-Fi)
- [ ] Headless mode for CI/CD pipeline integration
- [ ] gRPC / Protocol Buffers inspection
- [ ] Error grouping and analytics dashboard

## Documentation

Full documentation available at the [Rockxy Docs](docs/index.mdx):

- [Quickstart Guide](docs/quickstart.mdx) — get up and running in minutes
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — runtime snippets, device guides, validation probes, and support matrix
- [MCP Integration](docs/features/mcp.mdx) — connect Rockxy to Claude CLI or Claude Desktop
- [Architecture](docs/development/architecture.mdx) — proxy engine, actor model, data flow
- [Security Model](docs/development/security.mdx) — trust boundaries, XPC validation, certificate management
- [Design Decisions](docs/development/design-decisions.mdx) — why SwiftNIO, NSTableView, actors
- [Building from Source](docs/development/building.mdx) — build, test, lint, and debug
- [Code Style](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, and conventions
- [Changelog](CHANGELOG.md) — unreleased work and tagged releases

## Contributing

Contributions welcome — code, tests, docs, bug reports, and UX feedback.

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for setup instructions, code style, and the full PR checklist.

Good first issues are labeled [`good first issue`](https://github.com/LocNguyenHuu/Rockxy/labels/good%20first%20issue). By opening a PR, you agree to the [CLA](CLA.md).

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
- [GitHub Issues](https://github.com/LocNguyenHuu/Rockxy/issues) — bug reports and feature requests
- [GitHub Discussions](https://github.com/LocNguyenHuu/Rockxy/discussions) — questions and community chat
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
  <sub>Built with Swift, SwiftNIO, SwiftUI, and AppKit.</sub>
</p>
