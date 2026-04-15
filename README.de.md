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
  <strong>Quelloffener HTTP-Debugging-Proxy f&uuml;r macOS.</strong>
</p>

<p align="center">
  HTTP/HTTPS/WebSocket/GraphQL-Traffic abfangen, inspizieren und modifizieren &mdash; nativ in Swift entwickelt.<br>
  Eine kostenlose, &uuml;berpr&uuml;fbare Alternative zu <a href="#rockxy-vs-alternativen">Proxyman und Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/LocNguyenHuu/Rockxy/releases"><img src="https://img.shields.io/github/v/release/LocNguyenHuu/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Plattform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Lizenz" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs willkommen" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsern" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Dark.png" alt="Rockxy auf macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Neueste Version

**v0.7.1** — 2026-04-15

### Behoben

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

### Geändert

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

Die vollständige Versionshistorie finden Sie in [CHANGELOG.md](CHANGELOG.md).
<!-- END GENERATED: latest-release -->

## Funktionen

**Traffic-Erfassung** &mdash; SwiftNIO-basierter Proxy mit CONNECT-Tunnel, automatischer TLS-Zertifikatsgenerierung pro Host, WebSocket-Frame-Erfassung und automatischer GraphQL-Operationserkennung.

**Alles inspizieren** &mdash; JSON-Baumansicht, Hex-Inspektor, Timing-Wasserfall (DNS/TCP/TLS/TTFB/Transfer), Header, Cookies, Query-Parameter, Authentifizierung &mdash; alles in einem Tab-basierten Inspektor.

**Mock und Modifikation** &mdash; Map Local (Antworten aus lokalen Dateien), Map Remote (Umleitung zu anderem Server), Breakpoints (Pause und Bearbeitung w&auml;hrend der &Uuml;bertragung), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**Log-Korrelation** &mdash; macOS-Systemlogs (OSLog) erfassen und per Zeitstempel mit Netzwerkanfragen korrelieren. Sehen, welche App jede Anfrage gesendet hat.

**Mit Plugins erweitern** &mdash; JavaScript-Scripting in einer sandboxed JavaScriptCore-Laufzeit. Traffic mit benutzerdefinierten Hooks inspizieren, modifizieren und automatisieren.

**F&uuml;r Skalierung gebaut** &mdash; NSTableView mit virtuellem Scrollen f&uuml;r 100k+ Anfragen. Ringpuffer-Eviction, Disk-Body-Offloading, gebatchte UI-Updates. Keine Verz&ouml;gerung.

> 100 % natives macOS. Kein Electron. Keine Web-Views. SwiftUI + AppKit + SwiftNIO.

## Schnellstart

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

In Xcode bauen und ausf&uuml;hren. Das Willkommensfenster f&uuml;hrt durch die Root-CA-Einrichtung, Helper-Installation und Proxy-Aktivierung.

**Voraussetzungen:** macOS 14.0+, Xcode 16+, Swift 5.9

## Rockxy vs. Alternativen

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Lizenz** | AGPL-3.0 (Open Source) | Propriet&auml;r (Freemium) | Propriet&auml;r (50 $) |
| **Quellcode** | Vollst&auml;ndig &uuml;berpr&uuml;fbar | Geschlossen | Geschlossen |
| **Technologie** | Swift + SwiftNIO | Swift + AppKit | Java |
| **HTTPS-Interception** | Ja | Ja | Ja |
| **WebSocket** | Ja | Ja | Ja |
| **GraphQL-Erkennung** | Ja | Ja | Nein |
| **Map Local / Remote** | Ja | Ja | Ja |
| **Breakpoints** | Ja | Ja | Ja |
| **JavaScript-Scripting** | Ja | Ja | Nein |
| **OSLog-Korrelation** | Ja | Nein | Nein |
| **Prozessidentifikation** | Ja | Ja | Nein |
| **Request-Diff** | Ja | Ja | Nein |
| **HAR-Import/Export** | Ja | Ja | Nein |
| **100k+ Zeilen Performance** | Ja | Ja | Langsam |
| **Passwortfreie Proxy-Einrichtung** | Ja (Helper-Daemon) | Ja | Nein |
| **Community-Beitr&auml;ge** | Offene PRs | Nein | Nein |

## Sicherheit

Rockxy fängt Netzwerk-Traffic ab &mdash; Sicherheit ist fundamental, nicht optional.

- Der XPC-Helper validiert Aufrufer durch **Zertifikatsketten-Vergleich**, nicht nur durch Bundle-ID
- Plugins laufen in **sandboxed JavaScriptCore** mit 5-Sekunden-Timeout, ohne Dateisystem-/Netzwerkzugang
- **Eingabevalidierung** an allen Grenzen &mdash; Body-Gr&ouml;&szlig;enbegrenzungen, URI-Limits, Regex-DoS-Schutz, Path-Traversal-Pr&auml;vention
- Anmeldeinformationen werden in Logs **automatisch maskiert**
- Sensible Dateien werden mit **0o600-Berechtigungen** gespeichert

