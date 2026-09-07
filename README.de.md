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
  <strong>Quelloffener, &uuml;berpr&uuml;fbarer Debugging-Proxy f&uuml;r macOS.</strong>
</p>

<p align="center">
  HTTP/HTTPS/WebSocket/GraphQL-Traffic mit einer nativen Swift-App abfangen, inspizieren und modifizieren, die Sie pr&uuml;fen, bauen und vertrauen k&ouml;nnen.<br>
  Gebaut f&uuml;r API-, Mobile-, MCP-gest&uuml;tzte, KI- und Blockchain-&Auml;ra-Debugging-Workflows, w&auml;hrend Rockxy weiterw&auml;chst.<br>
  Eine local-first, AGPL-3.0 Alternative zu <a href="#rockxy-vs-alternativen">Proxyman und Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Plattform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Lizenz" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs willkommen" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsern" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/26380?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-26380" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/26380/daily?language=Swift" alt="RockxyApp/Rockxy | Trendshift" width="250" height="55" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy auf macOS" width="800" />
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

## Highlights des aktuellen Branches

- AI Assistant untersucht eine oder mehrere ausgew&auml;hlte Anfragen mit integrierter lokaler Analyse oder einem konfigurierten Ollama/provider-Modell, mit explizitem Review Data, begrenzter Redaction, Streaming-Antworten, Evidence Reveal und nutzerinitiierten Handoffs.
- Die native Sidebar bietet jetzt wiederverwendbare Focus Sets f&uuml;r App/Domain/Path-Scopes und workspace-spezifisches Noise Control, das passende Domains oder Pfade verbirgt, ohne die Erfassung zu stoppen.
- Der Haupt-Workspace nutzt native vertikale und horizontale Split Views f&uuml;r Context Dock und unteren Inspektor, mit durchgehenden Dividern, abgestimmten Toolbar/Footer-Separatoren und automatischer Layout-Anpassung.
- Upstream Proxy enth&auml;lt jetzt eine free/core Automatic Proxy Configuration mit PAC-URL-Routing f&uuml;r `DIRECT` -, HTTP- und HTTPS-Routen, w&auml;hrend bestehende SOCKS5- und Authentifizierungs-Policy-Grenzen erhalten bleiben.
- Export-Workflows decken jetzt OpenAPI YAML/HTML und die Gist-Ver&ouml;ffentlichung ausgew&auml;hlten Traffics mit redaction-aware Payload-Building ab.
- Inspektor-Werkzeuge enthalten jetzt JSONPath/key/value-Filterung und schnelle Previews f&uuml;r ausgew&auml;hlten Payload-Text wie JWTs.
- KI- und Web3-Traffic-Inspektion bietet Protokoll-Labels, Inspektor-Tabs und Debug-Zusammenfassungen f&uuml;r erkannte Modellaufrufe, JSON-RPC-Traffic und x402-Payment-Hinweise.
- Node.js Developer Setup spiegelt jetzt den ausgew&auml;hlten Client w&auml;hrend der Validierung und hat einen vollst&auml;ndigeren localhost-Beispielguide.
- Developer Setup Hub deckt jetzt Runtimes, Browser, Clients, Ger&auml;te, Frameworks und Umgebungen mit zielgerichteten Snippets, Validierungs-Watchern und ehrlicher Guide-Dokumentation ab.
- Die WebSocket-Binary-Frame-Inspektion bietet jetzt begrenzte, bedarfsgesteuerte Protobuf-Wire-Format-Heuristiken, ohne Decoder-Arbeit in den Capture-Hot-Path zu legen.
- Die &ouml;ffentliche Roadmap fokussiert tiefere protokollbewusste Regeln, Replay, Vergleich und sichereres Teilen redigierter Evidence.

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

### Focus Sets und Noise Control

Machen Sie wiederkehrende Untersuchungen zu wiederverwendbaren Sidebar-Scopes. Focus Sets kombinieren App-, Domain- und Path-Includes mit Domain/Path-Excludes, bleiben nach Neustarts erhalten und stehen in jedem Workspace zur Verf&uuml;gung. Noise Control erfasst Telemetrie und anderen geringwertigen Traffic weiter, verbirgt ihn aber im aktuellen Workspace.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant erkl&auml;rt ausgew&auml;hlten Traffic neben nativer Request-Tabelle und Sidebar" width="820" />

