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
  <strong>De open source, controleerbare foutopsporingsproxy voor macOS.</strong>
</p>

<p align="center">
  Onderschep, inspecteer en wijzig HTTP/HTTPS/WebSocket/GraphQL-verkeer met een native Swift-app die u kunt inspecteren, bouwen en vertrouwen.<br>
  Gebouwd voor API-, mobiele, MCP-ondersteunde, AI- en debugging-workflows uit het blockchain-tijdperk naarmate Rockxy evolueert.<br>
  Een lokaal-eerst AGPL-3.0-alternatief voor <a href="#rockxy-vs-alternatives">Proxyman en Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy running on macOS" width="800" />
  </a>
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.31.0** — 2026-07-24

### Added

- Added Rockxy Assistant for investigating selected requests, explaining failures, comparing related traffic, checking authentication signals, and preparing bug reports.
- Added built-in local analysis and optional configured model workflows, with a review step before selected traffic is shared.
- Added secure Babylon pairing and capture intake for supported companion traffic sessions.

### Fixed

- Kept investigations anchored to the exact request being reviewed.
- Prevented provider traffic from being recaptured into the active session.
- Improved streaming responsiveness, request-table stability, and bottom-inspector behavior.

### Changed

- Rebuilt the workspace around native macOS split views for more stable sidebar, request list, Context Dock, and inspector sizing.
- Expanded local model setup, provider configuration, context limits, and response-review controls.
- Refined workspace typography, mode switching, inspector persistence, and narrow-window actions.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Hoogtepunten van de huidige vestiging

- AI Assistant biedt lokale analyse of een Ollama/provider-model na Review Data; de sidebar heeft Focus Sets en Noise Control; de workspace gebruikt native split views; en AI/Web3/x402-inspectie is huidig gedrag.
- Upstream Proxy bevat nu gratis/kern automatische proxyconfiguratie met PAC URL-routering voor `DIRECT`, HTTP- en HTTPS-routes terwijl de bestaande SOCKS5- en authenticatiebeleidsgrenzen behouden blijven.
- Exportworkflows omvatten nu OpenAPI YAML/HTML en Gist-publicatie met geselecteerd verkeer met redactiebewuste payload-opbouw.
- Inspector-tools omvatten nu JSONPath/key/value-filtering en snelle voorbeelden voor geselecteerde payload-tekst zoals JWT's.
- Node.js Developer Setup weerspiegelt nu de geselecteerde client tijdens de validatie en heeft een volledigere localhost-voorbeeldgids.
- Developer Setup Hub omvat nu runtimes, browsers, clients, apparaten, frameworks en omgevingen met doelspecifieke fragmenten, validatiewatchers en eerlijke gidsinhoud.
- De inspectie van binaire WebSocket-frames bevat nu begrensde, on-demand Protobuf wire-format-heuristieken zonder decoder work aan het capture hot path toe te voegen.
- De openbare roadmap richt zich nu op diepere protocolbewuste regels, replay, vergelijking en veiliger delen van geredigeerd bewijs.

## Kenmerken

De tools die u zoekt als browser DevTools zijn niet voldoende. Debugging van kernverkeer voor Mac en iOS werkt – native op macOS, met openbare releases en een local-first-workflow.

### Verkeer vastleggen

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Inspecteer HTTP-, HTTPS-, WebSocket- en GraphQL-verkeer vanaf elke Mac-app, CLI of iOS-apparaat. Browser DevTools eindigen in de browser - Rockxy ziet de rest van je stapel.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Geavanceerd filteren en zoeken

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Beperk duizenden vastgelegde verzoeken in enkele seconden. Combineer methode-, host-, status-, header-, body- en procesfilters, of voer een volledige tekstzoekopdracht uit gedurende de hele sessie.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets en Noise Control

Maak terugkerende onderzoeken tot herbruikbare scopes in de sidebar. Focus Sets combineert app-, domain- en path-includes met domain/path-excludes, blijft bewaard tussen starts en is beschikbaar in elke workspace. Noise Control blijft telemetrie en ander verkeer met lage waarde vastleggen, maar verbergt het in de huidige workspace.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant legt geselecteerd verkeer uit naast de native request-tabel en sidebar" width="820" />

