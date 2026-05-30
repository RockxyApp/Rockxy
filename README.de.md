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
  <strong>Quelloffener, &uuml;berpr&uuml;fbarer HTTP-Debugging-Proxy f&uuml;r macOS.</strong>
</p>

<p align="center">
  HTTP/HTTPS/WebSocket/GraphQL-Traffic mit einer nativen Swift-App abfangen, inspizieren und modifizieren, die Sie pr&uuml;fen, bauen und vertrauen k&ouml;nnen.<br>
  Eine local-first, AGPL-3.0 Alternative zu <a href="#rockxy-vs-alternativen">Proxyman und Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Plattform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Lizenz" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs willkommen" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsern" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Light.png" alt="Rockxy auf macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.23.0** — 2026-05-29

### Added

- Added a more powerful advanced filter builder for narrowing traffic by URL, method, status, headers, body, app, domain, and other request or response fields.
- Added saved filter presets and inspector match highlighting so repeated investigations are faster to resume.
- Added upstream HTTP/HTTPS proxy support for routing captured traffic through another proxy when your network or lab setup requires it.
- Added Tools menu entries for external proxy settings, SOCKS proxy settings, Protobuf mappings, and Protobuf schema management.
- Added WebSocket Protobuf previews that make binary frame payloads easier to inspect as readable field trees.

### Fixed

- Fixed bypass proxy handling during TLS setup so bypassed hosts avoid interception more reliably.
- Improved scripting stability so request and response scripts handle headers, console output, and runtime errors more reliably.
- Strengthened redaction for local integration exports so sensitive request and rule data stays protected.
- Improved HAR imports and content-type detection for better handling of modern JSON-style responses and imported sessions.
- Improved sidebar grouping cleanup when selected domain/app groups disappear, keeping active filters and sidebar state aligned.

### Changed

- Refined multi-tab workspace behavior so tabs, selection, and window placement feel more predictable.
- Polished the proxy status indicator and workspace tab chrome for clearer capture state at a glance.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Highlights des aktuellen Branches

- Developer Setup Hub deckt jetzt Runtimes, Browser, Clients, Ger&auml;te, Frameworks und Umgebungen mit zielgerichteten Snippets, Validierungs-Watchern und ehrlicher Guide-Dokumentation ab.
- Wenn SSL Proxying pro Domain oder App aktiviert bzw. deaktiviert wird, bleiben die HTTPS-Aufforderung, Sidebar-Aktionen und die Haupttabelle synchron.
- Inspektor und Haupttabelle wurden weiter verfeinert: einzeilige scrollbare Tabs, oben ausgerichteter Query-Inhalt, klarere Trennung von Status/Code, Request/Response-Byte-Spalten, Duration-Korrekturen und live aktualisierte SSL-Statussymbole.

## Funktionen

Die Werkzeuge, zu denen Sie greifen, wenn die Browser-DevTools nicht mehr reichen. Kerntraffic-Debugging f&uuml;r Mac- und iOS-Arbeit &mdash; nativ macOS, mit &ouml;ffentlichen Releases und Local-First-Workflow.

### Traffic-Erfassung

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Inspizieren Sie HTTP-, HTTPS-, WebSocket- und GraphQL-Traffic aus jeder Mac-App, jedem CLI oder iOS-Ger&auml;t. Browser-DevTools enden im Browser &mdash; Rockxy sieht den Rest Ihres Stacks.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Erweiterte Filter und Suche

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Reduzieren Sie Tausende erfasster Anfragen in Sekunden. Kombinieren Sie Filter f&uuml;r Method, Host, Status, Header, Body und Prozess &mdash; oder f&uuml;hren Sie eine Volltextsuche &uuml;ber die gesamte Session aus.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### MCP-Server f&uuml;r KI-Assistenten

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Lassen Sie Claude Desktop oder Cursor &uuml;ber einen lokalen MCP-Server Ihren erfassten Traffic lesen. Fragen Sie "warum hat das 500 ergeben?", statt Header in den Chat zu kleben. Kostenloser MCP-Server &mdash; kein bezahltes KI-Add-on, kein Nutzungslimit.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Kopieren Sie Proxy-Snippets f&uuml;r Python, Node.js, Go, Rust, cURL, Docker und Browser und klicken Sie auf Run Test, um zu best&auml;tigen, dass der Traffic tats&auml;chlich flie&szlig;t.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Zertifikatsverwaltung f&uuml;r HTTPS-Debugging

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Eine P-256-ECDSA-Root-CA, die beim ersten Start generiert und in Ihrem Keychain versiegelt wird. Entschl&uuml;sseln Sie HTTPS beim ersten Versuch; gepinnte Hosts werden automatisch durchgereicht.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL-Proxy und HTTPS-Entschl&uuml;sselung

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

W&auml;hlen Sie aus, welche Hosts TLS-entschl&uuml;sselt werden. Entschl&uuml;sselter Traffic zeigt echte Header und JSON; der Rest l&auml;uft verschl&uuml;sselt durch. Wildcard-Regeln erlauben Domain-Scoping mit einem Klick.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

