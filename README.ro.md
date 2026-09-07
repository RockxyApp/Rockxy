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
  O alternativă local-first, AGPL-3.0 la <a href="#rockxy-vs-alternative">Proxyman și Charles Proxy</a>.
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
  <a href="https://trendshift.io/repositories/26380?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-26380" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/26380/daily?language=Swift" alt="RockxyApp/Rockxy | Trendshift" width="250" height="55" /></a>
</p>

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

## Repere actuale ale filialei

- AI Assistant investighează acum unul sau mai multe requesturi selectate cu analiză locală încorporată sau un model Ollama/provider configurat opțional, cu confirmare Review Data explicită, redactare limitată, răspunsuri streaming, evidence reveal și handoff-uri inițiate de utilizator.
- Sidebarul nativ include acum Focus Sets reutilizabile pentru scope-uri app/domain/path plus Noise Control la nivel de workspace care ascunde domain-urile sau path-urile care se potrivesc fără a opri capture.
- Workspace-ul principal folosește acum split view native verticale și orizontale pentru Context Dock și inspectorul de jos, păstrând separatoare de înălțime completă, separatoare toolbar/footer coordonate și redimensionare automată a layoutului.
- Upstream Proxy include acum Configurarea automată proxy gratuită/core cu rutare URL PAC pentru `DIRECT`, HTTP și HTTPS, păstrând în același timp limitele existente SOCKS5 și politicile de autentificare.
- Fluxurile de lucru de export acoperă acum OpenAPI YAML/HTML și publicarea Gist cu trafic selectat cu crearea de încărcătură utilă care ține cont de redactare.
- Instrumentele Inspector includ acum filtrarea JSONPath/cheie/valoare și previzualizări rapide pentru textul de încărcare utilă selectat, cum ar fi JWT.
- Inspecția traficului AI și Web3 adaugă acum etichete de protocol, file de inspector și rezumate de depanare pentru apeluri de model recunoscute, trafic JSON-RPC și indicii de plată în stil x402.
- Configurarea dezvoltatorului Node.js reflectă acum clientul selectat în timpul validării și are un ghid de probă localhost mai complet.
- Centrul de configurare pentru dezvoltatori acoperă acum timpii de execuție, browsere, clienți, dispozitive, cadre și medii cu fragmente specifice țintei, observatori de validare și conținut de ghid sincer.
- Inspecția frame-urilor binare WebSocket include acum heuristic Protobuf wire-format limitate și la cerere, fără a adăuga decoder work în capture hot path.
- Roadmap-ul public se concentrează acum pe reguli protocol-aware mai profunde, replay, comparison și partajarea mai sigură a dovezilor redactate.

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

### Focus Sets și Noise Control

Transformați investigațiile recurente în scope-uri reutilizabile în sidebar. Focus Sets combină includeri pentru app, domain și path cu excluderi domain/path, persistă între lansări și este disponibil în fiecare workspace. Noise Control continuă să captureze telemetria și traficul cu valoare redusă, dar le ascunde în workspace-ul curent.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant explică traficul selectat lângă tabelul de requesturi și sidebarul native" width="820" />

Selectați unul sau mai multe requesturi capturate și întrebați ce s-a întâmplat, ce a eșuat, ce s-a schimbat sau ce trebuie verificat în continuare. Rockxy începe cu analiză bazată pe dovezi pe acest Mac; un model Ollama sau provider configurat rulează numai după ce Review Data arată contextul exact, limitat și redactat. Răspunsurile pot dezvălui requestul sursă și pregăti workflow-uri native de follow-up, dar nu modifică traficul și nu execută acțiuni automat.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Citiți ghidul AI Assistant](docs/features/ai-assistant.mdx).

