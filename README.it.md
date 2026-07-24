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
  <strong>Il proxy di debug open source e verificabile per macOS.</strong>
</p>

<p align="center">
  Intercetta, ispeziona e modifica il traffico HTTP/HTTPS/WebSocket/GraphQL con un'app Swift nativa di cui puoi ispezionare, creare e fidarti.<br>
  Costruito per flussi di lavoro di debug API, mobili, assistiti da MCP, AI e dell'era blockchain man mano che Rockxy si evolve.<br>
  Un'alternativa locale, AGPL-3.0 a <a href="#rockxy-vs-alternatives">Procuratore e Charles Procuratore</a>.
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

## Punti salienti del ramo attuale

- AI Assistant offre analisi locale o con Ollama/provider dopo Review Data; la sidebar include Focus Sets e Noise Control; il workspace usa split view native; e l'ispezione AI/Web3/x402 è ora comportamento corrente.
- Il proxy upstream ora include la configurazione proxy automatica gratuita/core con routing URL PAC per `DIRECT`, HTTP e HTTPS preservando SOCKS5 esistente e i limiti dei criteri di autenticazione.
- I flussi di lavoro di esportazione ora coprono OpenAPI YAML/HTML e la pubblicazione di Gist con traffico selezionato con creazione di payload sensibile alla redazione.
- Gli strumenti di ispezione ora includono il filtro JSONPath/chiave/valore e anteprime rapide per il testo del payload selezionato come i JWT.
- La configurazione per sviluppatori di Node.js ora rispecchia il client selezionato durante la convalida e dispone di una guida di esempio localhost più completa.
- L'hub di configurazione dello sviluppatore ora copre runtime, browser, client, dispositivi, framework e ambienti con snippet specifici del target, osservatori di convalida e contenuti di guida onesti.
- L'ispezione dei frame binari WebSocket include ora heuristic Protobuf wire-format limitate e on-demand, senza aggiungere decoder work al capture hot path.
- La roadmap pubblica ora si concentra su regole protocol-aware più profonde, replay, confronto e condivisione più sicura delle prove redatte.

## Caratteristiche

Gli strumenti a cui ricorrere quando i DevTools del browser non sono sufficienti. Il debugging del traffico principale per Mac e iOS funziona: nativo su macOS, con versioni pubbliche e un flusso di lavoro locale.

### Cattura del traffico

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Controlla il traffico HTTP, HTTPS, WebSocket e GraphQL da qualsiasi app Mac, CLI o dispositivo iOS. I Browser DevTools terminano nel browser: Rockxy vede il resto del tuo stack.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Filtro e ricerca avanzati

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Restringi migliaia di richieste acquisite in pochi secondi. Combina filtri di metodo, host, stato, intestazione, corpo e processo oppure esegui una ricerca full-text nell'intera sessione.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets e Noise Control

Trasforma le indagini ricorrenti in scope riutilizzabili nella sidebar. Focus Sets combina inclusioni per app, domain e path con esclusioni domain/path, persiste tra gli avvii ed è disponibile in ogni workspace. Noise Control continua a catturare telemetria e traffico di poco valore, ma li nasconde nel workspace corrente.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant spiega il traffico selezionato accanto alla tabella request e alla sidebar native" width="820" />

Seleziona una o più request catturate e chiedi cosa è successo, cosa non ha funzionato, cosa è cambiato o cosa verificare dopo. Rockxy inizia con un'analisi basata sulle evidenze su questo Mac; un modello Ollama o provider configurato viene eseguito solo dopo che Review Data mostra il contesto esatto, limitato e redatto. Le risposte possono rivelare la request sorgente e preparare workflow di follow-up nativi, ma non modificano il traffico né eseguono azioni automaticamente.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Leggi la guida AI Assistant](docs/features/ai-assistant.mdx).

