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
  <strong>Proxy-ul de depanare cu sursă deschisă, auditabil pentru macOS.</strong>
</p>

<p align="center">
  Interceptați, inspectați și modificați traficul HTTP/HTTPS/WebSocket/GraphQL cu o aplicație Swift nativă în care puteți inspecta, crea și aveți încredere.<br>
  Creat pentru fluxurile de lucru de depanare API, mobile, asistate de MCP, AI și blockchain pe măsură ce Rockxy evoluează.<br>
  O alternativă la AGPL-3.0, pe primul loc local <a href="#rockxy-vs-alternatives">Proxyman și Charles Proxy</a>.
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

**v0.30.0** — 2026-07-16

### Added

- Added a redesigned Focus Navigator with Browse, Focus, and Library modes for moving between all traffic, reusable investigation scopes, saved requests, and pinned requests.
- Added reusable Focus Sets, traffic signals, and noise controls for isolating errors, slow requests, WebSocket or GraphQL activity, rule hits, selected apps, domains, and paths without deleting captured traffic.
- Added a Context Dock that keeps request and response details available while navigating the traffic list.
- Added encrypted nearby iPhone session transfers into a dedicated iOS workspace so current Mac traffic remains available.

### Fixed

- Fixed Quick Tools customization so every part of each dropdown field opens its menu reliably.
- Kept selection state aligned when focus, signal, noise, or filter changes hide previously selected requests.

### Changed

- Refined workspace navigation, inspector layout, selection behavior, and persisted layout preferences for a clearer debugging workflow.
- Kept nearby iPhone transfer discovery available while Rockxy is running, including when macOS restores the app without a main window.
- Improved captured-value filtering so apps, domains, and paths are easier to reuse in focused investigations.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Repere actuale ale filialei

- Upstream Proxy include acum Configurarea automată proxy gratuită/core cu rutare URL PAC pentru `DIRECT`, HTTP și HTTPS, păstrând în același timp limitele existente SOCKS5 și politicile de autentificare.
- Fluxurile de lucru de export acoperă acum OpenAPI YAML/HTML și publicarea Gist cu trafic selectat cu crearea de încărcătură utilă care ține cont de redactare.
- Instrumentele Inspector includ acum filtrarea JSONPath/cheie/valoare și previzualizări rapide pentru textul de încărcare utilă selectat, cum ar fi JWT.
- Configurarea dezvoltatorului Node.js reflectă acum clientul selectat în timpul validării și are un ghid de probă localhost mai complet.
- Centrul de configurare pentru dezvoltatori acoperă acum timpii de execuție, browsere, clienți, dispozitive, cadre și medii cu fragmente specifice țintei, observatori de validare și conținut de ghid sincer.
- Lucrările cu WebSocket Protobuf continuă ca parte a direcției mai bogate de inspecție a protocolului Rockxy.
- Planificarea foii de parcurs public include acum depanarea care știe protocolul pentru traficul AI, fluxurile Web3/RPC, fluxurile de plată în stil x402 și partajarea mai sigură a dovezilor redactate.

## Caracteristici

Instrumentele la care apelați atunci când DevTools din browser nu sunt suficiente. Depanarea traficului de bază pentru Mac și iOS funcționează - nativ pe macOS, cu versiuni publice și un flux de lucru mai întâi local.