Schwachstellen melden &uuml;ber [SECURITY.md](SECURITY.md). Siehe die [vollst&auml;ndige Sicherheitsarchitektur](docs/development/security.mdx) f&uuml;r Details.

## Roadmap

- [x] HTTP/HTTPS/WebSocket/GraphQL-Interception
- [x] Map Local, Map Remote, Breakpoints, Block, Throttle
- [x] JavaScript-Plugin-System (Sandbox-Ausf&uuml;hrung)
- [x] HAR-Import/Export, native Sitzungsdateien, Request-Diff
- [x] OSLog-Korrelation und Maskierung von Anmeldeinformationen
- [ ] HTTP/2- und HTTP/3-Unterst&uuml;tzung
- [ ] Remote-Ger&auml;te-Proxy (iOS &uuml;ber USB/Wi-Fi)
- [ ] Headless-Modus f&uuml;r CI/CD-Pipelines
- [ ] gRPC / Protocol Buffers-Inspektion
- [ ] Fehlergruppierung und Analyse-Dashboard

## Dokumentation

Vollst&auml;ndige Dokumentation verf&uuml;gbar unter [Rockxy Docs](docs/index.mdx):

- [Schnellstart-Anleitung](docs/quickstart.mdx) &mdash; in wenigen Minuten einsatzbereit
- [Architektur](docs/development/architecture.mdx) &mdash; Proxy-Engine, Actor-Modell, Datenfluss
- [Sicherheitsmodell](docs/development/security.mdx) &mdash; Vertrauensgrenzen, XPC-Validierung, Zertifikatsverwaltung
- [Design-Entscheidungen](docs/development/design-decisions.mdx) &mdash; warum SwiftNIO, NSTableView, Actors
- [Aus Quellcode bauen](docs/development/building.mdx) &mdash; Bauen, Testen, Lint und Debuggen
- [Code-Stil](docs/development/code-style.mdx) &mdash; SwiftLint, SwiftFormat und Konventionen

## Beitragen

Alle Arten von Beitr&auml;gen sind willkommen &mdash; Code, Tests, Dokumentation, Fehlerberichte und UX-Feedback.

Siehe **[CONTRIBUTING.md](CONTRIBUTING.md)** f&uuml;r Einrichtungsanweisungen, Code-Stil und die vollst&auml;ndige PR-Checkliste.

Einsteigerfreundliche Issues sind mit [`good first issue`](https://github.com/LocNguyenHuu/Rockxy/labels/good%20first%20issue) gekennzeichnet. Mit dem Einreichen eines PRs stimmen Sie dem [CLA](CLA.md) zu.

## Sponsoren und Partner

Rockxy wird von unabh&auml;ngigen Entwicklern gebaut und gewartet. Sponsoring finanziert die kontinuierliche Entwicklung, Sicherheits&uuml;berpr&uuml;fungen und neue Funktionen.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Rockxy_sponsern-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Rockxy sponsern" />
  </a>
</p>

| Stufe | Vorteile |
|-------|----------|
| **Gold Sponsor** | Logo auf README + Docs-Seite, priorisierte Feature-Anfragen, dedizierter Support-Kanal |
| **Silver Sponsor** | Logo auf README, namentliche Erw&auml;hnung in Release-Notes |
| **Bronze Sponsor** | Namentliche Erw&auml;hnung in README und Dokumentation |
| **Partner** | Co-Entwicklung, Integrations-Support, fr&uuml;her Zugang zu kommenden Features |

**Partnerschaftsanfragen** &mdash; Entwicklertool-Unternehmen, Sicherheitsfirmen und Enterprise-Teams, die individuelle Integrationen oder White-Label-L&ouml;sungen suchen: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Support

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) &mdash; Rockxys Entwicklung unterst&uuml;tzen
- [GitHub Issues](https://github.com/LocNguyenHuu/Rockxy/issues) &mdash; Fehlerberichte und Feature-Anfragen
- [GitHub Discussions](https://github.com/LocNguyenHuu/Rockxy/discussions) &mdash; Fragen und Community-Chat
- **E-Mail** &mdash; [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Sicherheitsprobleme** &mdash; siehe [SECURITY.md](SECURITY.md) f&uuml;r verantwortungsvolle Offenlegung

## Lizenz

[GNU Affero General Public License v3.0](LICENSE) &mdash; Copyright 2024&ndash;2026 Rockxy Contributors.

---

<p align="center">
  <sub>Entwickelt mit Swift, SwiftNIO, SwiftUI und AppKit.</sub>
</p>