### Server MCP per client AI esterni

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Lascia che Claude Desktop o Cursor leggano il traffico catturato attraverso un server MCP locale. Chiedi "perché questo 500?" invece di incollare le intestazioni nella chat. Locale, sensibile alla redazione e open source.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Hub di configurazione per sviluppatori

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Copia e incolla gli snippet proxy per Python, Node.js, Go, Rust, cURL, Docker e browser, quindi fai clic su Esegui test per verificare che il traffico stia effettivamente fluendo.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Gestione dei certificati per il debug HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Una CA root ECDSA P-256 generata al primo avvio, sigillata nel portachiavi. Decrittografa HTTPS al primo tentativo; gli host bloccati passano automaticamente.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### Proxy SSL e decrittografia HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Scegli quali host ottengono la decrittazione TLS. Il traffico decrittografato mostra intestazioni reali e JSON; tutto il resto passa crittografato. Le regole con caratteri jolly ti consentono di definire l'ambito per dominio con un clic.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Ignora proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Salta host specifici in modo che le app aggiunte ai certificati, i servizi interni o la telemetria rumorosa non entrino mai nell'acquisizione. I caratteri jolly mantengono l'elenco breve e il registro delle richieste focalizzato su ciò che ti interessa veramente.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Elenco blocchi

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Fai fallire qualsiasi host. Elimina reti pubblicitarie, tracker di terze parti o una dipendenza instabile per vedere come si degrada la tua app quando non c'è più, senza modificare una riga di codice.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Mappa locale

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Servire un file salvato o un albero di directory al posto di una risposta live. Scambia un payload JSON, riproduci uno snapshot o aggiungi un'API di terze parti instabile a una copia locale durante il debug.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Mappa remota

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Riscrivi la destinazione di una richiesta catturata senza toccare il codice dell'app o /etc/hosts. Indirizza il traffico di produzione allo staging, al tuo server di sviluppo o al computer di un collega per una riproduzione di bug riproducibile.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Punti di interruzione e regole

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Metti in pausa una richiesta o una risposta, modifica il metodo, le intestazioni, il corpo o lo stato, quindi continua. Il modo più veloce per testare "cosa succede se l'API restituisce 401?" senza toccare il backend.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Modifica intestazioni

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Aggiungi, rimuovi o sostituisci le intestazioni su qualsiasi host senza ridistribuirle. Testa le modifiche CORS, l'autenticazione o la cache in pochi secondi con le preimpostazioni integrate.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Intestazioni di richiesta e risposta personalizzate

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Sostituisci le intestazioni per host con il pieno controllo su entrambe le fasi. Inserisci token di autenticazione sulle richieste in uscita, rimuovi Set-Cookie sulle risposte o aggiungi uno User-Agent personalizzato: salvato come regole con nome che puoi attivare in qualsiasi momento.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Condizioni di rete

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Accelera a 3G, EDGE, LTE, WiFi o un ritardo personalizzato. Il tuo laptop è in fibra; i tuoi utenti non lo sono: guarda la UX a 400 ms RTT prima di loro.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Componi: modifica e riproduci

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Ricostruisci qualsiasi richiesta HTTP acquisita (modifica metodo, URL, intestazioni, parametri di query o corpo) e inviala nuovamente senza uscire da Rockxy. Nessun ciclo di Postino, Insonnia o arricciatura copia-incolla. Esegui l'iterazione dei prompt LLM, i limiti di autenticazione fuzz o riproduci un caso di errore per gli endpoint OpenAI, Anthropic e Cohere in pochi secondi.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Confronta

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Impila due risposte acquisite una accanto all'altra e individua ogni campo che è stato invertito: stato, intestazioni, chiavi JSON, byte del corpo. Rileva regressioni API silenziose, output LLM non deterministici e deriva dei prompt senza inserire nulla in uno strumento diff di terze parti. La differenza affiancata evidenzia cosa è cambiato; Il confronto JSON approfondito ignora l'ordinamento delle chiavi.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Schede di anteprima personalizzate

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Visualizza i corpi delle richieste e delle risposte nel modo desiderato. Aggiungi schede extra all'inspector per JSON, GraphQL, JWT, immagine o il tuo formato, riutilizzabili per ogni richiesta acquisita.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sessioni ed esportazione

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Salva sessioni, importa/esporta HAR per il trasferimento tra strumenti, copia qualsiasi richiesta come cURL o JSON. Oscura intestazioni di autorizzazione, cookie e token di connessione prima della condivisione: consegna a un compagno di squadra una riproduzione del bug funzionante senza divulgare segreti.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Aree di lavoro con più schede

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Workspace multi-tab Rockxy con viste filtrate in modo indipendente della stessa cattura live" width="820" />

Mantieni affiancate viste di indagine indipendenti della stessa cattura live. Ogni scheda conserva filtri, ordinamento, selezione, scope della sidebar e stato dell'ispettore, condividendo proxy e transazioni catturate.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Script JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS si aggancia alle richieste e alle risposte per i casi che una regola statica non può coprire: redigere PII, firmare token, riscrivere payload. Gli errori emergono in linea invece di corrompere il traffico.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Ispezione Consapevole del Protocollo

Rockxy offre ispezione consapevole del protocollo per AI, Web3 RPC e x402 nel normale workflow di debug HTTP.

### Ispezione del traffico AI

Semplifica il debug del traffico del modello all'interno del normale flusso di lavoro di acquisizione. Rileva richieste AI, ispeziona chiamate di modelli selezionati, diagnostica risposte in streaming, confronta il comportamento di prompt/output e comprendi le catene di chiamate agli strumenti senza incollare payload sensibili in un altro servizio.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Ispezione Web3/RPC