### Server MCP pentru clienți AI externi

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Lăsați Claude Desktop sau Cursor să vă inspecteze traficul capturat prin zece instrumente doar-citire din serverul MCP local al Rockxy. Întrebați „de ce a returnat acest 500?” în loc să lipiți anteturi în chat. Implementarea este open source, autentificată prin token și păstrează redactarea datelor sensibile activată în mod implicit.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Promovați orice antet de cerere sau răspuns la o coloană de primă clasă în tabelul de trafic. Păstrați sursele de cerere și răspuns separate, salvați anteturile care vă interesează, apoi parcurgeți request ID-uri, trace ID-uri, starea cache-ului sau metadate personalizate fără a deschide fiecare inspector.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Condiții de rețea

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Accelerează la 3G, EDGE, LTE, WiFi sau o întârziere personalizată. Laptopul tău este pe fibră; utilizatorii dvs. nu sunt - vedeți UX la 400 ms RTT înainte de a o face.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compune — Editează și reluează

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Reconstruiți orice solicitare HTTP capturată - schimbați metoda, adresa URL, anteturile, parametrii de interogare sau corpul - și retrimiteți fără a părăsi Rockxy. Fără bucla de copy-paste către Postman, Insomnia sau curl. Repetați solicitările LLM, fuzz limitele de auth sau reproduceți un caz eșuat pentru punctele finale OpenAI, Anthropic și Cohere în câteva secunde.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Comparați

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Stivuiți două tranzacții capturate sau payload-uri lipite unul lângă altul și identificați fiecare câmp care s-a schimbat — stare, anteturi, chei JSON sau octeți de corp. Obțineți regresii API silențioase, ieșiri LLM nedeterministe și prompt drift fără a introduce nimic într-un instrument de diferențiere terță parte.

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Spații de lucru multi-tab Rockxy cu vizualizări filtrate independent ale aceleiași capturi live" width="820" />

Păstrați alăturate vizualizări independente de investigație ale aceleiași capturi live — o filă pentru traficul de staging, una pentru producție și una pentru un flux de dispozitiv iOS. Fiecare filă își păstrează propriile filtre, sortare, selecție, scope-ul sidebarului și starea inspectorului, partajând proxy-ul și tranzacțiile capturate.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Scripturi JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS agăță solicitări și răspunsuri pentru cazurile pe care o regulă statică nu le poate acoperi — redactați PII, semnați jetoane, rescrie încărcături utile. Erorile apar în linie în loc să corupă traficul.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Inspecție Conștientă de Protocol

Rockxy oferă inspecție conștientă de protocol pentru AI, Web3 RPC și x402 în workflow-ul normal de depanare HTTP.

### Inspecția de trafic AI

Rockxy detectează solicitările AI recunoscute în cadrul fluxului de lucru normal de captare. Inspectați apelurile de model selectate, starea de streaming, câmpurile usage când sunt prezente, avertismentele, retrieval hints și rezumatele tool-call fără a lipi payload-uri sensibile într-un alt serviciu.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Inspecție Web3/RPC

Rockxy transformă apelurile de rețea din era blockchain în dovezi de depanare lizibile. Inspectați traficul HTTP JSON-RPC în stil EVM și Solana cu provider host, request ID, method, batch summary, error, chain, transaction, payload și debug-intent, fără a transforma Rockxy într-un portofel sau explorator de blocuri.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### Indicii pentru fluxul de plăți x402

Rockxy evidențiază indiciile payment-required și orientate spre retry, astfel încât fluxurile HTTP payment-gated să fie inteligibile de la nivelul de rețea, în timp ce dovezile de depanare rămân locale și redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Lucrări Viitoare

Secțiunile următoare descriu direcția publică, nu comportamentul actual.

### Reguli care țin cont de protocol

Rockxy poate deja eticheta și inspecta traficul AI și Web3 astăzi. Potrivirea mai profundă a regulilor după model, tool call, metodă JSON-RPC, chain, transaction hash sau batch subcall rămâne lucru viitor; instrumentele actuale de modificare a traficului încă potrivesc URL, metoda HTTP și anteturile.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Pachete de dovezi redacționate `În curând`

Împărtășiți faptele necesare pentru a reproduce o eroare fără a scurge secrete. Împachetați traficul selectat cu rezumate de protocol, previzualizări de redactare și context susținut de sursă pe care un coechipier poate audita.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Partajarea în echipă și colaborare `În curând`

Trimiteți o sesiune capturată unui coechipier cu un singur clic. Adnotați cererile eșuate în linie, vedeți cine se uită la ce în timp real și depanați traficul HTTPS prin pereche fără partajarea ecranului. Vizat pentru o lansare viitoare.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Shell de aplicație macOS nativ — fără Electron. SwiftUI + AppKit + SwiftNIO, cu WebKit folosit doar pentru previzualizarea corpului HTML.

## Pornire rapidă

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Construiți și rulați în Xcode. Fereastra Bun venit vă ghidează prin configurarea CA root, instalarea helperului și activarea proxy-ului.

**Cerințe:** macOS 14.0+, Xcode 16+, Swift 5.9

Dacă doriți să conectați Rockxy la un client MCP local după instalare, consultați [Ghid de integrare MCP](docs/features/mcp.mdx).

## Rockxy vs. Alternative

