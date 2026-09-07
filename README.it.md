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
  Un'alternativa local-first, AGPL-3.0 a <a href="#rockxy-vs-alternative">Proxyman e Charles Proxy</a>.
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

## Punti salienti del ramo attuale

- AI Assistant ora indaga una o più richieste selezionate con analisi locale integrata, modelli Ollama o provider configurati opzionali, conferma esplicita di Review Data, redazione limitata, risposte in streaming, rivelazione delle prove e handoff avviati dall'utente.
- La sidebar nativa ora include Focus Sets riutilizzabili per gli scope app/domain/path più il Noise Control per workspace che nasconde domini o path corrispondenti senza fermare la cattura.
- Il workspace principale ora usa split view native verticali e orizzontali per il Context Dock e l'inspector inferiore, preservando divisori a piena altezza, separatori toolbar/footer coordinati e ridimensionamento automatico del layout.
- Il proxy upstream ora include la configurazione proxy automatica gratuita/core con routing URL PAC per `DIRECT`, HTTP e HTTPS preservando SOCKS5 esistente e i limiti dei criteri di autenticazione.
- I flussi di lavoro di esportazione ora coprono OpenAPI YAML/HTML e la pubblicazione di Gist con traffico selezionato con creazione di payload sensibile alla redazione.
- Gli strumenti di ispezione ora includono il filtro JSONPath/chiave/valore e anteprime rapide per il testo del payload selezionato come i JWT.
- L'ispezione del traffico AI e Web3 ora aggiunge etichette di protocollo, tab dell'inspector e riepiloghi di debug per chiamate di modello riconosciute, traffico JSON-RPC e suggerimenti di pagamento in stile x402.
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

Lascia che Claude Desktop o Cursor ispezionino il traffico catturato tramite dieci strumenti di sola lettura nel server MCP locale di Rockxy. Chiedi "perché questo 500?" invece di incollare le intestazioni nella chat. L'implementazione è open source, autenticata tramite token e mantiene la redazione dei dati sensibili attiva per impostazione predefinita.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Hub di configurazione per sviluppatori

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Copia e incolla gli snippet proxy per Python, Node.js, Go, Rust, cURL, Docker e browser, quindi fai clic su Esegui test per verificare che il traffico stia effettivamente fluendo.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Gestione dei certificati per il debug HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Una CA root ECDSA P-256 generata al primo avvio, sigillata nel portachiavi. Decrittografa HTTPS al primo tentativo; gli host con pinning passano automaticamente.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Promuovi qualsiasi intestazione di richiesta o risposta a colonna di prima classe nella tabella del traffico. Mantieni separate le sorgenti di richiesta e risposta, salva le intestazioni che ti interessano, poi scorri request ID, trace ID, stato della cache o metadati personalizzati senza aprire ogni inspector.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Condizioni di rete

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Accelera a 3G, EDGE, LTE, WiFi o un ritardo personalizzato. Il tuo laptop è in fibra; i tuoi utenti non lo sono: guarda la UX a 400 ms RTT prima di loro.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Componi: modifica e riproduci

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Ricostruisci qualsiasi richiesta HTTP acquisita (modifica metodo, URL, intestazioni, parametri di query o corpo) e inviala nuovamente senza uscire da Rockxy. Nessun ciclo copia-incolla verso Postman, Insomnia o curl. Itera sui prompt LLM, fuzza i limiti di autenticazione o riproduci un caso di errore per gli endpoint OpenAI, Anthropic e Cohere in pochi secondi.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Confronta

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Impila due transazioni catturate o payload incollati una accanto all'altra e individua ogni campo che è cambiato: stato, intestazioni, chiavi JSON o byte del corpo. Rileva regressioni API silenziose, output LLM non deterministici e deriva dei prompt senza inviare nulla a uno strumento diff di terze parti.

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