W&auml;hlen Sie eine oder mehrere erfasste Anfragen und fragen Sie, was passiert ist, was fehlgeschlagen ist, was sich ge&auml;ndert hat oder was als N&auml;chstes zu pr&uuml;fen ist. Rockxy beginnt mit evidenzbasierter Analyse auf diesem Mac; ein konfiguriertes Ollama- oder provider-Modell l&auml;uft erst, nachdem Review Data den exakten, begrenzten und redigierten Kontext zeigt. Antworten k&ouml;nnen Source Requests offenlegen und native Follow-up-Workflows vorbereiten, ver&auml;ndern Traffic oder f&uuml;hren Aktionen aber nie automatisch aus.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[AI-Assistant-Anleitung lesen](docs/features/ai-assistant.mdx).

### MCP-Server f&uuml;r externe KI-Clients

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Lassen Sie Claude Desktop oder Cursor Ihren erfassten Traffic &uuml;ber zehn schreibgesch&uuml;tzte Tools im lokalen MCP-Server von Rockxy inspizieren. Fragen Sie "warum hat das 500 ergeben?", statt Header in den Chat zu kleben. Die Implementierung ist Open Source, Token-authentifiziert und h&auml;lt die Maskierung sensibler Daten standardm&auml;&szlig;ig aktiviert.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Bef&ouml;rdern Sie jeden Request- oder Response-Header zu einer erstklassigen Spalte in der Traffic-Tabelle. Halten Sie Request- und Response-Quellen getrennt, speichern Sie die Header, die Sie interessieren, und scannen Sie dann Request-IDs, Trace-IDs, Cache-Status oder eigene Metadaten, ohne jeden Inspektor zu &ouml;ffnen.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Netzwerkbedingungen

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Drosseln Sie auf 3G, EDGE, LTE, WiFi oder eine eigene Latenz. Ihr Laptop l&auml;uft an Glasfaser; Ihre Nutzer nicht &mdash; sehen Sie die UX bei 400 ms RTT, bevor sie es tun.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose &mdash; Bearbeiten und Replay

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Bauen Sie jede erfasste HTTP-Anfrage neu auf &mdash; &auml;ndern Sie Method, URL, Header, Query-Parameter oder Body &mdash; und senden Sie sie erneut, ohne Rockxy zu verlassen. Keine Copy-Paste-Schleife zu Postman, Insomnia oder curl. Iterieren Sie LLM-Prompts, fuzzen Sie Auth-Grenzen oder reproduzieren Sie einen fehlgeschlagenen Fall f&uuml;r OpenAI-, Anthropic- und Cohere-Endpunkte in Sekunden.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Vergleichen

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Stapeln Sie zwei erfasste Transaktionen oder eingef&uuml;gte Payloads nebeneinander und finden Sie jedes Feld, das gekippt ist &mdash; Status, Header, JSON-Schl&uuml;ssel oder Body-Bytes. Fangen Sie stille API-Regressionen, nicht-deterministische LLM-Ausgaben und Prompt-Drift, ohne etwas in ein Drittanbieter-Diff-Tool zu pipen.

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy Multi-Tab-Workspaces mit unabh&auml;ngig gefilterten Ansichten derselben Live-Capture" width="820" />

Halten Sie unabh&auml;ngige Untersuchungsansichten derselben Live-Capture nebeneinander &mdash; ein Tab f&uuml;r Staging-Traffic, einer f&uuml;r Produktion und einer f&uuml;r einen iOS-Ger&auml;te-Flow. Jeder Tab besitzt eigene Filter, Sortierung, Auswahl, Sidebar-Scope und Inspektor-Zustand, teilt aber Proxy und erfasste Transaktionen.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript-Scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS-Hooks auf Requests und Responses f&uuml;r F&auml;lle, die eine statische Regel nicht abdeckt &mdash; PII redacten, Token signieren, Payloads umschreiben. Fehler erscheinen inline, anstatt den Traffic zu besch&auml;digen.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Protokollbewusste Inspektion

Rockxy bietet protokollbewusste KI-, Web3-RPC- und x402-Inspektion im normalen HTTP-Debugging-Workflow.

### KI-Traffic-Inspektion

Rockxy erkennt erkannte KI-Anfragen im normalen Capture-Workflow. Inspizieren Sie ausgew&auml;hlte Modellaufrufe, Streaming-Status, Usage-Felder falls vorhanden, Warnungen, Retrieval-Hints und Tool-Call-Zusammenfassungen, ohne sensible Payloads in einen anderen Dienst zu kopieren.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC-Inspektion