Selecteer een of meer vastgelegde requests en vraag wat er gebeurde, wat mislukte, wat veranderde of wat daarna moet worden gecontroleerd. Rockxy begint met evidence-based analyse op deze Mac; een geconfigureerd Ollama- of provider-model draait pas nadat Review Data de exacte, begrensde en geredigeerde context toont. Antwoorden kunnen de source request onthullen en native follow-up-workflows voorbereiden, maar wijzigen nooit automatisch verkeer en voeren geen acties uit.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Lees de AI Assistant-gids](docs/features/ai-assistant.mdx).

### MCP-server voor externe AI-clients

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Laat Claude Desktop of Cursor uw vastgelegde verkeer lezen via een lokale MCP-server. Vraag "waarom deed deze 500?" in plaats van headers in de chat te plakken. Lokaal, redactiebewust en open source.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Installatiehub voor ontwikkelaars

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Kopieer en plak proxyfragmenten voor Python, Node.js, Go, Rust, cURL, Docker en browsers en klik vervolgens op Test uitvoeren om te bevestigen dat het verkeer daadwerkelijk stroomt.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Certificaatbeheer voor HTTPS-foutopsporing

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Een P-256 ECDSA-root-CA gegenereerd bij de eerste lancering, verzegeld in uw sleutelhanger. Decodeer HTTPS bij de eerste poging; vastgezette hosts passeren automatisch.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL-proxy en HTTPS-decodering

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Kies welke hosts TLS-decodering krijgen. Gedecodeerd verkeer toont echte headers en JSON; al het andere gaat versleuteld door. Met regels voor jokertekens kunt u met één klik per domein zoeken.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Omzeil proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Sla specifieke hosts over, zodat gecertificeerde apps, interne services of luidruchtige telemetrie nooit in de opname terechtkomen. Wildcards houden de lijst kort en uw verzoeklogboek is gericht op datgene waar u echt om geeft.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Blokkeer lijst

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Zorg ervoor dat elke host faalt. Laat advertentienetwerken, trackers van derden of een zwakke afhankelijkheid achterwege en kijk hoe uw app verslechtert als deze weg is, zonder ook maar één regel code te wijzigen.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Kaart Lokaal

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Serveer een opgeslagen bestand of een directorystructuur in plaats van een live antwoord. Verwissel een JSON-payload, speel een momentopname opnieuw af of maak een slechte API van derden vast aan een lokale kopie terwijl u fouten opspoort.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Kaart op afstand

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Herschrijf de bestemming van een vastgelegd verzoek zonder de app-code of /etc/hosts aan te raken. Richt het productieverkeer op de staging, uw ontwikkelserver of de machine van een collega voor een reproduceerbare bugreproductie.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Breekpunten en regels

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Pauzeer een verzoek of antwoord, bewerk de methode, kopteksten, hoofdtekst of status en ga vervolgens verder. De snelste manier om te testen "wat als de API 401 retourneert?" zonder de backend aan te raken.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Wijzig kopteksten

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Voeg headers toe, verwijder of vervang ze op elke host zonder opnieuw te implementeren. Test CORS-, authenticatie- of cachewijzigingen binnen enkele seconden met ingebouwde presets.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Aangepaste verzoek- en antwoordheaders

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Overschrijf headers per host met volledige controle over beide fasen. Injecteer auth-tokens op uitgaande verzoeken, verwijder Set-Cookie op antwoorden of maak een aangepaste User-Agent vast – opgeslagen als benoemde regels die u op elk gewenst moment kunt wijzigen.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Netwerkvoorwaarden

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Geef gas naar 3G, EDGE, LTE, WiFi of een aangepaste vertraging. Je laptop beschikt over glasvezel; uw gebruikers niet: bekijk de UX op 400 ms RTT voordat zij dat doen.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Componeren - Bewerken en opnieuw afspelen

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Herbouw elk vastgelegd HTTP-verzoek (wijzig de methode, URL, headers, queryparameters of hoofdtekst) en verzend het opnieuw zonder Rockxy te verlaten. Geen postbode, slapeloosheid of curl-copy-paste-lus. Herhaal LLM-prompts, vervaag verificatiegrenzen of reproduceer binnen enkele seconden een falende case voor OpenAI-, Anthropic- en Cohere-eindpunten.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Vergelijk

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Stapel twee vastgelegde reacties naast elkaar en ontdek elk veld dat omdraaide: status, headers, JSON-sleutels, bodybytes. Vang stille API-regressies, niet-deterministische LLM-uitvoer en prompt-drift op zonder iets in een diff-tool van derden te verwerken. Side-by-side diff benadrukt wat er is veranderd; diepe JSON-vergelijking negeert de sleutelvolgorde.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Aangepaste Previewer-tabbladen

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Geef verzoek- en antwoordteksten weer zoals u dat wilt. Maak extra tabbladen vast aan de inspecteur voor JSON, GraphQL, JWT, afbeelding of uw eigen indeling – herbruikbaar voor elk vastgelegd verzoek.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sessies en exporteren

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Sla sessies op, import/exporteer HAR voor cross-tool overdracht, kopieer elk verzoek als cURL of JSON. Bewerk autorisatieheaders, cookies en dragertokens voordat u ze deelt. Geef een teamgenoot een werkende bugreproductie zonder geheimen te lekken.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Werkruimten met meerdere tabbladen

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab-workspaces met onafhankelijk gefilterde weergaven van dezelfde live capture" width="820" />