Mantieni affiancate viste di indagine indipendenti della stessa cattura live: una scheda per il traffico di staging, una per la produzione e una per un flusso su dispositivo iOS. Ogni scheda conserva i propri filtri, ordinamento, selezione, scope della sidebar e stato dell'ispettore, condividendo proxy e transazioni catturate.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Script JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS si aggancia alle richieste e alle risposte per i casi che una regola statica non può coprire: redigere PII, firmare token, riscrivere payload. Gli errori emergono in linea invece di corrompere il traffico.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Ispezione Consapevole del Protocollo

Rockxy offre ispezione consapevole del protocollo per AI, Web3 RPC e x402 nel normale workflow di debug HTTP.

### Ispezione del traffico AI

Rockxy rileva le richieste AI riconosciute all'interno del normale flusso di cattura. Ispeziona chiamate di modello selezionate, stato di streaming, campi usage quando presenti, avvisi, retrieval hint e riepiloghi di tool-call senza incollare payload sensibili in un altro servizio.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Ispezione Web3/RPC

Rockxy trasforma le chiamate di rete dell'era blockchain in prove di debug leggibili. Ispeziona il traffico HTTP JSON-RPC in stile EVM e Solana con provider host, request ID, method, riepilogo batch, errore, chain, transazione, payload e debug intent, senza trasformare Rockxy in un wallet o un block explorer.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### Suggerimenti per il flusso di pagamento x402

Rockxy evidenzia i suggerimenti payment-required e orientati al retry così che i flussi HTTP payment-gated siano comprensibili dal livello di rete, mentre le prove di debug restano locali e redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Lavori Futuri

Le sezioni seguenti descrivono una direzione pubblica, non il comportamento attuale.

### Regole compatibili con il protocollo

Rockxy oggi può etichettare e ispezionare il traffico AI e Web3. Il rule matching più profondo per model, tool call, JSON-RPC method, chain, transaction hash o batch subcall resta lavoro futuro; gli attuali strumenti di modifica del traffico continuano a fare match su URL, HTTP method e header.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Pacchetti di prove redatte `In arrivo`

Condividi i fatti necessari per riprodurre un bug senza divulgare segreti. Crea pacchetti di traffico selezionato con riepiloghi di protocollo, anteprime di redazione e contesto supportato dall'origine che un membro del team può controllare.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Condivisione e collaborazione in team `In arrivo`

Invia una sessione catturata a un compagno di squadra con un clic. Annota le richieste non riuscite in linea, vedi chi guarda cosa in tempo reale ed esegui il debug del traffico HTTPS senza condivisione dello schermo. Destinato a una versione futura.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Shell di app macOS nativa &mdash; nessun Electron. SwiftUI + AppKit + SwiftNIO, con WebKit usato solo per l'anteprima del body HTML.

## Avvio rapido

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Costruisci ed esegui in Xcode. La finestra di benvenuto guida l'utente attraverso la configurazione della CA root, l'installazione dell'helper e l'attivazione del proxy.

**Requisiti:** macOS 14.0+, Xcode 16+, Swift 5.9

Se desideri connettere Rockxy a un client MCP locale dopo l'installazione, consulta la [Guida all'integrazione MCP](docs/features/mcp.mdx).

## Rockxy rispetto alle alternative

La matrice principale copre i proxy di debug Web generici. Test di sicurezza
suite e intercettori orientati al browser/API con sostanziale sovrapposizione del flusso di lavoro
sono elencati separatamente quindi i prodotti a differenza non sono presentati come intercambiabili.
Gli analizzatori di pacchetti e i client solo API non rientrano in questo confronto.