Rockxy verwandelt Netzwerkaufrufe der Blockchain-&Auml;ra in lesbare Debugging-Evidence. Inspizieren Sie EVM- und Solana-artigen HTTP-JSON-RPC-Traffic mit Provider Host, Request ID, Methode, Batch-Zusammenfassung, Fehler, Chain, Transaktion, Payload und Debug-Intent, ohne Rockxy zu Wallet oder Block Explorer zu machen.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402-Payment-Flow-Hinweise

Rockxy hebt payment-required und retry-orientierte Hinweise hervor, sodass payment-gated HTTP-Flows von der Netzwerkebene aus verst&auml;ndlich sind, w&auml;hrend die Debugging-Evidence lokal und redaction-aware bleibt.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Zuk&uuml;nftige Arbeiten

Die folgenden Abschnitte beschreiben die &ouml;ffentliche Richtung, nicht aktuelles Verhalten.

### Protokollbewusste Regeln

Rockxy kann KI- und Web3-Traffic heute labeln und inspizieren. Tieferes Rule Matching nach Modell, Tool Call, JSON-RPC-Methode, Chain, Transaction Hash oder Batch Subcall bleibt zuk&uuml;nftige Arbeit; aktuelle Traffic-Modifikation matcht URL, HTTP-Methode und Header.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Redigierte Evidence-Bundles `Demn&auml;chst`

Teilen Sie die Fakten, die f&uuml;r einen Bug-Repro n&ouml;tig sind, ohne Secrets zu leaken. Ausgew&auml;hlten Traffic mit Protokollzusammenfassungen, Redaction-Previews und source-backed Kontext paketieren, den Kollegen pr&uuml;fen k&ouml;nnen.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Team-Sharing und Zusammenarbeit `Demn&auml;chst`

Senden Sie eine erfasste Session mit einem Klick an einen Kollegen. Annotieren Sie fehlgeschlagene Anfragen inline, sehen Sie in Echtzeit, wer was anschaut, und pair-debuggen Sie HTTPS-Traffic ohne Screensharing. Ziel f&uuml;r ein zuk&uuml;nftiges Release.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Native macOS-App-Shell &mdash; kein Electron. SwiftUI + AppKit + SwiftNIO, wobei WebKit nur f&uuml;r die HTML-Body-Vorschau verwendet wird.

## Schnellstart

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

In Xcode bauen und ausf&uuml;hren. Das Willkommensfenster f&uuml;hrt durch die Root-CA-Einrichtung, Helper-Installation und Proxy-Aktivierung.

**Voraussetzungen:** macOS 14.0+, Xcode 16+, Swift 5.9

Wenn Sie Rockxy nach der Installation mit einem lokalen MCP-Client verbinden m&ouml;chten, siehe den [MCP-Integrationsguide](docs/features/mcp.mdx).

## Rockxy vs. Alternativen

Die Hauptmatrix umfasst allgemeine Web-Debugging-Proxys. Sicherheitstests
Suiten und browser-/API-orientierte Interceptoren mit erheblichen Workflow-Überschneidungen
werden separat aufgeführt, sodass unterschiedliche Produkte nicht als austauschbar dargestellt werden.
Paketanalysatoren und Nur-API-Clients fallen nicht in diesen Vergleich.