Houd onafhankelijke onderzoeksweergaven van dezelfde live capture naast elkaar. Elk tabblad behoudt eigen filters, sortering, selectie, sidebar-scope en inspectorstatus, terwijl proxy en vastgelegde transacties worden gedeeld.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript-scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS haakt in op verzoeken en antwoorden voor de gevallen die een statische regel niet kan dekken: PII redigeren, tokens ondertekenen, payloads herschrijven. Fouten komen inline naar voren in plaats van het verkeer te corrumperen.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Protocolbewuste Inspectie

Rockxy biedt protocolbewuste inspectie voor AI, Web3 RPC en x402 binnen de normale HTTP-debugworkflow.

### AI Verkeersinspectie

Maak het eenvoudiger om modelverkeer te debuggen binnen de normale vastlegworkflow. Detecteer AI-verzoeken, inspecteer geselecteerde modelaanroepen, diagnosticeer streamingreacties, vergelijk prompt-/uitvoergedrag en begrijp de ketens van toolaanroepen zonder gevoelige payloads in een andere service te plakken.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC-inspectie

Verander netwerkoproepen uit het blockchain-tijdperk in leesbaar bewijs voor foutopsporing. Inspecteer JSON-RPC- en Solana RPC-verkeer, groepeer gerelateerde oproepen in stromen, leg veelvoorkomende RPC-fouten uit en speel geselecteerde verzoeken opnieuw af zonder een portemonnee of blokverkenner te worden.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 Payment Flow Hints

Begrijp betalingsgestuurde HTTP-stromen vanuit de netwerklaag. Markeer betalingsvereiste reacties, volg het pad voor nieuwe pogingen en houd het foutopsporingsbewijs lokaal en redactiebewust.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Toekomstig Werk

De volgende secties beschrijven de openbare richting, niet het huidige gedrag.

### Geredigeerde bewijsbundels `Binnenkort`

Deel de feiten die nodig zijn om een bug te reproduceren zonder geheimen te lekken. Verpak geselecteerd verkeer met protocolsamenvattingen, redactievoorbeelden en broncontext die een teamgenoot kan controleren.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Protocolbewuste regels

Gebruik AI- en Web3-metagegevens waar Rockxy al werkt: filters, badges, optionele kolommen, vergelijking, regels, ontwikkelaarsinstellingen en lokale MCP-samenvattingen.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Team delen en samenwerken `Binnenkort`

Stuur een vastgelegde sessie met één klik naar een teamgenoot. Annoteer falende verzoeken inline, kijk in realtime wie naar wat kijkt en debug HTTPS-verkeer zonder het scherm te delen. Gericht op een toekomstige release.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% native macOS. Geen Elektron. Geen webweergaven. SwiftUI + AppKit + SwiftNIO.