### Proxy di debug web diretto

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Forma del prodotto** | Proxy di debug nativo di macOS | App macOS nativa; Edizioni Windows/Linux basate su Electron | Proxy di debug desktop multipiattaforma | CLI/TUI multipiattaforma e toolkit proxy dell'interfaccia utente Web | Proxy desktop multipiattaforma Electron e client HTTP | Proxy di debug desktop multipiattaforma |
| **Modello di origine e creazione** | Fonte comunitaria pubblica sotto AGPL-3.0-or-later; costruibile con Xcode. Lo DMG ufficiale contiene anche componenti downstream non pubblici | Sorgente chiusa; nessuna fonte di applicazione pubblica identificata nei materiali ufficiali esaminati | Sorgente chiusa; nessuna fonte di applicazione pubblica identificata nei materiali ufficiali esaminati | Sorgente con licenza pubblica MIT; costruibile dal sorgente | Sorgente desktop pubblica AGPL; costruibile dalla fonte; i binari pubblicati hanno opzioni di licenza aggiuntive | Sorgente chiusa; distribuito come codice oggetto sotto Fiddler Everywhere EULA |
| **Cattura e configura** | Proxy di sistema locale con configurazione guidata per app Mac, runtime, dispositivi iOS e simulatore | Configurazione automatica per app, runtime e dispositivi mobili Mac | Proxy locale con guide di configurazione per macOS, iOS e multipiattaforma | Modalità di acquisizione normale, processo locale, WireGuard, inversa, trasparente e altre | Intercettazione proxy mirata e manuale per browser, runtime, contenitori e dispositivi mobili | Modalità di acquisizione di sistema, rete, browser, terminale, esplicita e da dispositivo remoto |
| **Modifica e deride** | Punti di interruzione, Map Local/Remote, regole di intestazione, blocco e regole di latenza | Punti di interruzione, Map Local/Remote, elenchi di blocchi, condizioni di rete e regole JavaScript | Punti di interruzione, riscrittura, Map Local/Remote, blocco e limitazione | Map Local/Remote, modifica del corpo/intestazione, blocco e riproduzione del server | Punti di interruzione più riscrittura, reindirizzamento, simulazione e inserimento di errori basati su regole; parte dell'automazione è limitata al piano | Regole, punti di interruzione, reindirizzamenti, modifica della risposta e mocking |
| **Riproduci e confronta** | Composizione/riproduzione più richiesta locale affiancata, intestazione e confronto del corpo | Componi, ripeti e confronta | Ripeti e modifica le richieste | Riproduzione lato client e lato server | Client HTTP integrato per la composizione e l'invio di richieste | API Compositore, riproduzione del traffico e confronto del traffico documentati come beta |
| **Flussi di lavoro WebSocket** | Ispezione di testo/frame binario con euristica limitata Protobuf | Ispezione WS/WSS; gli script possono modificare URL/intestazioni di handshake, non messaggi | Il supporto WebSocket è documentato nella cronologia delle versioni ufficiali | Intercettazione e scripting WebSocket; La riproduzione WebSocket non è supportata | Ispezione WebSocket più regole specifiche WebSocket | WebSocket cattura e ispezione |
| **Scripting ed estensibilità** | Hook JavaScriptCore sandbox con API limitato e timeout di esecuzione | JavaScript script di richiesta/risposta | Riscrivere le regole e un'interfaccia Web di controllo; nessuna funzionalità di scripting generale JavaScript documentata | Componenti aggiuntivi Python e automazione della riga di comando | Automazione basata su regole più librerie proxy e di origine pubblica | Automazione basata su regole; nessuna funzionalità di scripting generale di prima parte documentata |
| **Instradamento a monte** | [Proxy upstream HTTP/HTTPS e routing URL PAC](docs/features/upstream-proxy.mdx); La politica della community disabilita l'autenticazione proxy e SOCKS5 e limita le regole di bypass a tre | Routing esterno HTTP/HTTPS/SOCKS e PAC con regole di bypass | Proxy esterni HTTP/HTTPS/SOCKS con regole di autenticazione e bypass | Modalità upstream HTTP/HTTPS più modalità inversa e listener SOCKS | Impostazioni upstream di sistema, HTTP, HTTPS e SOCKS; potrebbero applicarsi limiti del piano | Concatenamento automatico ai proxy di sistema più acquisizione proxy inverso |
| **AI e MCP** | [Assistente AI in-app](docs/features/ai-assistant.mdx) e [MCP locale integrato](docs/features/mcp.mdx) con 10 strumenti di sola lettura, autenticazione token e redazione attiva per impostazione predefinita | MCP integrato per client AI esterni, incluse letture del traffico e controlli di app/regole | Non documentato | Non documentato | Nell'attuale fonte ufficiale è presente un bridge locale MCP in bundle; nessun assistente in-app documentato | MCP integrato più un assistente di debug di livello professionale la cui documentazione attuale richiede che i dettagli sul traffico acquisiti siano incollati nella chat |