### Direkte Web-Debugging-Proxys

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Produktform** | Nativer macOS-Debugging-Proxy | Native macOS-App; Electron-basierte Windows-/Linux-Editionen | Plattformübergreifender Desktop-Debugging-Proxy | Plattformübergreifendes CLI/TUI- und Web-UI-Proxy-Toolkit | Plattformübergreifender Electron Desktop-Proxy und HTTP-Client | Plattformübergreifender Desktop-Debugging-Proxy |
| **Quelle und Build-Modell** | Öffentlicher Community-Quellcode unter AGPL-3.0-or-later; mit Xcode baubar. Der offizielle DMG enthält außerdem nicht öffentliche Downstream-Komponenten | Geschlossener Quellcode; in den geprüften offiziellen Materialien wurde kein öffentlicher Anwendungsquellcode identifiziert | Geschlossener Quellcode; in den geprüften offiziellen Materialien wurde kein öffentlicher Anwendungsquellcode identifiziert | Öffentlicher MIT-lizenzierter Quellcode; aus dem Quellcode baubar | Öffentlicher AGPL-Desktop-Quellcode; aus dem Quellcode baubar; veröffentlichte Binärdateien haben zusätzliche Lizenzoptionen | Geschlossener Quellcode; als Objektcode unter der Fiddler Everywhere EULA verteilt |
| **Erfassung und Einrichtung** | Lokaler System-Proxy mit geführter Einrichtung für Mac-Apps, Laufzeiten, iOS-Geräte und Simulator | Automatische Einrichtung für Mac-Apps, Runtimes und mobile Geräte | Lokaler Proxy mit macOS-, iOS- und plattformübergreifenden Einrichtungshandbüchern | Regulärer, lokaler Prozess, WireGuard, umgekehrter, transparenter und andere Erfassungsmodi | Gezieltes und manuelles Proxy-Abfangen für Browser, Laufzeiten, Container und mobile Geräte | System-, Netzwerk-, Browser-, Terminal-, explizite und Remote-Geräte-Erfassungsmodi |
| **Ändern und verspotten** | Haltepunkte, Map Local/Remote, Header-Regeln, Blockierung und Latenzregeln | Haltepunkte, Map Local/Remote, Blocklisten, Netzwerkbedingungen und JavaScript-Regeln | Haltepunkte, Umschreiben, Map Local/Remote, Blockierung und Drosselung | Map Local/Remote, Body-/Header-Änderung, Blockierung und Serverwiedergabe | Haltepunkte sowie regelbasiertes Umschreiben, Umleiten, Mock und Fehlerinjektion; Einige Automatisierungen sind planbegrenzt | Regeln, Haltepunkte, Weiterleitungen, Antwortmodifikation und Mocking |
| **Wiederholen und vergleichen** | Verfassen/Wiedergeben plus lokaler paralleler Vergleich von Anfrage, Header und Text | Verfassen, Wiederholen und Vergleichen | Anfragen wiederholen und bearbeiten | Clientseitige und serverseitige Wiedergabe | Integrierter HTTP-Client zum Verfassen und Senden von Anfragen | API Composer, Traffic-Wiedergabe und Traffic-Vergleich als Beta dokumentiert |
| **WebSocket-Workflows** | Text-/Binärrahmenprüfung mit begrenzter Protobuf-Heuristik | WS/WSS Inspektion; Skripte können Handshake-URLs/Header ändern, nicht Nachrichten | Die Unterstützung von WebSocket ist im offiziellen Versionsverlauf | dokumentiert WebSocket Abfangen und Skripting; WebSocket-Wiedergabe wird nicht unterstützt | WebSocket-Inspektion plus WebSocket-spezifische Regeln | WebSocket Erfassung und Inspektion |
| **Skripting und Erweiterbarkeit** | Sandboxed JavaScriptCore-Hooks mit einem begrenzten API und einem Ausführungszeitlimit | JavaScript Anforderungs-/Antwort-Skripting | Regeln neu schreiben und ein Kontroll-Webinterface einrichten; keine allgemeine JavaScript-Skriptfunktion dokumentiert | Python Addons und Befehlszeilenautomatisierung | Regelbasierte Automatisierung plus öffentliche Quell- und Proxy-Bibliotheken | Regelbasierte Automatisierung; keine allgemeine Skripting-Funktion von Erstanbietern dokumentiert |
| **Upstream-Routing** | [HTTP/HTTPS Upstream-Proxy und PAC URL-Routing](docs/features/upstream-proxy.mdx); Die Community-Richtlinie deaktiviert die Proxy-Authentifizierung und SOCKS5 und begrenzt die Umgehungsregeln auf drei | Externes HTTP/HTTPS/SOCKS- und PAC-Routing mit Bypass-Regeln | Externe HTTP/HTTPS/SOCKS-Proxys mit Authentifizierungs- und Umgehungsregeln | HTTP/HTTPS-Upstream-Modus plus Reverse- und SOCKS-Listener-Modus | System-, HTTP-, HTTPS- und SOCKS-Upstream-Einstellungen; Es können Planbeschränkungen gelten | Automatische Verkettung an System-Proxys plus Reverse-Proxy-Erfassung |
| **AI und MCP** | [In-App AI Assistant](docs/features/ai-assistant.mdx) und [integriertes lokales MCP](docs/features/mcp.mdx) mit 10 schreibgeschützten Tools, Token-Authentifizierung und standardmäßig aktivierter Maskierung | Integriertes MCP für externe KI-Clients, einschließlich Traffic-Lesezugriff und App-/Regelsteuerung | Nicht dokumentiert | Nicht dokumentiert | In der aktuellen offiziellen Quelle ist eine gebündelte lokale MCP-Brücke vorhanden; kein In-App-Assistent dokumentiert | Integriertes MCP sowie ein Debugging Assistant im Pro-Tarif; laut aktueller Dokumentation müssen erfasste Traffic-Details in den Chat eingefügt werden |