&Uuml;berspringen Sie bestimmte Hosts, damit Cert-gepinnte Apps, interne Dienste oder l&auml;rmende Telemetrie nie in die Erfassung gelangen. Wildcards halten die Liste kurz und Ihr Anfrage-Log auf das Wesentliche fokussiert.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Lassen Sie jeden Host scheitern. Werfen Sie Werbenetzwerke, Drittanbieter-Tracker oder eine wackelige Abh&auml;ngigkeit raus, um zu sehen, wie Ihre App ohne sie degradiert &mdash; ohne eine Zeile Code zu &auml;ndern.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Liefern Sie statt einer Live-Antwort eine gespeicherte Datei oder einen Verzeichnisbaum aus. Tauschen Sie ein JSON-Payload, spielen Sie einen Snapshot erneut ab oder fixieren Sie eine wackelige Drittanbieter-API w&auml;hrend des Debuggens auf eine lokale Kopie.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Schreiben Sie das Ziel einer erfassten Anfrage um, ohne App-Code oder /etc/hosts anzufassen. Lenken Sie Produktions-Traffic auf Staging, Ihren Dev-Server oder den Rechner eines Kollegen f&uuml;r einen reproduzierbaren Bug-Repro um.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Breakpoints und Regeln

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Pausieren Sie eine Anfrage oder Antwort, bearbeiten Sie Method, Header, Body oder Status und fahren Sie fort. Der schnellste Weg, "was, wenn die API 401 zur&uuml;ckgibt?" zu testen, ohne das Backend anzufassen.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Header &auml;ndern

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

F&uuml;gen Sie auf jedem Host Header hinzu, entfernen oder ersetzen Sie sie, ohne neu zu deployen. Testen Sie CORS-, Auth- oder Cache-&Auml;nderungen in Sekunden mit eingebauten Presets.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Custom Request- und Response-Header

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

&Uuml;berschreiben Sie Header pro Host mit voller Kontrolle &uuml;ber beide Phasen. Injizieren Sie Auth-Token in ausgehende Anfragen, entfernen Sie Set-Cookie in Antworten oder fixieren Sie einen User-Agent &mdash; gespeichert als benannte Regeln, die jederzeit umschaltbar sind.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Netzwerkbedingungen

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Drosseln Sie auf 3G, EDGE, LTE, WiFi oder eine eigene Latenz. Ihr Laptop l&auml;uft an Glasfaser; Ihre Nutzer nicht &mdash; sehen Sie die UX bei 400 ms RTT, bevor sie es tun.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose &mdash; Bearbeiten und Replay

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Bauen Sie jede erfasste HTTP-Anfrage neu auf &mdash; &auml;ndern Sie Method, URL, Header, Query-Parameter oder Body &mdash; und senden Sie sie erneut, ohne Rockxy zu verlassen. Keine Copy-Paste-Schleife zu Postman, Insomnia oder curl. Iterieren Sie LLM-Prompts, fuzzen Sie Auth-Grenzen oder reproduzieren Sie einen fehlgeschlagenen Fall f&uuml;r OpenAI-, Anthropic- und Cohere-Endpunkte in Sekunden.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Vergleichen

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Stapeln Sie zwei erfasste Antworten nebeneinander und finden Sie jedes Feld, das gekippt ist &mdash; Status, Header, JSON-Schl&uuml;ssel, Body-Bytes. Fangen Sie stille API-Regressionen, nicht-deterministische LLM-Ausgaben und Prompt-Drift, ohne etwas in ein Drittanbieter-Diff-Tool zu pipen. Side-by-side-Diff hebt Unterschiede hervor; ein tiefer JSON-Vergleich ignoriert die Reihenfolge von Schl&uuml;sseln.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Custom Previewer-Tabs

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Rendern Sie Request- und Response-Bodys, wie Sie m&ouml;chten. Pinnen Sie zus&auml;tzliche Tabs an den Inspektor f&uuml;r JSON, GraphQL, JWT, Bilder oder Ihr eigenes Format &mdash; wiederverwendbar bei jeder erfassten Anfrage.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sessions und Export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Speichern Sie Sessions, importieren/exportieren Sie HAR f&uuml;r den Tool-&Uuml;bergang, kopieren Sie jede Anfrage als cURL oder JSON. Redacten Sie Authorization-Header, Cookies und Bearer-Token vor dem Teilen &mdash; geben Sie einem Kollegen einen funktionierenden Bug-Repro, ohne Geheimnisse zu lecken.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Multi-Tab-Workspaces

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

F&uuml;hren Sie unabh&auml;ngige Capture-Sessions parallel &mdash; ein Tab f&uuml;r Staging, einer f&uuml;r Prod, einer f&uuml;r den iOS-Ger&auml;te-Build. Jeder Tab beh&auml;lt seine eigenen Filter, Auswahl und Inspektor-Zust&auml;nde, sodass Kontextwechsel nahezu nichts kostet.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript-Scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS-Hooks auf Requests und Responses f&uuml;r F&auml;lle, die eine statische Regel nicht abdeckt &mdash; PII redacten, Token signieren, Payloads umschreiben. Fehler erscheinen inline, anstatt den Traffic zu besch&auml;digen.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