### Strumenti di intercettazione adiacenti

Questi prodotti si sovrappongono in modo significativo a Rockxy ma sono leader nei test di sicurezza,
regole del browser o flussi di lavoro del client API anziché lo stesso scopo generale
focus nativo del proxy di debug.

| **Prodotto** | **Perché è adiacente** | **Modello di origine e creazione** | **Sovrapposizione rilevante** | **AI e MCP** |
|---|---|---|---|---|
| **Burp Suite** | Suite di test di sicurezza web con proxy di intercettazione | Applicazione a codice chiuso; il suo EULA afferma che gli utenti non hanno diritto alla fonte dell'applicazione. Le estensioni possono utilizzare licenze separate | Intercettazione proxy e corrispondenza/sostituzione, ripetitore, WebSocket, proxy upstream/SOCKS e un ampio ecosistema di estensione | Burp AI è disponibile in Repeater; PortSwigger mantiene anche un'estensione server pubblica MCP per client AI esterni |
| **ZAP** | Security scanner e proxy di intercettazione | Sorgente pubblica Apache-2.0; costruibile dal sorgente | Intercettazione/modifica, rinvio manuale, punti di interruzione e script WebSocket, scripting multilingue, componenti aggiuntivi e automazione | Integrazione ufficiale MCP e componenti aggiuntivi di supporto LLM opzionali |
| **Requestly HTTP Interceptor** | Estensione del browser e strumento interceptor/mock desktop multipiattaforma | Sorgente di intercettazione desktop pubblica AGPL; il client Requestly API separato è proprietario in base all'avviso del repository pubblico della comunità | Acquisizione a livello di sistema/browser, reindirizzamento, Map Local/Remote, modifica di intestazione/corpo, trasformazioni JavaScript, mock e simulazione di ritardo/errore | Un server MCP ufficiale separato gestisce regole e gruppi; nessun assistente per l'analisi del traffico in-app documentato |

La disponibilità delle funzionalità può variare in base all'edizione, al piano, alla piattaforma o al componente aggiuntivo.
"Non documentato" significa che una funzionalità non è stata trovata nel file first-party ufficiale
fonti recensite su 2026-08-22; non è una prova che la capacità sia assente.
Le dichiarazioni su prodotti e funzionalità di cui sopra sono state confrontate con la documentazione del fornitore,
repository di sorgenti gestiti dal fornitore o termini di licenza del fornitore in quella data e
potrebbe cambiare. I nomi dei prodotti e i marchi appartengono ai rispettivi proprietari;
Rockxy non è affiliato o approvato da loro. Le correzioni sono benvenute
tramite il tracker dei problemi Rockxy.

Sulla tabella di marcia: regole più approfondite basate sul protocollo, pacchetti di prove redatte più sicure, flussi di lavoro di riproduzione e confronto più efficaci, linee guida più ampie per l'impostazione degli sviluppatori e ricerca continua su HTTP/2 e HTTP/3.

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

Rockxy è gestito in modo indipendente. Le sponsorizzazioni aiutano a finanziare lo sviluppo continuo, l'infrastruttura di release, la documentazione e il lavoro sulla sicurezza.

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

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Fatto da <a href="https://github.com/LocNguyenHuu">Stephen</a>. Costruito con Swift, SwiftNIO, SwiftUI e AppKit.</sub>
</p>