Trasforma le chiamate di rete dell'era blockchain in prove di debug leggibili. Esamina il traffico JSON-RPC e Solana RPC, raggruppa le chiamate correlate in flussi, spiega gli errori RPC comuni e riproduci le richieste selezionate senza diventare un portafoglio o un block explorer.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### Suggerimenti per il flusso di pagamento x402

Comprendere i flussi HTTP gestiti a pagamento dal livello di rete. Evidenzia le risposte che richiedono il pagamento, segui il percorso dei nuovi tentativi e mantieni le prove di debug locali e sensibili alla redazione.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Lavori Futuri

Le sezioni seguenti descrivono una direzione pubblica, non il comportamento attuale.

### Pacchetti di prove redatte `In arrivo`

Condividi i fatti necessari per riprodurre un bug senza divulgare segreti. Crea pacchetti di traffico selezionato con riepiloghi di protocollo, anteprime di redazione e contesto supportato dall'origine che un membro del team può controllare.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Regole compatibili con il protocollo

Utilizza metadati AI e Web3 dove Rockxy già funziona: filtri, badge, colonne opzionali, confronto, regole, configurazione sviluppatore e riepiloghi MCP locali.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Condivisione e collaborazione in team `In arrivo`

Invia una sessione catturata a un compagno di squadra con un clic. Annota le richieste non riuscite in linea, vedi chi guarda cosa in tempo reale ed esegui il debug del traffico HTTPS senza condivisione dello schermo. Destinato a una versione futura.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

>MacOS nativo al 100%. Nessun elettrone. Nessuna visualizzazione web. SwiftUI + AppKit + SwiftNIO.

## Avvio rapido

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Costruisci ed esegui in Xcode. La finestra di benvenuto guida l'utente attraverso la configurazione della CA root, l'installazione dell'helper e l'attivazione del proxy.

**Requisiti:** macOS 14.0+, Xcode 16+, Swift 5.9

Se desideri connettere Rockxy a un client MCP locale dopo l'installazione, consulta il file [Guida all'integrazione MCP](docs/features/mcp.mdx).

## Rockxy contro alternative

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Modello di progetto** | Progetto open source AGPL-3.0 | App commerciale proprietaria | App commerciale proprietaria |
| **Codice sorgente** | Pubblico, verificabile, divisibile | Sorgente chiusa | Sorgente chiusa |
| **Costruisci dalla fonte** | Gratuito con Xcode da questo repository | Non disponibile da fonte pubblica | Non disponibile da fonte pubblica |
| **Base macOS nativa** | Swift + SwiftNIO + SwiftUI/AppKit | App commerciale nativa per macOS | App commerciale multipiattaforma |
| **Prima acquisizione locale** | Il proxy locale, i certificati, l'assistente e i dati di acquisizione rimangono sul tuo Mac | Applicazione proxy desktop | Applicazione proxy desktop |
| **Flusso di lavoro di configurazione dello sviluppatore** | Hub di configurazione per sviluppatori integrato per runtime, client, dispositivi, framework e ambienti | Guida alla configurazione specifica del prodotto | Guida alla configurazione specifica del prodotto |
| **Proxy esterno + instradamento PAC** | Proxy upstream HTTP/HTTPS, configurazione automatica PAC e regole di bypass | Strumenti proxy commerciali maturi | Strumenti proxy commerciali maturi |
| **Bridge MCP/automazione locale** | Redazione integrata, autenticata da token, per impostazione predefinita | Non rivendicato nei documenti pubblici esaminati | Non rivendicato nei documenti pubblici esaminati |
| **Percorso di contributo aperto** | Questioni pubbliche, discussioni, roadmap e PR | Prodotto controllato dal fornitore | Prodotto controllato dal fornitore |

Sulla roadmap: regole protocol-aware più profonde, bundle di prove redatte più sicuri, workflow di replay e confronto più solidi, guide Developer Setup più ampie e ricerca continua su HTTP/2 e HTTP/3.

## Sicurezza

Rockxy intercetta il traffico di rete: la sicurezza è fondamentale, non opzionale.

- L'helper XPC convalida i chiamanti tramite **confronto della catena di certificati**, non solo l'ID del bundle
- I plugin vengono eseguiti **JavaScriptCore in modalità sandbox** con timeout di 5 secondi, nessun accesso al filesystem/rete
- **Convalida dell'input** su tutti i confini: limiti di dimensione corporea, limiti URI, protezione DoS regex, prevenzione dell'attraversamento del percorso
- Credenziali **redatto automaticamente** nei log catturati
- File sensibili archiviati con **0o600 permessi**

Segnalare vulnerabilità tramite [SICUREZZA.md](SECURITY.md). Vedi il [architettura di sicurezza completa](docs/development/security.mdx) per i dettagli.

## Tabella di marcia