### Benachbarte Abfangwerkzeuge

Diese Produkte überschneiden sich deutlich mit Rockxy, sind aber bei Sicherheitstests führend.
Browserregeln oder API-Client-Workflows anstelle derselben Allzweck-Workflows
nativer Debugging-Proxy-Fokus.

| **Produkt** | **Warum es benachbart ist** | **Quelle und Build-Modell** | **Relevante Überschneidung** | **AI und MCP** |
|---|---|---|---|---|
| **Burp Suite** | Web-Sicherheitstestsuite mit einem abfangenden Proxy | Closed-Source-Anwendung; Sein EULA besagt, dass Benutzer kein Recht auf die Anwendungsquelle haben. Erweiterungen können separate Lizenzen verwenden | Proxy-Abfangen und Match/Replace, Repeater, WebSockets, Upstream/SOCKS-Proxying und ein großes Erweiterungs-Ökosystem | Burp AI ist in Repeater verfügbar; PortSwigger unterhält außerdem eine öffentliche MCP-Servererweiterung für externe KI-Clients |
| **ZAP** | Sicherheitsscanner und abfangender Proxy | Öffentliche Apache-2.0-Quelle; aus dem Quellcode erbaubar | Abfangen/Bearbeiten, manuelles erneutes Senden, WebSocket-Haltepunkte und Skripte, mehrsprachiges Skripting, Add-ons und Automatisierung | Offizielle MCP-Integration und optionale LLM-Support-Add-ons |
| **Requestly HTTP Interceptor** | Browser-Erweiterung und plattformübergreifendes Desktop-Interceptor/Mock-Tool | Öffentliche AGPL-Desktop-Interceptor-Quelle; Der separate Requestly API-Client ist gemäß seinem öffentlichen Community-Repository-Hinweis | proprietär Systemweite/Browser-Erfassung, Umleitung, Map Local/Remote, Header-/Body-Änderung, JavaScript-Transformationen, Mocks und Verzögerungs-/Fehlersimulation | Ein separater offizieller MCP-Server verwaltet Regeln und Gruppen; kein In-App-Assistent zur Verkehrsanalyse dokumentiert |

Die Verfügbarkeit von Funktionen kann je nach Edition, Plan, Plattform oder Add-on variieren.
„Nicht dokumentiert“ bedeutet, dass eine Funktion im offiziellen Erstanbieter nicht gefunden wurde
Quellen überprüft auf 2026-08-22; es ist kein Beweis dafür, dass die Fähigkeit fehlt.
Die obigen Produkt- und Funktionsaussagen wurden anhand der Herstellerdokumentation überprüft.
vom Anbieter verwaltete Quellrepositorys oder die Lizenzbedingungen des Anbieters zu diesem Zeitpunkt und
kann sich ändern. Produktnamen und Marken gehören ihren jeweiligen Eigentümern;
Rockxy ist nicht mit ihnen verbunden oder wird von ihnen unterstützt. Korrekturen sind willkommen
über den Issue-Tracker Rockxy.

Auf der Roadmap: tiefergehende protokollbewusste Regeln, sicherere redigierte Beweisbündel, stärkere Wiedergabe- und Vergleichs-Workflows, umfassendere Entwickler-Setup-Anleitungen und fortgesetzte HTTP/2- und HTTP/3-Forschung.

## Sicherheit

Rockxy fängt Netzwerk-Traffic ab &mdash; Sicherheit ist fundamental, nicht optional.

- Der XPC-Helper validiert Aufrufer durch **Zertifikatsketten-Vergleich**, nicht nur durch Bundle-ID
- Plugins laufen in **sandboxed JavaScriptCore** mit 5-Sekunden-Timeout, ohne Dateisystem-/Netzwerkzugang
- **Eingabevalidierung** an allen Grenzen &mdash; Body-Gr&ouml;&szlig;enbegrenzungen, URI-Limits, Regex-DoS-Schutz, Path-Traversal-Pr&auml;vention
- Anmeldeinformationen werden in Logs **automatisch maskiert**
- Sensible Dateien werden mit **0o600-Berechtigungen** gespeichert