Matricea principală acoperă proxy-uri de depanare web de uz general. Testare de securitate
suite și browser/interceptoare orientate spre API, cu suprapunere substanțială a fluxului de lucru
sunt enumerate separat, astfel încât, spre deosebire de produsele, nu sunt prezentate ca interschimbabile.
Analizatoarele de pachete și clienții numai pentru API sunt în afara acestei comparații.

### Proxy direct de depanare web

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Forma produsului** | Proxy nativ de depanare macOS | Aplicație nativă macOS; Ediții Windows/Linux bazate pe Electron | Proxy de depanare desktop multiplatformă | CLI/TUI multiplatformă și set de instrumente proxy pentru interfața de utilizare web | Proxy desktop Electron multiplatformă și client HTTP | Proxy de depanare desktop multiplatformă |
| **Sursă și model de construcție** | Sursa comunității publice sub AGPL-3.0-or-later; construibil cu Xcode. DMG oficial conține și componente non-publice din aval | Sursă închisă; nicio sursă de aplicare publică identificată în materialele oficiale analizate | Sursă închisă; nicio sursă de aplicare publică identificată în materialele oficiale analizate | Sursă publică cu licență MIT; construibil din sursa | Sursă desktop publică AGPL; construibil de la sursă; binarele publicate au opțiuni suplimentare de licențiere | Sursă închisă; distribuit ca cod obiect sub Fiddler Everywhere EULA |
| **Capturare și configurare** | Proxy de sistem local cu configurare ghidată pentru aplicații Mac, runtime, dispozitive iOS și Simulator | Configurare automată pentru aplicații Mac, timpi de execuție și dispozitive mobile | Proxy local cu ghiduri de configurare pentru macOS, iOS și multiplatforme | Modul obișnuit, cu proces local, WireGuard, invers, transparent și alte moduri de captură | Interceptare manuală și direcționată proxy pentru browsere, timpi de execuție, containere și dispozitive mobile | Moduri de captare sistem, rețea, browser, terminal, explicit și la distanță |
| **Modifică și batjocorește** | Puncte de întrerupere, Map Local/Remote, reguli de antet, reguli de blocare și latență | Puncte de întrerupere, Map Local/Remote, liste de blocare, condiții de rețea și reguli JavaScript | Puncte de întrerupere, rescriere, Map Local/Remote, blocare și accelerare | Map Local/Remote, modificarea corpului/antetului, blocarea și reluarea serverului | Puncte de întrerupere plus rescriere bazată pe reguli, redirecționare, simulare și injectare de erori; unele automatizări sunt limitate în plan | Reguli, puncte de întrerupere, redirecționări, modificare a răspunsului și batjocură |
| **Reda și compara** | Compune/reluare plus cerere locală alăturată, antet și comparație de corp | Compune, repetă și diferență | Repetați și editați solicitările | Reluare pe partea client și pe partea server | Client HTTP încorporat pentru compunerea și trimiterea cererilor | API Composer, reluare a traficului și comparare a traficului documentate ca beta |
| **WebSocket fluxuri de lucru** | Inspecție text/cadru binar cu euristică Protobuf delimitată | inspecție WS/WSS; scripturile pot modifica URL-ul/anteturile de handshake, nu mesajele | Suportul WebSocket este documentat în istoricul versiunilor oficiale | WebSocket interceptare și scripting; Reluarea WebSocket nu este acceptată | Inspecție WebSocket plus reguli specifice WebSocket | WebSocket captare și inspecție |
| **Scriptare și extensibilitate** | Cârlige JavaScriptCore cu nisip cu un API delimitat și timeout de execuție | JavaScript scriptare cerere/răspuns | Rescrierea regulilor și o interfață web de control; nicio caracteristică generală de scripting JavaScript documentată | Python suplimente și automatizare linie de comandă | Automatizare bazată pe reguli plus biblioteci surse publice și proxy | Automatizare bazată pe reguli; nicio caracteristică generală de scriptare primară nu este documentată |
| **Dirutare în amonte** | [HTTP/HTTPS proxy în amonte și rutare URL PAC](docs/features/upstream-proxy.mdx); Politica comunitară dezactivează autentificarea proxy și SOCKS5 și limitează regulile de ocolire la trei | Rutare externă HTTP/HTTPS/SOCKS și PAC cu reguli de ocolire | Proxy-uri externe HTTP/HTTPS/SOCKS cu reguli de autentificare și ocolire | HTTP/HTTPS modul amonte plus modurile de ascultare inversă și SOCKS | Setări de sistem, HTTP, HTTPS și SOCKS în amonte; se pot aplica limite ale planului | Înlănțuire automată la proxy-urile de sistem plus capturarea proxy inversă |
| **AI și MCP** | [Asistent AI în aplicație](docs/features/ai-assistant.mdx) și [MCP local încorporat](docs/features/mcp.mdx) cu ​​10 instrumente numai pentru citire, autentificare cu simbol și redactare activate în mod implicit | MCP încorporat pentru clienții AI externi, inclusiv citirile de trafic și controalele aplicației/regulilor | Nedocumentat | Nedocumentat | Un pod MCP local este prezent în sursa oficială curentă; nici un asistent în aplicație documentat | MCP încorporat plus un asistent de depanare de nivel profesional a cărui documentație actuală necesită ca detaliile de trafic capturate să fie lipite în chat |