La tabella di marcia pubblica di Rockxy è orientata al flusso di lavoro e priva di date. Si concentra su affidabilità, UX nativo di macOS, flussi di lavoro di debug, supporto dei protocolli, visibilità del traffico dell'era AI/Web3, documentazione e onboarding dei contributori.

- [ROADMAP.md](ROADMAP.md): direzione ingegneria pubblica di alto livello
- [Roadmap pubblica di Rockxy](https://github.com/orgs/RockxyApp/projects/1): visibilità operativa per le problematiche tracciate nella roadmap

## Documentazione

La documentazione completa è disponibile presso il [Documenti Rockxy](docs/index.mdx):

- [Guida rapida](docs/quickstart.mdx) - diventa operativo in pochi minuti
- [Hub di configurazione per sviluppatori](docs/features/developer-setup-hub.mdx) — frammenti di runtime, guide del dispositivo, sonde di convalida e matrice di supporto
- [AI Assistant](docs/features/ai-assistant.mdx) — analizza il traffico selezionato localmente o con un modello configurato dopo Review Data
- [Filtri e ricerca](docs/core-features/filters-and-search.mdx) — scope sidebar, Focus Sets, Noise Control, filtri toolbar e ricerca
- [Ispezione AI e Web3](docs/features/ai-web3-inspection.mdx) — ispeziona traffico model API, JSON-RPC e x402 riconosciuto
- [Integrazione MCP](docs/features/mcp.mdx) - collega Rockxy ai client MCP locali
- [Architettura](docs/development/architecture.mdx) — motore proxy, modello di attore, flusso di dati
- [Modello di sicurezza](docs/development/security.mdx) — confini di fiducia, convalida XPC, gestione dei certificati
- [Decisioni di progettazione](docs/development/design-decisions.mdx) - perché SwiftNIO, NSTableView, attori
- [Costruire dalla fonte](docs/development/building.mdx) - costruire, testare, lint ed eseguire il debug
- [Stile del codice](docs/development/code-style.mdx) — SwiftLint, SwiftFormat e convenzioni
- [Registro delle modifiche](CHANGELOG.md) — opere inedite e uscite contrassegnate

## Contribuire

I contributi sono benvenuti: codice, test, documenti, segnalazioni di bug e feedback UX.

Vedi **[CONTRIBUIRE.md](CONTRIBUTING.md)** per le istruzioni di configurazione, lo stile del codice e l'elenco completo di controllo PR.

I buoni primi numeri sono etichettati [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Aprendo una PR, accetti i [CLA](CLA.md).

## Sponsor e partner

Rockxy è costruito e gestito da sviluppatori indipendenti. Le sponsorizzazioni finanziano lo sviluppo continuo, i controlli di sicurezza e le nuove funzionalità.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy &egrave; ospitato fiscalmente da [Open Source Collective](https://docs.oscollective.org/). I contributi e le spese del progetto sono registrati sulla [pagina pubblica Open Collective di Rockxy](https://opencollective.com/rockxy), offrendo una visione trasparente di come i fondi vengono ricevuti e utilizzati.

| Livello | Contributo | Cosa supporta |
|---------|------------|--------------|
| **Backer** | Da $5/mese | Manutenzione open source, documentazione, test e release |
| **Builder** | Da $25/mese | Test di regressione, miglioramenti delle prestazioni e workflow quotidiani di debug |
| **Sponsor** | $100/mese | Manutenzione a lungo termine di uno strumento attento alla privacy e gratuito per gli sviluppatori |
| **Sustaining Sponsor** | $500/mese | Manutenzione e sviluppo del prodotto mirati, inclusi automazione delle release e supporto dei protocolli |

**Richieste di partenariato** - società di strumenti di sviluppo, società di sicurezza e team aziendali alla ricerca di integrazioni personalizzate o soluzioni white label: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Supporto

- [Open Collective](https://opencollective.com/rockxy/donate) — contribuisci a Rockxy tramite il suo budget di progetto trasparente
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — sostenere lo sviluppo di Rockxy
- [Problemi di GitHub](https://github.com/RockxyApp/Rockxy/issues) — segnalazioni di bug e richieste di funzionalità
- [Discussioni su GitHub](https://github.com/RockxyApp/Rockxy/discussions) - domande e chat della comunità
- **E-mail** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Problemi di sicurezza** – vedi [SICUREZZA.md](SECURITY.md) per una divulgazione responsabile

## Licenza

[Licenza pubblica generale GNU Affero v3.0](LICENSE) — Copyright 2024–2026 Collaboratori Rockxy.

## Storia delle stelle

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Fatto da <a href="https://github.com/LocNguyenHuu">Stefano</a>. Costruito con Swift, SwiftNIO, SwiftUI e AppKit.</sub>
</p>