## Snel beginnen

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Bouw en voer uit in Xcode. Het welkomstvenster begeleidt u bij het instellen van de root-CA, de helperinstallatie en de proxy-activering.

**Vereisten:** macOS 14.0+, Xcode 16+, Swift 5.9

Als je Rockxy na de installatie met een lokale MCP-client wilt verbinden, zie dan de [MCP-integratiegids](docs/features/mcp.mdx).

## Rockxy versus alternatieven

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Projectmodel** | AGPL-3.0 open source-project | Eigen commerciële app | Eigen commerciële app |
| **Broncode** | Openbaar, controleerbaar, forkeerbaar | Gesloten bron | Gesloten bron |
| **Bouw vanuit de bron** | Gratis bij Xcode uit deze repository | Niet beschikbaar via openbare bron | Niet beschikbaar via openbare bron |
| **Native macOS-basis** | Swift + SwiftNIO + SwiftUI/AppKit | Native commerciële macOS-app | Platformoverschrijdende commerciële app |
| **Lokale eerste opname** | Lokale proxy, certificaten, helper en vastgelegde gegevens blijven op uw Mac | Desktop proxy-app | Desktop proxy-app |
| **Werkstroom voor het instellen van ontwikkelaars** | Ingebouwde Developer Setup Hub voor runtimes, clients, apparaten, frameworks en omgevingen | Productspecifieke installatierichtlijnen | Productspecifieke installatierichtlijnen |
| **Externe proxy + PAC-routering** | HTTP/HTTPS upstream-proxy, automatische PAC-configuratie en bypass-regels | Volwassen commerciële proxy-tooling | Volwassen commerciële proxy-tooling |
| **MCP/lokale automatiseringsbrug** | Standaard ingebouwde, token-geauthenticeerde redactie | Niet geclaimd in openbare documenten die zijn beoordeeld | Niet geclaimd in openbare documenten die zijn beoordeeld |
| **Open bijdragepad** | Publieke kwesties, discussies, routekaart en PR's | Leveranciergestuurd product | Leveranciergestuurd product |

Op de routekaart: diepere protocolbewuste regels, veiligere geredigeerde bewijsbundels, sterkere replay- en vergelijkingsworkflows, bredere Developer Setup-gidsen en doorlopend onderzoek naar HTTP/2 en HTTP/3.

## Beveiliging

Rockxy onderschept netwerkverkeer – beveiliging is fundamenteel, niet optioneel.

- XPC-helper valideert bellers via **certificaatketenvergelijking**, niet alleen bundel-ID
- Plug-ins komen binnen **gesandboxte JavaScriptCore** met een time-out van 5 seconden, geen toegang tot het bestandssysteem/netwerk
- **Invoervalidatie** op alle grenzen: maximale lichaamsgrootte, URI-limieten, regex DoS-bescherming, preventie van padtraversal
- Referenties **automatisch geredigeerd** in vastgelegde logboeken
- Gevoelige bestanden opgeslagen met **0o600 machtigingen**

Meld kwetsbaarheden via [BEVEILIGING.md](SECURITY.md). Zie de [volledige beveiligingsarchitectuur](docs/development/security.mdx) voor details.

## Routekaart

De publieke roadmap van Rockxy is workflow-georiënteerd en datumvrij. Het richt zich op betrouwbaarheid, native macOS UX, debugging-workflows, protocolondersteuning, verkeerszichtbaarheid uit het AI/Web3-tijdperk, documentatie en onboarding van bijdragers.