Schwachstellen melden &uuml;ber [SECURITY.md](SECURITY.md). Siehe die [vollst&auml;ndige Sicherheitsarchitektur](docs/development/security.mdx) f&uuml;r Details.

## Roadmap

Rockxys &ouml;ffentliche Roadmap ist workflow-orientiert und ohne feste Datumsversprechen. Sie konzentriert sich auf Zuverl&auml;ssigkeit, native macOS-UX, Debugging-Workflows, Protokollunterst&uuml;tzung, Traffic-Sichtbarkeit f&uuml;r die KI/Web3-&Auml;ra, Dokumentation und Contributor-Onboarding.

- [ROADMAP.md](ROADMAP.md): &ouml;ffentliche technische Richtung auf hoher Ebene
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): operative Sicht auf roadmap-relevante Issues

## Dokumentation

Vollst&auml;ndige Dokumentation verf&uuml;gbar unter [Rockxy Docs](docs/index.mdx):

- [Schnellstart-Anleitung](docs/quickstart.mdx) &mdash; in wenigen Minuten einsatzbereit
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) &mdash; Runtime-Snippets, Ger&auml;te-Guides, Validierungsproben und Support-Matrix
- [AI Assistant](docs/features/ai-assistant.mdx) &mdash; ausgew&auml;hlten Traffic lokal oder mit einem nach Review Data konfigurierten Modell untersuchen
- [Filter und Suche](docs/core-features/filters-and-search.mdx) &mdash; Sidebar-Scopes, Focus Sets, Noise Control, Toolbar-Filter und Suche
- [KI- und Web3-Inspektion](docs/features/ai-web3-inspection.mdx) &mdash; erkannten Model-API-, JSON-RPC- und x402-Traffic inspizieren
- [MCP-Integration](docs/features/mcp.mdx) &mdash; Rockxy mit lokalen MCP-Clients verbinden
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

Rockxy wird unabh&auml;ngig gewartet. Sponsoring hilft, die kontinuierliche Entwicklung, Release-Infrastruktur, Dokumentation und Sicherheitsarbeit zu finanzieren.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Rockxy sponsern" />
  </a>
</p>

Rockxy wird finanziell vom [Open Source Collective](https://docs.oscollective.org/) betreut. Beitr&auml;ge und Projektausgaben werden auf der [&ouml;ffentlichen Open-Collective-Seite von Rockxy](https://opencollective.com/rockxy) erfasst, sodass Unterst&uuml;tzende transparent nachvollziehen k&ouml;nnen, wie Mittel eingehen und verwendet werden.

| Stufe | Beitrag | Unterst&uuml;tzt |
|-------|---------|---------------|
| **Backer** | Ab $5/Monat | Open-Source-Wartung, Dokumentation, Tests und Releases |
| **Builder** | Ab $25/Monat | Regressionstests, Leistungsverbesserungen und allt&auml;gliche Debugging-Workflows |
| **Sponsor** | $100/Monat | Langfristige Wartung eines datenschutzorientierten Tools, das f&uuml;r Entwickler kostenlos bleibt |
| **Sustaining Sponsor** | $500/Monat | Konzentrierte Wartung und Produktentwicklung, einschlie&szlig;lich Release-Automatisierung und Protokollunterst&uuml;tzung |

**Partnerschaftsanfragen** &mdash; Entwicklertool-Unternehmen, Sicherheitsfirmen und Enterprise-Teams, die individuelle Integrationen oder White-Label-L&ouml;sungen suchen: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Support

- [Open Collective](https://opencollective.com/rockxy/donate) &mdash; &uuml;ber das transparente Projektbudget zu Rockxy beitragen
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) &mdash; Rockxys Entwicklung unterst&uuml;tzen
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) &mdash; Fehlerberichte und Feature-Anfragen
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) &mdash; Fragen und Community-Chat
- **E-Mail** &mdash; [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Sicherheitsprobleme** &mdash; siehe [SECURITY.md](SECURITY.md) f&uuml;r verantwortungsvolle Offenlegung

## Lizenz

[GNU Affero General Public License v3.0](LICENSE) &mdash; Copyright 2024&ndash;2026 Rockxy Contributors.

## Sterne-Verlauf

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Entwickelt mit Swift, SwiftNIO, SwiftUI und AppKit.</sub>
</p>