### Team-Sharing und Zusammenarbeit `Demn&auml;chst`

Senden Sie eine erfasste Session mit einem Klick an einen Kollegen. Annotieren Sie fehlgeschlagene Anfragen inline, sehen Sie in Echtzeit, wer was anschaut, und pair-debuggen Sie HTTPS-Traffic ohne Screensharing. Ziel f&uuml;r ein zuk&uuml;nftiges Release.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100 % natives macOS. Kein Electron. Keine Web-Views. SwiftUI + AppKit + SwiftNIO.
## Schnellstart

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

In Xcode bauen und ausf&uuml;hren. Das Willkommensfenster f&uuml;hrt durch die Root-CA-Einrichtung, Helper-Installation und Proxy-Aktivierung.

**Voraussetzungen:** macOS 14.0+, Xcode 16+, Swift 5.9

## Rockxy vs. Alternativen

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Projektmodell** | AGPL-3.0 Open-Source-Projekt | Propriet&auml;re kommerzielle App | Propriet&auml;re kommerzielle App |
| **Quellcode** | &Ouml;ffentlich, &uuml;berpr&uuml;fbar, forkbar | Geschlossener Quellcode | Geschlossener Quellcode |
| **Aus Source bauen** | Kostenlos mit Xcode aus diesem Repo | Nicht aus &ouml;ffentlichem Source verf&uuml;gbar | Nicht aus &ouml;ffentlichem Source verf&uuml;gbar |
| **Native macOS-Basis** | Swift + SwiftNIO + SwiftUI/AppKit | Native kommerzielle macOS-App | Plattform&uuml;bergreifende kommerzielle App |
| **Local-first Capture** | Lokaler Proxy, Zertifikate, Helper und Capture-Daten bleiben auf Ihrem Mac | Desktop-Proxy-App | Desktop-Proxy-App |
| **Developer-Setup-Workflow** | Integrierter Developer Setup Hub f&uuml;r Runtimes, Clients, Ger&auml;te, Frameworks und Umgebungen | Produktspezifische Setup-Guides | Produktspezifische Setup-Guides |
| **MCP/local automation bridge** | Integriert, Token-authentifiziert, standardm&auml;&szlig;ig maskiert | In gepr&uuml;ften &ouml;ffentlichen Docs nicht beansprucht | In gepr&uuml;ften &ouml;ffentlichen Docs nicht beansprucht |
| **Offener Beitragsweg** | &Ouml;ffentliche Issues, Discussions, Roadmap und PRs | Herstellerkontrolliertes Produkt | Herstellerkontrolliertes Produkt |

Auf der Roadmap: tiefere replay/diff/rules/scripting-Workflows, verbesserte WebSocket- und GraphQL-Inspektion sowie Erkundung von gRPC/Protobuf plus HTTP/2- und HTTP/3-Support.

## Sicherheit

Rockxy fängt Netzwerk-Traffic ab &mdash; Sicherheit ist fundamental, nicht optional.

- Der XPC-Helper validiert Aufrufer durch **Zertifikatsketten-Vergleich**, nicht nur durch Bundle-ID
- Plugins laufen in **sandboxed JavaScriptCore** mit 5-Sekunden-Timeout, ohne Dateisystem-/Netzwerkzugang
- **Eingabevalidierung** an allen Grenzen &mdash; Body-Gr&ouml;&szlig;enbegrenzungen, URI-Limits, Regex-DoS-Schutz, Path-Traversal-Pr&auml;vention
- Anmeldeinformationen werden in Logs **automatisch maskiert**
- Sensible Dateien werden mit **0o600-Berechtigungen** gespeichert

Schwachstellen melden &uuml;ber [SECURITY.md](SECURITY.md). Siehe die [vollst&auml;ndige Sicherheitsarchitektur](docs/development/security.mdx) f&uuml;r Details.

## Roadmap

Rockxys &ouml;ffentliche Roadmap ist workflow-orientiert und ohne feste Datumsversprechen. Sie konzentriert sich auf Zuverl&auml;ssigkeit, native macOS-UX, Debugging-Workflows, Protokollunterst&uuml;tzung, Dokumentation und Contributor-Onboarding.

- [ROADMAP.md](ROADMAP.md): &ouml;ffentliche technische Richtung auf hoher Ebene
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): operative Sicht auf roadmap-relevante Issues

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

Einsteigerfreundliche Issues sind mit [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue) gekennzeichnet. Mit dem Einreichen eines PRs stimmen Sie dem [CLA](CLA.md) zu.

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
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) &mdash; Fehlerberichte und Feature-Anfragen
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) &mdash; Fragen und Community-Chat
- **E-Mail** &mdash; [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Sicherheitsprobleme** &mdash; siehe [SECURITY.md](SECURITY.md) f&uuml;r verantwortungsvolle Offenlegung

## Lizenz

[GNU Affero General Public License v3.0](LICENSE) &mdash; Copyright 2024&ndash;2026 Rockxy Contributors.

## Sterne-Verlauf

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Entwickelt mit Swift, SwiftNIO, SwiftUI und AppKit.</sub>
</p>
