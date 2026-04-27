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

## Highlights des aktuellen Branches

- Developer Setup Hub deckt jetzt Runtimes, Browser, Clients, Ger&auml;te, Frameworks und Umgebungen mit zielgerichteten Snippets, Validierungs-Watchern und ehrlicher Guide-Dokumentation ab.
- Wenn SSL Proxying pro Domain oder App aktiviert bzw. deaktiviert wird, bleiben die HTTPS-Aufforderung, Sidebar-Aktionen und die Haupttabelle synchron.
- Inspektor und Haupttabelle wurden weiter verfeinert: einzeilige scrollbare Tabs, oben ausgerichteter Query-Inhalt, klarere Trennung von Status/Code, Request/Response-Byte-Spalten, Duration-Korrekturen und live aktualisierte SSL-Statussymbole.

## Funktionen

**Traffic-Erfassung** &mdash; SwiftNIO-basierter Proxy mit CONNECT-Tunnel, automatischer TLS-Zertifikatsgenerierung pro Host, WebSocket-Frame-Erfassung und automatischer GraphQL-Operationserkennung.

**Alles inspizieren** &mdash; JSON-Baumansicht, Hex-Inspektor, Timing-Wasserfall (DNS/TCP/TLS/TTFB/Transfer), Header, Cookies, Query-Parameter, Authentifizierung &mdash; alles in einem Tab-basierten Inspektor.

**Mock und Modifikation** &mdash; Map Local (Antworten aus lokalen Dateien), Map Remote (Umleitung zu anderem Server), Breakpoints (Pause und Bearbeitung w&auml;hrend der &Uuml;bertragung), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**Log-Korrelation** &mdash; macOS-Systemlogs (OSLog) erfassen und per Zeitstempel mit Netzwerkanfragen korrelieren. Sehen, welche App jede Anfrage gesendet hat.

**Mit Plugins erweitern** &mdash; JavaScript-Scripting in einer sandboxed JavaScriptCore-Laufzeit. Traffic mit benutzerdefinierten Hooks inspizieren, modifizieren und automatisieren.

**F&uuml;r Skalierung gebaut** &mdash; NSTableView mit virtuellem Scrollen f&uuml;r 100k+ Anfragen. Ringpuffer-Eviction, Disk-Body-Offloading, gebatchte UI-Updates. Keine Verz&ouml;gerung.

**Developer Setup Hub** &mdash; Gef&uuml;hrte Einrichtung pro Runtime, Browser, Ger&auml;t, Framework und Umgebung mit kopierbaren Snippets, Validierungsproben und Troubleshooting-Hinweisen.

**AI-Ready (MCP Server)** &mdash; Integrierter Model Context Protocol-Server, mit dem Claude CLI, Claude Desktop und andere MCP-Clients live Traffic, Regeln und Proxy-Status direkt aus dem Chat abfragen k&ouml;nnen. Nur lokal, Token-authentifiziert, sensible Daten werden standardm&auml;&szlig;ig maskiert.

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
- [x] Model Context Protocol (MCP)-Server f&uuml;r KI-Assistenten (Claude CLI, Claude Desktop)
- [ ] HTTP/2- und HTTP/3-Unterst&uuml;tzung
- [ ] Remote-Ger&auml;te-Proxy (iOS &uuml;ber USB/Wi-Fi)
- [ ] Headless-Modus f&uuml;r CI/CD-Pipelines
- [ ] gRPC / Protocol Buffers-Inspektion
- [ ] Fehlergruppierung und Analyse-Dashboard

## Dokumentation

Vollst&auml;ndige Dokumentation verf&uuml;gbar unter [Rockxy Docs](docs/index.mdx):

- [Schnellstart-Anleitung](docs/quickstart.mdx) &mdash; in wenigen Minuten einsatzbereit
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) &mdash; Runtime-Snippets, Ger&auml;te-Guides, Validierungsproben und Support-Matrix
- [Architektur](docs/development/architecture.mdx) &mdash; Proxy-Engine, Actor-Modell, Datenfluss
- [Sicherheitsmodell](docs/development/security.mdx) &mdash; Vertrauensgrenzen, XPC-Validierung, Zertifikatsverwaltung
- [Design-Entscheidungen](docs/development/design-decisions.mdx) &mdash; warum SwiftNIO, NSTableView, Actors
- [Aus Quellcode bauen](docs/development/building.mdx) &mdash; Bauen, Testen, Lint und Debuggen
- [Code-Stil](docs/development/code-style.mdx) &mdash; SwiftLint, SwiftFormat und Konventionen
- [Changelog](CHANGELOG.md) &mdash; aktuelle Branch-&Auml;nderungen und Verlauf der getaggten Releases

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

## Sterne-Verlauf

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Entwickelt mit Swift, SwiftNIO, SwiftUI und AppKit.</sub>
</p>