### Instrumente de interceptare adiacente

Aceste produse se suprapun în mod semnificativ cu Rockxy, dar conduc cu teste de securitate,
regulile browserului sau fluxurile de lucru pentru client API, mai degrabă decât același scop general
focus nativ de depanare-proxy.

| **Produs** | **De ce este adiacent** | **Sursă și model de construcție** | **Suprapunere relevantă** | **AI și MCP** |
|---|---|---|---|---|
| **Burp Suite** | Suită de testare a securității web cu un proxy de interceptare | Aplicație cu sursă închisă; EULA afirmă că utilizatorii nu au niciun drept la sursa aplicației. Extensiile pot folosi licențe separate | Interceptare proxy și potrivire/înlocuire, Repeater, WebSocket, proxy în amonte/SOCKS și un ecosistem extins de extindere | Burp AI este disponibil în Repeater; PortSwigger menține, de asemenea, o extensie publică de server MCP pentru clienți externi AI |
| **ZAP** | Scaner de securitate și interceptare proxy | Sursa publică Apache-2.0; construibil din sursa | Interceptare/editare, retrimitere manuală, puncte de întrerupere și scripturi WebSocket, scripting în mai multe limbi, suplimente și automatizare | Integrare oficială MCP și suplimente opționale de asistență LLM |
| **Requestly HTTP Interceptor** | Extensie de browser și instrument de interceptare/modificare desktop multiplatformă | Sursă publică AGPL desktop-interceptor; clientul separat Requestly API este proprietar conform notificării sale publice privind depozitul comunității | Captură la nivelul întregului sistem/browser, redirecționare, Map Local/Remote, modificare antet/corp, transformări JavaScript, simulare de întârziere/erori | Un server oficial separat MCP gestionează regulile și grupurile; nu este documentat niciun asistent de analiză a traficului în aplicație |

Disponibilitatea caracteristicilor poate varia în funcție de ediție, plan, platformă sau supliment.
„Nedocumentat” înseamnă că o capacitate nu a fost găsită în prima parte oficială
surse revizuite pe 2026-08-22; nu este dovada că capacitatea este absentă.
Declarațiile despre produse și caracteristici de mai sus au fost verificate cu documentația furnizorului,
arhivele sursă întreținute de furnizor sau termenii licenței furnizorului la acea dată și
se poate schimba. Numele produselor și mărcile comerciale aparțin proprietarilor respectivi;
Rockxy nu este afiliat sau susținut de ei. Corecțiile sunt binevenite
prin intermediul instrumentului de urmărire a problemelor Rockxy.

Pe foaia de parcurs: reguli mai profunde care cunoaște protocolul, pachete de dovezi redactate mai sigure, fluxuri de lucru mai puternice de reluare și comparare, îndrumări mai ample de configurare pentru dezvoltatori și cercetare continuă HTTP/2 și HTTP/3.

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
- [AI Assistant](docs/features/ai-assistant.mdx) — investigați traficul selectat local sau cu un model configurat după Review Data
- [Filtre și căutare](docs/core-features/filters-and-search.mdx) — scope-uri sidebar, Focus Sets, Noise Control, filtre toolbar și căutare
- [Inspecție AI și Web3](docs/features/ai-web3-inspection.mdx) — inspectați traficul model API, JSON-RPC și x402 recunoscut
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

Rockxy este întreținut în mod independent. Sponsorizările ajută la finanțarea dezvoltării continue, a infrastructurii de lansare, a documentației și a activității de securitate.

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

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Realizat de <a href="https://github.com/LocNguyenHuu">Stephen</a>. Construit cu Swift, SwiftNIO, SwiftUI și AppKit.</sub>
</p>
