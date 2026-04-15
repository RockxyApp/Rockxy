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
## Latest Release

**v0.7.1** — 2026-04-15

### Fixed

- Align live-history cap with actor accounting, guard clearSession reentry, clear ruleLoadTask on completion
- Finalize upstream normalization cleanup
- Cross-suite RuleEngine serialization via RuleTestLock and clearSession regression test
- Replace fire-and-forget engine restore with awaited cleanup in rule tests
- Eliminate MainActor starvation in rule tests and close clearSession generation gap
- Synchronous sessionGeneration in clearSession, atomic rule store writes, and detached syncAll disk I/O
- ClearSession generation sync, deterministic rollback polls, and test isolation
- ClearSession race, rule test isolation, and docs product-name normalization
- Testable ConnectionValidator seam with accept-path and audit-token coverage
- Generation-safe accepted-count reporting and audit-token SecCode extraction seam
- Real caller-validation entrypoint, generation-safe session clear, and bridge defaults isolation
- Real caller-validation tests, correct history accounting, and full plugin environment normalization
- Session clear race, plugin environment normalization, and test serialization
- Hermetic plugin test isolation, real runtime transition test, and error-status assertion
- Refresh VM on failed enable, isolate plugin fixtures, guard small-buffer eviction, and tighten signing tests
- Use Task.sleep instead of Task.yield for VM rollback test stability
- Single-flight rule loading via ensureRulesLoaded()
- Harden plugin/rule race conditions, quota logic, and error surfacing
- Short-circuit re-enable for already-enabled plugins
- Snapshot plugin IDs across await and fix exclusive netcond quota
- Rule loading race and exclusive network-condition quota bypass
- Make quota paths truly atomic and isolate gate policy from tests
- Address final review findings for gates, bulk replace, and selection
- Make script enable atomic and propagate missing-plugin errors
- Address review findings for policy gate correctness
- Make RuleQuotaTests immune to cross-suite singleton state

### Changed

- Correct batched-update interval to 100ms and qualify large-body storage path per build
- Validate loadInitialRules reuses in-flight ruleLoadTask and clears it on completion
- Harden plugin env cleanup, dedupe allowed-caller constants, remove hardcoded audit_token_t ObjC encoding, guarantee rule lock release
- Delegate RockxyIdentity bundle init to infoDictionary init
- Tighten .gitignore entries, fix README badges, correct architecture and security diagrams
- Exercise real audit-token revalidation branch in isValidCaller
- Full isValidCaller accept path and NSValue audit-token branch via TestXPCConnection
- Stabilize ConnectionValidator tests and remove infeasible XPC harness
- Direct ConnectionValidator coverage via Shared/ relocation
- Prove enable transition through real default-init production singleton
- Prove default-init VMs load consistent state through real production path
- Restore default-init wiring coverage via pluginManagerIdentity seam
- Isolate default-wiring plugin test from real app-support state
- Complete helper signing diagnostics, toggle rollback, and engine-state assertions
- Strengthen actor eviction, default VM wiring, and concurrent enable postconditions
- Cover default plugin runtime wiring
- Cover coordinator rule wiring, VM quota rollback, and script default paths
- Extract shared temp plugin helpers to TestFixtures
- Remove dead SessionStore coupling from eviction and strengthen history retention tests
- Add helper caller validation matrix
- Annotate identity fallbacks and bind tests to live config
- Add identity and helper trust matrix coverage
- Unify ScriptPluginManager ownership and add script quota
- Cap live history buffer at policy-defined limit
- Add RulePolicyGate and route rule mutations through it
- Add domain favorites capacity at coordinator boundary
- Inject workspace capacity via init
- Remove edition leakage and introduce AppPolicy
- Split family config from product identity

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Features

**Traffic Capture** — SwiftNIO proxy with CONNECT tunnel, auto-generated per-host TLS certificates, WebSocket frame capture, and automatic GraphQL operation detection.

**Inspect Everything** — JSON tree viewer, hex inspector, timing waterfall (DNS/TCP/TLS/TTFB/Transfer), headers, cookies, query params, auth — all in a tabbed inspector.

**Mock & Modify** — Map Local (serve from files), Map Remote (redirect to another server), Breakpoints (pause and edit mid-flight), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**Log Correlation** — Capture macOS logs (OSLog) and correlate them with network requests by timestamp. See which app made each request.

**Extend with Plugins** — JavaScript scripting in a sandboxed JavaScriptCore runtime. Inspect, modify, and automate traffic with custom hooks.

**Built for Scale** — NSTableView virtual scrolling handles 100k+ requests. Ring buffer eviction, disk body offloading, batched UI updates. Zero lag.

> 100% native macOS. No Electron. No web views. SwiftUI + AppKit + SwiftNIO.

## Quick Start

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Build and run in Xcode. The Welcome window guides you through root CA setup, helper installation, and proxy activation.

**Requirements:** macOS 14.0+, Xcode 16+, Swift 5.9

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
- [ ] HTTP/2 and HTTP/3 support
- [ ] Remote device proxy (iOS over USB/Wi-Fi)
- [ ] Headless mode for CI/CD pipeline integration
- [ ] gRPC / Protocol Buffers inspection
- [ ] Error grouping and analytics dashboard

## Documentation

Full documentation available at the [Rockxy Docs](docs/index.mdx):

- [Quickstart Guide](docs/quickstart.mdx) — get up and running in minutes
- [Architecture](docs/development/architecture.mdx) — proxy engine, actor model, data flow
- [Security Model](docs/development/security.mdx) — trust boundaries, XPC validation, certificate management
- [Design Decisions](docs/development/design-decisions.mdx) — why SwiftNIO, NSTableView, actors
- [Building from Source](docs/development/building.mdx) — build, test, lint, and debug
- [Code Style](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, and conventions

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

---

<p align="center">
  <sub>Built with Swift, SwiftNIO, SwiftUI, and AppKit.</sub>
</p>