- [ROADMAP.md](ROADMAP.md): leiding op hoog niveau in de openbare techniek
- [Rockxy openbare routekaart](https://github.com/orgs/RockxyApp/projects/1): operationele zichtbaarheid voor problemen die via de routekaart worden gevolgd

## Documentatie

Volledige documentatie beschikbaar op de [Rockxy-documenten](docs/index.mdx):

- [Snelstartgids](docs/quickstart.mdx) - binnen enkele minuten aan de slag
- [Installatiehub voor ontwikkelaars](docs/features/developer-setup-hub.mdx) — runtimefragmenten, apparaathandleidingen, validatietests en ondersteuningsmatrix
- [AI Assistant](docs/features/ai-assistant.mdx) — onderzoek geselecteerd verkeer lokaal of met een geconfigureerd model na Review Data
- [Filters en zoeken](docs/core-features/filters-and-search.mdx) — sidebar-scopes, Focus Sets, Noise Control, toolbar-filters en zoeken
- [AI- en Web3-inspectie](docs/features/ai-web3-inspection.mdx) — inspecteer herkend model API-, JSON-RPC- en x402-verkeer
- [MCP-integratie](docs/features/mcp.mdx) — verbind Rockxy met lokale MCP-clients
- [Architectuur](docs/development/architecture.mdx) — proxy-engine, actormodel, gegevensstroom
- [Beveiligingsmodel](docs/development/security.mdx) — vertrouwensgrenzen, XPC-validatie, certificaatbeheer
- [Ontwerpbeslissingen](docs/development/design-decisions.mdx) — waarom SwiftNIO, NSTableView, acteurs
- [Bouwen vanuit de Bron](docs/development/building.mdx) - bouwen, testen, linten en debuggen
- [Codestijl](docs/development/code-style.mdx) — SwiftLint, SwiftFormat en conventies
- [Wijzigingslog](CHANGELOG.md) — niet-uitgebracht werk en getagde releases

## Bijdragen

Bijdragen zijn welkom: code, tests, documenten, bugrapporten en UX-feedback.

Zie **[BIJDRAGEN.md](CONTRIBUTING.md)** voor installatie-instructies, codestijl en de volledige PR-checklist.

Goede eerste nummers zijn gelabeld [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Door een PR te openen, gaat u akkoord met de [CLA](CLA.md).

## Sponsoren & Partners

Rockxy wordt gebouwd en onderhouden door onafhankelijke ontwikkelaars. Sponsoring financiert voortdurende ontwikkeling, beveiligingsaudits en nieuwe functies.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy wordt fiscaal gehost door [Open Source Collective](https://docs.oscollective.org/). Bijdragen en projectuitgaven worden vastgelegd op de [openbare Open Collective-pagina van Rockxy](https://opencollective.com/rockxy), zodat ondersteuners transparant kunnen zien hoe fondsen worden ontvangen en gebruikt.

| Niveau | Bijdrage | Wat het ondersteunt |
|--------|----------|---------------------|
| **Backer** | Vanaf $5/maand | Open-sourceonderhoud, documentatie, tests en releases |
| **Builder** | Vanaf $25/maand | Regressietests, prestatieverbeteringen en dagelijkse debuggingworkflows |
| **Sponsor** | $100/maand | Langdurig onderhoud van een privacygericht hulpmiddel dat gratis blijft voor ontwikkelaars |
| **Sustaining Sponsor** | $500/maand | Gericht onderhoud en productontwikkeling, inclusief releaseautomatisering en protocolondersteuning |

**Vragen over partnerschap** — ontwikkelaarstoolbedrijven, beveiligingsbedrijven en bedrijfsteams die op zoek zijn naar aangepaste integraties of white-label-oplossingen: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Ondersteuning

- [Open Collective](https://opencollective.com/rockxy/donate) — draag bij aan Rockxy via het transparante projectbudget
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — ondersteuning van de ontwikkeling van Rockxy
- [GitHub-problemen](https://github.com/RockxyApp/Rockxy/issues) - bugrapporten en functieverzoeken
- [GitHub-discussies](https://github.com/RockxyApp/Rockxy/discussions) - vragen en community-chat
- **E-mail** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Beveiligingsproblemen** – zie [BEVEILIGING.md](SECURITY.md) voor verantwoorde openbaarmaking

## Licentie

[GNU Affero Algemene Publieke Licentie v3.0](LICENSE) — Copyright 2024–2026 Rockxy-bijdragers.

## Sterrengeschiedenis

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Gemaakt door <a href="https://github.com/LocNguyenHuu">Stefanus</a>. Gebouwd met Swift, SwiftNIO, SwiftUI en AppKit.</sub>
</p>