### Captarea traficului

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Inspectați traficul HTTP, HTTPS, WebSocket și GraphQL de pe orice aplicație Mac, CLI sau dispozitiv iOS. Browser DevTools se termină la browser - Rockxy vede restul stivei dvs.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Filtru și căutare avansate

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Restrângeți mii de solicitări capturate în câteva secunde. Combinați filtrele de metodă, gazdă, stare, antet, corp și proces - sau executați o căutare cu text integral în întreaga sesiune.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Server MCP pentru asistenți AI

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Lăsați Claude Desktop sau Cursor să vă citească traficul capturat printr-un server MCP local. Întrebați „de ce au făcut acest 500?” în loc să lipiți anteturi în chat. Local, conștient de redactare și sursă deschisă.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Hub de configurare pentru dezvoltatori

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Copiați și inserați fragmente proxy pentru Python, Node.js, Go, Rust, cURL, Docker și browsere, apoi faceți clic pe Executare test pentru a confirma că traficul circulă efectiv.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Managementul certificatelor pentru depanarea HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Un CA root P-256 ECDSA generat la prima lansare, sigilat în brelocul dumneavoastră. Decriptați HTTPS la prima încercare; gazdele fixate trec automat.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### Proxy SSL și decriptare HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Alegeți ce gazde primesc decriptare TLS. Traficul decriptat arată anteturi reale și JSON; totul trece prin criptare. Regulile wildcard vă permit să vă delimitați în funcție de domeniu cu un singur clic.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Ocoliți proxy-ul

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Omiteți anumite gazde, astfel încât aplicațiile fixate cu certificat, serviciile interne sau telemetria zgomotoasă să nu intre niciodată în captură. Wildcard-urile mențin lista scurtă, iar jurnalul de solicitări se concentrează pe ceea ce vă interesează de fapt.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Lista blocate

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Faceți orice gazdă să eșueze. Eliminați rețelele publicitare, instrumentele de urmărire terță parte sau o dependență nesigură pentru a vedea cum se degradează aplicația dvs. atunci când dispare, fără a modifica o linie de cod.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Hartă locală

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Serviți un fișier salvat sau un arbore de directoare în locul unui răspuns live. Schimbați o sarcină utilă JSON, redați un instantaneu sau fixați un API terță parte neconformat la o copie locală în timp ce depanați.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Telecomanda pentru hartă

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Rescrieți destinația unei solicitări capturate fără a atinge codul aplicației sau /etc/hosts. Indicați traficul de producție la punere în scenă, serverul dvs. de dezvoltare sau mașina unui coleg pentru o reproducere reproductibilă a erorilor.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Puncte de întrerupere și reguli

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Întrerupeți o solicitare sau un răspuns, editați metoda, anteturile, corpul sau starea, apoi continuați. Cea mai rapidă modalitate de a testa „ce se întâmplă dacă API-ul returnează 401?” fără a atinge backend-ul.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Modificați anteturile

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Adăugați, eliminați sau înlocuiți anteturi pe orice gazdă fără redistribuire. Testați modificările CORS, auth sau cache în câteva secunde cu presetări încorporate.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Anteturi personalizate de solicitare și răspuns

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Ignorați anteturile pentru fiecare gazdă cu control deplin asupra ambelor faze. Injectați jetoane de autentificare la cererile trimise, eliminați Set-Cookie pe răspunsuri sau fixați un User-Agent personalizat - salvat ca reguli numite pe care le puteți comuta oricând.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Condiții de rețea

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Accelerează la 3G, EDGE, LTE, WiFi sau o întârziere personalizată. Laptopul tău este pe fibră; utilizatorii dvs. nu sunt - vedeți UX la 400 ms RTT înainte de a o face.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compune — Editează și reluează

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Reconstruiți orice solicitare HTTP capturată - schimbați metoda, adresa URL, anteturile, parametrii de interogare sau corpul - și retrimiteți fără a părăsi Rockxy. Fără poștaș, insomnie sau buclă curl copy-paste. Repetați solicitările LLM, fuzz limitele de auth sau reproduceți un caz eșuat pentru punctele finale OpenAI, Anthropic și Cohere în câteva secunde.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Comparați

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Stivuiți două răspunsuri capturate unul lângă altul și identificați fiecare câmp care s-a răsturnat — stare, anteturi, chei JSON, octeți de corp. Obțineți regresii API silențioase, ieșiri LLM nedeterministe și deriva promptă fără a introduce nimic într-un instrument de diferențiere terță parte. Diferența side-by-side evidențiază ceea ce s-a schimbat; compararea JSON profundă ignoră ordonarea cheilor.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### File personalizate de previzualizare

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Redați corpurile de solicitare și răspuns așa cum doriți. Fixați file suplimentare la inspector pentru JSON, GraphQL, JWT, imagine sau propriul dvs. format - reutilizabile pentru fiecare solicitare capturată.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sesiuni și export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Salvați sesiuni, importați/exportați HAR pentru transferul între instrumente, copiați orice solicitare ca cURL sau JSON. Redactați anteturile de autorizare, cookie-urile și jetoanele purtător înainte de a le partaja - înmânați unui coechipier o reproșare a erorilor de lucru fără a scurge secrete.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Spații de lucru cu mai multe file

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

Rulați sesiuni de captură independente una lângă alta — o filă pentru punere în scenă, una pentru producție, una pentru construirea dispozitivului iOS. Fiecare filă are propriile sale filtre, selecție și starea inspectorului, astfel încât schimbarea contextului nu costă nimic.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Scripturi JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS agăță solicitări și răspunsuri pentru cazurile pe care o regulă statică nu le poate acoperi — redactați PII, semnați jetoane, rescrie încărcături utile. Erorile apar în linie în loc să corupă traficul.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Mai multe caracteristici în curând

Funcțiile viitoare sunt urmărite public și sunt livrate numai atunci când implementarea, testele, comportamentul de confidențialitate și documentația sunt gata.

### Inspecția de trafic AI `În curând`

Faceți traficul modelului mai ușor de depanat în cadrul fluxului de lucru normal de captare. Detectați solicitările AI, inspectați apelurile model selectate, diagnosticați răspunsurile în flux, comparați comportamentul prompt/ieșire și înțelegeți lanțurile de apeluri de instrumente fără a lipi încărcături utile sensibile într-un alt serviciu.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Inspecție Web3/RPC `În curând`

Transformați apelurile de rețea din era blockchain în dovezi de depanare lizibile. Inspectați traficul JSON-RPC și Solana RPC, grupați apelurile asociate în fluxuri, explicați erorile RPC obișnuite și reluați cererile selectate fără a deveni un portofel sau un explorator de blocuri.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### Depanarea fluxului de plăți x402 `În curând`

Înțelegeți fluxurile HTTP bazate pe plăți din stratul de rețea. Evidențiați răspunsurile necesare pentru plată, urmați calea de reîncercare și păstrați dovezile de depanare locale și conștiente de redactare.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### Pachete de dovezi redacționate `În curând`

Împărtășiți faptele necesare pentru a reproduce o eroare fără a scurge secrete. Împachetați traficul selectat cu rezumate de protocol, previzualizări de redactare și context susținut de sursă pe care un coechipier poate audita.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Filtre și reguli care țin cont de protocol `În curând`

Folosiți metadatele AI și Web3 acolo unde funcționează deja Rockxy: filtre, insigne, coloane opționale, comparații, reguli, Configurare pentru dezvoltatori și rezumate MCP locale.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Partajarea în echipă și colaborare `În curând`

Trimiteți o sesiune capturată unui coechipier cu un singur clic. Adnotați cererile eșuate în linie, vedeți cine se uită la ce în timp real și depanați traficul HTTPS prin pereche fără partajarea ecranului. Vizat pentru o lansare viitoare.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% macOS nativ. Fara electron. Fără vizualizări web. SwiftUI + AppKit + SwiftNIO.

## Pornire rapidă

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Construiți și rulați în Xcode. Fereastra Bun venit vă ghidează prin configurarea CA root, instalarea helperului și activarea proxy-ului.

**Cerințe:** macOS 14.0+, Xcode 16+, Swift 5.9

Dacă doriți să conectați Rockxy la un client MCP local după instalare, consultați [Ghid de integrare MCP](docs/features/mcp.mdx).

## Rockxy vs Alternative

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Model de proiect** | Proiect open-source AGPL-3.0 | Aplicație comercială proprietară | Aplicație comercială proprietară |
| **Cod sursă** | Public, auditabil, forkable | Sursă închisă | Sursă închisă |
| **Construiți din sursă** | Gratuit cu Xcode din acest depozit | Nu este disponibil din sursa publică | Nu este disponibil din sursa publică |
| **Fundație nativă macOS** | Swift + SwiftNIO + SwiftUI/AppKit | Aplicație comercială nativă macOS | Aplicație comercială multiplatformă |
| **Captură locală mai întâi** | Proxy-ul local, certificatele, ajutorul și datele de captare rămân pe Mac | Aplicație proxy desktop | Aplicație proxy desktop |
| **Flux de lucru pentru configurarea dezvoltatorului** | Hub de configurare pentru dezvoltatori încorporat pentru runtime, clienți, dispozitive, cadre și medii | Ghid de configurare specific produsului | Ghid de configurare specific produsului |
| **Proxy extern + rutare PAC** | Proxy în amonte HTTP/HTTPS, auto-configurare PAC și reguli de ocolire | Instrumente proxy comerciale mature | Instrumente proxy comerciale mature |
| **MCP/punte de automatizare locală** | Încorporat, autentificat prin simbol, redactare în mod implicit | Nu este revendicat în documentele publice revizuite | Nu este revendicat în documentele publice revizuite |
| **Deschideți calea de contribuție** | Probleme publice, discuții, foaie de parcurs și PR-uri | Produs controlat de furnizor | Produs controlat de furnizor |

Pe foaia de parcurs: fluxuri de lucru mai profunde de redare/difer/reguli/scriptare, inspecție îmbunătățită pentru WebSocket și GraphQL, depanare AI și Web3/RPC conștientă de protocol, vizibilitate fluxului de plăți în stil x402 și explorarea gRPC/Protobuf plus suport HTTP/2 și HTTP/3.

## Securitate

Rockxy interceptează traficul de rețea — securitatea este fundamentală, nu opțională.

- Asistentul XPC validează apelanții prin **comparație certificat-lanț**, nu doar ID-ul pachetului
- Pluginurile rulează **JavaScriptCore cu nisip** cu timeout de 5 secunde, fără acces la sistem de fișiere/rețea
- **Validarea intrărilor** pe toate granițele - limitele dimensiunii corpului, limitele URI, protecția DoS regex, prevenirea traversării căilor
- Acreditări **redactat automat** în jurnalele capturate
- Fișierele sensibile stocate cu **0o600 permisiuni**

Raportați vulnerabilități prin [SECURITY.md](SECURITY.md). Vezi [arhitectură de securitate completă](docs/development/security.mdx) pentru detalii.

## Foaia de parcurs

Foaia de parcurs publică a Rockxy este orientată spre fluxul de lucru și fără date. Se concentrează pe fiabilitate, macOS UX nativ, fluxuri de lucru de depanare, suport pentru protocol, vizibilitatea traficului din era AI/Web3, documentație și integrarea colaboratorilor.

- [ROADMAP.md](ROADMAP.md): direcție de inginerie publică de nivel înalt
- [Foaia de parcurs publică Rockxy](https://github.com/orgs/RockxyApp/projects/1): vizibilitate operațională pentru problemele urmărite pe foaia de parcurs

## Documentare

Documentația completă disponibilă la [Rockxy Docs](docs/index.mdx):

- [Ghid de pornire rapidă](docs/quickstart.mdx) — pune-te pe picioare în câteva minute
- [Hub de configurare pentru dezvoltatori](docs/features/developer-setup-hub.mdx) — fragmente de rulare, ghiduri pentru dispozitive, sonde de validare și matrice de asistență
- [Integrare MCP](docs/features/mcp.mdx) — conectați Rockxy la clienții MCP locali
- [Arhitectura](docs/development/architecture.mdx) — motor proxy, model actor, flux de date
- [Model de securitate](docs/development/security.mdx) — limitele de încredere, validarea XPC, managementul certificatelor
- [Decizii de proiectare](docs/development/design-decisions.mdx) — de ce SwiftNIO, NSTableView, actori
- [Construire din sursă](docs/development/building.mdx) — construiți, testați, scame și depanați
- [Stil cod](docs/development/code-style.mdx) — SwiftLint, SwiftFormat și convenții
- [Jurnalul modificărilor](CHANGELOG.md) — lucrări nelansate și versiuni etichetate

## Contribuind

Contribuții sunt binevenite - cod, teste, documente, rapoarte de erori și feedback UX.

Vezi **[CONTRIBUTING.md](CONTRIBUTING.md)** pentru instrucțiuni de configurare, stilul codului și lista completă de verificare PR.

Primele numere bune sunt etichetate [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Prin deschiderea unui PR, sunteți de acord cu [CLA](CLA.md).

## Sponsori și parteneri

Rockxy este construit și întreținut de dezvoltatori independenți. Sponsorizările finanțează dezvoltarea continuă, audituri de securitate și funcții noi.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy este găzduit fiscal de [Open Source Collective](https://docs.oscollective.org/). Contribuțiile și cheltuielile proiectului sunt înregistrate pe [pagina publică Open Collective a Rockxy](https://opencollective.com/rockxy), oferind o imagine transparentă asupra modului în care fondurile sunt primite și utilizate.

| Nivel | Contribuție | Ce susține |
|-------|-------------|------------|
| **Backer** | De la $5/lună | Mentenanță open source, documentație, testare și lansări |
| **Builder** | De la $25/lună | Testare de regresie, îmbunătățiri de performanță și fluxuri zilnice de depanare |
| **Sponsor** | $100/lună | Mentenanța pe termen lung a unui instrument orientat spre confidențialitate și gratuit pentru dezvoltatori |
| **Sustaining Sponsor** | $500/lună | Mentenanță și dezvoltare concentrată a produsului, inclusiv automatizarea lansărilor și suport pentru protocoale |

**Cereri de parteneriat** — companii de instrumente de dezvoltare, firme de securitate și echipe de întreprinderi care caută integrări personalizate sau soluții cu etichetă albă: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Sprijin

- [Open Collective](https://opencollective.com/rockxy/donate) — contribuie la Rockxy prin bugetul transparent al proiectului
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — sprijină dezvoltarea lui Rockxy
- [Probleme GitHub](https://github.com/RockxyApp/Rockxy/issues) — rapoarte de erori și solicitări de caracteristici
- [Discuții GitHub](https://github.com/RockxyApp/Rockxy/discussions) — întrebări și chat comunitar
- **E-mail** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Probleme de securitate** — vezi [SECURITY.md](SECURITY.md) pentru dezvăluirea responsabilă

## Licență

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## Istoria stelelor

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Realizat de <a href="https://github.com/LocNguyenHuu">Ştefan</a>. Construit cu Swift, SwiftNIO, SwiftUI și AppKit.</sub>
</p>
