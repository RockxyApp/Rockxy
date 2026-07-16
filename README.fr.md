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
  <strong>Proxy de d&eacute;bogage open-source et auditable pour macOS.</strong>
</p>

<p align="center">
  Interceptez, inspectez et modifiez le trafic HTTP/HTTPS/WebSocket/GraphQL avec une app Swift native que vous pouvez inspecter, compiler et v&eacute;rifier.<br>
  Con&ccedil;u pour les workflows de d&eacute;bogage API, mobile, assist&eacute;s par MCP, IA et de l'&egrave;re blockchain &agrave; mesure que Rockxy &eacute;volue.<br>
  Une alternative local-first, AGPL-3.0 &agrave; <a href="#rockxy-vs-alternatives">Proxyman et Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Version" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Plateforme" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Licence" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs bienvenues" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Soutenir" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy en cours d'ex&eacute;cution sur macOS" width="800" />
  </a>
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.29.0** — 2026-07-12

### Added

- Added dedicated model API traffic inspection with provider and model hints, streaming state, usage details when available, tool-call summaries, retrieval hints, and clear unavailable-field warnings.
- Added Web3 JSON-RPC inspection for EVM and Solana-style HTTP RPC traffic, including provider host, request ID, method, batch summary, error, chain, transaction, payload, and debug-intent details.
- Added x402-style payment-flow hints for payment-required and retry-oriented HTTP traffic.
- Added a default Protocol column and protocol filters that make model API, Web3 RPC, gRPC, GraphQL, WebSocket, and HTTP traffic easier to scan in the request list.

### Changed

- Kept model API, Web3, and gRPC inspector tabs together at the end of the inspector tab row for a more consistent response-review workflow.
- Clarified that rules and debugging tools continue to match URL, HTTP method, and headers rather than model names, tool calls, chain IDs, JSON-RPC methods, or batch subcalls.
- Refined General settings so proxy controls, certificate status, and certificate actions are easier to scan.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Points forts de la branche actuelle

- Upstream Proxy inclut d&eacute;sormais une Automatic Proxy Configuration free/core avec routage PAC URL pour les routes `DIRECT`, HTTP et HTTPS, tout en pr&eacute;servant les fronti&egrave;res de policy SOCKS5 et d'authentification existantes.
- Les workflows d'export couvrent d&eacute;sormais OpenAPI YAML/HTML et la publication Gist du trafic s&eacute;lectionn&eacute; avec construction de payload redaction-aware.
- Les outils Inspector incluent d&eacute;sormais le filtrage JSONPath/key/value et des aper&ccedil;us rapides pour le texte de payload s&eacute;lectionn&eacute;, comme les JWT.
- Node.js Developer Setup refl&egrave;te d&eacute;sormais le client s&eacute;lectionn&eacute; pendant la validation et dispose d'un guide localhost plus complet.
- Developer Setup Hub couvre d&eacute;sormais les runtimes, navigateurs, clients, appareils, frameworks et environnements avec des snippets cibl&eacute;s, des watchers de validation et une documentation honn&ecirc;te.
- Le travail WebSocket Protobuf continue dans la direction d'une inspection de protocoles plus riche pour Rockxy.
- La planification publique de la roadmap inclut d&eacute;sormais le d&eacute;bogage protocol-aware du trafic IA, des flows Web3/RPC, des flows de paiement de type x402 et un partage d'evidence redig&eacute;e plus s&ucirc;r.

## Fonctionnalit&eacute;s

Les outils que vous saisissez quand les DevTools du navigateur ne suffisent plus. Du d&eacute;bogage de trafic principal pour le travail Mac et iOS &mdash; natif macOS, avec des releases publiques et un flux local-first.

### Capture du trafic

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Inspectez le trafic HTTP, HTTPS, WebSocket et GraphQL depuis n'importe quelle application Mac, CLI ou appareil iOS. Les DevTools du navigateur s'arr&ecirc;tent au navigateur &mdash; Rockxy voit le reste de votre stack.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Filtres et recherche avanc&eacute;s

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

R&eacute;duisez des milliers de requ&ecirc;tes captur&eacute;es en quelques secondes. Combinez les filtres method, host, status, header, body et processus &mdash; ou lancez une recherche plein texte sur toute la session.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Serveur MCP pour assistants IA

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Laissez Claude Desktop ou Cursor lire votre trafic captur&eacute; via un serveur MCP local. Demandez "pourquoi cette requ&ecirc;te a renvoy&eacute; 500 ?" au lieu de coller des headers dans le chat. Local, redaction-aware et open source.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Copiez-collez les snippets de proxy pour Python, Node.js, Go, Rust, cURL, Docker et les navigateurs, puis cliquez sur Run Test pour confirmer que le trafic passe r&eacute;ellement.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Gestion des certificats pour d&eacute;boguer HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Un root CA P-256 ECDSA g&eacute;n&eacute;r&eacute; au premier lancement, scell&eacute; dans votre Keychain. D&eacute;chiffrez HTTPS du premier coup ; les h&ocirc;tes &eacute;pingl&eacute;s sont automatiquement laiss&eacute;s en transit.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL Proxy et d&eacute;chiffrement HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Choisissez quels h&ocirc;tes seront d&eacute;chiffr&eacute;s en TLS. Le trafic d&eacute;chiffr&eacute; r&eacute;v&egrave;le les vrais headers et JSON ; le reste passe chiffr&eacute;. Les r&egrave;gles wildcard permettent de cibler un domaine en un clic.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Sautez certains h&ocirc;tes pour que les applis &agrave; pinning de certificat, les services internes ou la t&eacute;l&eacute;m&eacute;trie bruyante n'entrent jamais dans la capture. Les wildcards gardent la liste courte et le journal de requ&ecirc;tes concentr&eacute; sur ce qui compte.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Faites &eacute;chouer n'importe quel h&ocirc;te. Coupez les r&eacute;gies pub, les trackers tiers ou une d&eacute;pendance instable pour voir comment votre app se d&eacute;grade sans elle &mdash; sans changer une ligne de code.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Servez un fichier enregistr&eacute; ou une arborescence locale &agrave; la place d'une r&eacute;ponse en direct. Substituez un payload JSON, rejouez un snapshot ou &eacute;pinglez une API tierce capricieuse sur une copie locale pendant le d&eacute;bogage.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

R&eacute;&eacute;crivez la destination d'une requ&ecirc;te captur&eacute;e sans toucher au code de l'application ni &agrave; /etc/hosts. Pointez le trafic de prod vers staging, votre serveur de d&eacute;v ou la machine d'un coll&egrave;gue pour reproduire un bug de mani&egrave;re fiable.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Breakpoints et r&egrave;gles

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Mettez une requ&ecirc;te ou r&eacute;ponse en pause, modifiez method, headers, body ou status, puis continuez. Le moyen le plus rapide de tester "et si l'API renvoie 401 ?" sans toucher au backend.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Modifier les headers

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Ajoutez, supprimez ou remplacez des headers sur n'importe quel h&ocirc;te sans red&eacute;ployer. Testez CORS, l'auth ou les changements de cache en quelques secondes gr&acirc;ce aux presets int&eacute;gr&eacute;s.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Headers de requ&ecirc;te et de r&eacute;ponse personnalis&eacute;s

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Surchargez les headers par h&ocirc;te avec un contr&ocirc;le total sur les deux phases. Injectez des tokens d'auth sur les requ&ecirc;tes sortantes, supprimez Set-Cookie sur les r&eacute;ponses ou figez un User-Agent personnalis&eacute; &mdash; le tout sauvegard&eacute; en r&egrave;gles nomm&eacute;es activables &agrave; tout moment.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Conditions r&eacute;seau

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Bridez en 3G, EDGE, LTE, WiFi ou avec un d&eacute;lai personnalis&eacute;. Votre laptop est en fibre ; vos utilisateurs non &mdash; voyez l'UX &agrave; 400 ms de RTT avant eux.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose &mdash; &Eacute;diter et rejouer

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Reconstruisez n'importe quelle requ&ecirc;te HTTP captur&eacute;e &mdash; changez method, URL, headers, query params ou body &mdash; et renvoyez-la sans quitter Rockxy. Plus de boucle copier-coller vers Postman, Insomnia ou curl. It&eacute;rez sur des prompts LLM, fuzzez des limites d'auth ou reproduisez un cas qui &eacute;choue pour OpenAI, Anthropic et Cohere en quelques secondes.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Comparer

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Empilez deux r&eacute;ponses captur&eacute;es c&ocirc;te &agrave; c&ocirc;te et rep&eacute;rez chaque champ qui a bascul&eacute; &mdash; status, headers, cl&eacute;s JSON, octets du body. Attrapez les r&eacute;gressions API silencieuses, les sorties LLM non d&eacute;terministes et la d&eacute;rive de prompt sans pousser quoi que ce soit vers un outil tiers. Le diff c&ocirc;te &agrave; c&ocirc;te met en &eacute;vidence ce qui change ; la comparaison JSON profonde ignore l'ordre des cl&eacute;s.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Onglets de pr&eacute;visualisation personnalis&eacute;s

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Rendez les bodies de requ&ecirc;te et de r&eacute;ponse comme vous le souhaitez. &Eacute;pinglez des onglets suppl&eacute;mentaires dans l'inspecteur pour JSON, GraphQL, JWT, image ou votre propre format &mdash; r&eacute;utilisables sur chaque requ&ecirc;te captur&eacute;e.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sessions et export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Sauvegardez des sessions, importez/exportez du HAR pour le passage d'un outil &agrave; l'autre, copiez n'importe quelle requ&ecirc;te en cURL ou JSON. Redactez les headers d'authorization, cookies et bearer tokens avant partage &mdash; donnez &agrave; un coll&egrave;gue un repro de bug fonctionnel sans fuiter de secrets.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Espaces de travail multi-onglets

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

Lancez des sessions de capture ind&eacute;pendantes c&ocirc;te &agrave; c&ocirc;te &mdash; un onglet pour staging, un pour la prod, un pour le build iOS. Chaque onglet conserve ses propres filtres, s&eacute;lection et &eacute;tat d'inspecteur, donc le changement de contexte ne co&ucirc;te rien.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Scripting JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

Hooks JS sur les requ&ecirc;tes et r&eacute;ponses pour les cas qu'une r&egrave;gle statique ne couvre pas &mdash; redacter les PII, signer des tokens, r&eacute;&eacute;crire des payloads. Les erreurs apparaissent inline au lieu de corrompre le trafic.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Plus de fonctionnalit&eacute;s bient&ocirc;t

Les fonctionnalit&eacute;s futures sont suivies publiquement et ne seront livr&eacute;es que lorsque l'impl&eacute;mentation, les tests, le comportement privacy et la documentation seront pr&ecirc;ts.

### Inspection du trafic IA `Bient&ocirc;t disponible`

Rendre le trafic de mod&egrave;le plus facile &agrave; d&eacute;boguer dans le workflow de capture normal. D&eacute;tecter les requ&ecirc;tes IA, inspecter les appels de mod&egrave;le s&eacute;lectionn&eacute;s, diagnostiquer les r&eacute;ponses streaming, comparer le comportement prompt/output et comprendre les cha&icirc;nes de tool-calls sans coller de payloads sensibles dans un autre service.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Inspection Web3/RPC `Bient&ocirc;t disponible`

Transformer les appels r&eacute;seau de l'&egrave;re blockchain en evidence de d&eacute;bogage lisible. Inspecter le trafic JSON-RPC et Solana RPC, regrouper les appels li&eacute;s en flows, expliquer les erreurs RPC courantes et rejouer les requ&ecirc;tes s&eacute;lectionn&eacute;es sans transformer Rockxy en wallet ou block explorer.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### D&eacute;bogage des flows de paiement x402 `Bient&ocirc;t disponible`

Comprendre les flows HTTP payment-gated depuis la couche r&eacute;seau. Mettre en &eacute;vidence les r&eacute;ponses payment-required, suivre le chemin de retry et garder l'evidence de d&eacute;bogage locale et redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### Bundles d'evidence redig&eacute;e `Bient&ocirc;t disponible`

Partager les faits n&eacute;cessaires pour reproduire un bug sans divulguer de secrets. Packager le trafic s&eacute;lectionn&eacute; avec des r&eacute;sum&eacute;s de protocole, des aper&ccedil;us de redaction et un contexte source-backed qu'un coll&egrave;gue peut auditer.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Filtres et r&egrave;gles protocol-aware `Bient&ocirc;t disponible`

Utiliser les m&eacute;tadonn&eacute;es IA et Web3 l&agrave; o&ugrave; Rockxy travaille d&eacute;j&agrave; : filtres, badges, colonnes optionnelles, comparaison, r&egrave;gles, Developer Setup et r&eacute;sum&eacute;s MCP locaux.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Partage et collaboration en &eacute;quipe `Bient&ocirc;t disponible`

Envoyez une session captur&eacute;e &agrave; un coll&egrave;gue d'un seul clic. Annotez les requ&ecirc;tes en &eacute;chec en inline, voyez qui regarde quoi en temps r&eacute;el et faites du pair-debug HTTPS sans partage d'&eacute;cran. Cibl&eacute; pour une release future.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100 % natif macOS. Pas d'Electron. Pas de vues web. SwiftUI + AppKit + SwiftNIO.

## D&eacute;marrage rapide

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Compilez et ex&eacute;cutez dans Xcode. La fen&ecirc;tre de bienvenue vous guide &agrave; travers la configuration du CA racine, l'installation du helper et l'activation du proxy.

**Pr&eacute;requis :** macOS 14.0+, Xcode 16+, Swift 5.9

## Rockxy vs. Alternatives

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Mod&egrave;le de projet** | Projet open-source AGPL-3.0 | App commerciale propri&eacute;taire | App commerciale propri&eacute;taire |
| **Code source** | Public, auditable, forkable | Source ferm&eacute;e | Source ferm&eacute;e |
| **Compilation depuis la source** | Gratuite avec Xcode depuis ce repo | Non disponible depuis une source publique | Non disponible depuis une source publique |
| **Base native macOS** | Swift + SwiftNIO + SwiftUI/AppKit | App commerciale native macOS | App commerciale multiplateforme |
| **Capture local-first** | Proxy local, certificats, helper et donn&eacute;es de capture restent sur votre Mac | App proxy desktop | App proxy desktop |
| **Workflow de setup d&eacute;veloppeur** | Developer Setup Hub int&eacute;gr&eacute; pour runtimes, clients, appareils, frameworks et environnements | Guides de setup propres au produit | Guides de setup propres au produit |
| **MCP/local automation bridge** | Int&eacute;gr&eacute;, authentifi&eacute; par token, masquage par d&eacute;faut | Non revendiqu&eacute; dans les docs publiques consult&eacute;es | Non revendiqu&eacute; dans les docs publiques consult&eacute;es |
| **Chemin de contribution ouvert** | Issues, discussions, roadmap et PRs publics | Produit contr&ocirc;l&eacute; par le fournisseur | Produit contr&ocirc;l&eacute; par le fournisseur |

Sur la feuille de route : workflows replay/diff/rules/scripting plus profonds, inspection WebSocket et GraphQL am&eacute;lior&eacute;e, d&eacute;bogage protocol-aware de l'IA et du Web3/RPC, visibilit&eacute; des flows de paiement de type x402, et exploration du support gRPC/Protobuf ainsi que HTTP/2 et HTTP/3.

## S&eacute;curit&eacute;

Rockxy intercepte le trafic r&eacute;seau &mdash; la s&eacute;curit&eacute; est fondamentale, pas optionnelle.

- Le helper XPC valide les appelants par **comparaison de cha&icirc;ne de certificats**, pas seulement par bundle ID
- Les plugins s'ex&eacute;cutent dans un **JavaScriptCore isol&eacute;** avec un timeout de 5 secondes, sans acc&egrave;s au syst&egrave;me de fichiers ni au r&eacute;seau
- **Validation des entr&eacute;es** sur toutes les fronti&egrave;res &mdash; limites de taille des body, limites d'URI, protection contre le DoS regex, pr&eacute;vention du path traversal
- Les identifiants sont **automatiquement masqu&eacute;s** dans les logs
- Les fichiers sensibles sont stock&eacute;s avec des **permissions 0o600**

Signaler les vuln&eacute;rabilit&eacute;s via [SECURITY.md](SECURITY.md). Voir l'[architecture de s&eacute;curit&eacute; compl&egrave;te](docs/development/security.mdx) pour plus de d&eacute;tails.

## Feuille de route

La feuille de route publique de Rockxy est orient&eacute;e workflows et sans dates promises. Elle se concentre sur la fiabilit&eacute;, l'UX macOS native, les workflows de d&eacute;bogage, les protocoles, la visibilit&eacute; du trafic de l'&egrave;re IA/Web3, la documentation et l'accueil des contributeurs.

- [ROADMAP.md](ROADMAP.md) : direction d'ing&eacute;nierie publique de haut niveau
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1) : visibilit&eacute; op&eacute;rationnelle des issues suivies dans la feuille de route

## Documentation

Documentation compl&egrave;te disponible sur [Rockxy Docs](docs/index.mdx) :

- [Guide de d&eacute;marrage rapide](docs/quickstart.mdx) &mdash; op&eacute;rationnel en quelques minutes
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) &mdash; snippets runtime, guides appareil, sondes de validation et matrice de support
- [Architecture](docs/development/architecture.mdx) &mdash; moteur proxy, mod&egrave;le Actor, flux de donn&eacute;es
- [Mod&egrave;le de s&eacute;curit&eacute;](docs/development/security.mdx) &mdash; fronti&egrave;res de confiance, validation XPC, gestion des certificats
- [D&eacute;cisions de conception](docs/development/design-decisions.mdx) &mdash; pourquoi SwiftNIO, NSTableView, les Actors
- [Compiler depuis les sources](docs/development/building.mdx) &mdash; compilation, tests, lint et d&eacute;bogage
- [Style de code](docs/development/code-style.mdx) &mdash; SwiftLint, SwiftFormat et conventions
- [Changelog](CHANGELOG.md) &mdash; travaux non publi&eacute;s et historique des versions tagu&eacute;es

## Contribuer

Toutes les contributions sont les bienvenues &mdash; code, tests, documentation, rapports de bugs et retours UX.

Consultez **[CONTRIBUTING.md](CONTRIBUTING.md)** pour les instructions de configuration, le style de code et la checklist PR compl&egrave;te.

Les issues pour d&eacute;butants sont &eacute;tiquet&eacute;es [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). En soumettant une PR, vous acceptez le [CLA](CLA.md).

## Sponsors et Partenaires

Rockxy est construit et maintenu par des d&eacute;veloppeurs ind&eacute;pendants. Les sponsorisations financent le d&eacute;veloppement continu, les audits de s&eacute;curit&eacute; et les nouvelles fonctionnalit&eacute;s.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsoriser_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsoriser Rockxy" />
  </a>
</p>

Rockxy est h&eacute;berg&eacute; fiscalement par [Open Source Collective](https://docs.oscollective.org/). Les contributions et les d&eacute;penses du projet sont enregistr&eacute;es sur la [page Open Collective publique de Rockxy](https://opencollective.com/rockxy), offrant une vue transparente de la r&eacute;ception et de l'utilisation des fonds.

| Niveau | Contribution | Ce que cela soutient |
|--------|--------------|----------------------|
| **Backer** | &Agrave; partir de 5 $/mois | Maintenance open source, documentation, tests et versions |
| **Builder** | &Agrave; partir de 25 $/mois | Tests de r&eacute;gression, am&eacute;liorations des performances et workflows de d&eacute;bogage quotidiens |
| **Sponsor** | 100 $/mois | Maintenance &agrave; long terme d'un outil ax&eacute; sur la confidentialit&eacute; et gratuit pour les d&eacute;veloppeurs |
| **Sustaining Sponsor** | 500 $/mois | Maintenance et d&eacute;veloppement produit cibl&eacute;s, y compris l'automatisation des versions et le support des protocoles |

**Demandes de partenariat** &mdash; entreprises d'outils de d&eacute;veloppement, soci&eacute;t&eacute;s de s&eacute;curit&eacute; et &eacute;quipes entreprise cherchant des int&eacute;grations personnalis&eacute;es ou des solutions en marque blanche : [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Support

- [Open Collective](https://opencollective.com/rockxy/donate) &mdash; contribuer &agrave; Rockxy via son budget de projet transparent
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) &mdash; soutenir le d&eacute;veloppement de Rockxy
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) &mdash; rapports de bugs et demandes de fonctionnalit&eacute;s
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) &mdash; questions et discussions communautaires
- **Email** &mdash; [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Probl&egrave;mes de s&eacute;curit&eacute;** &mdash; voir [SECURITY.md](SECURITY.md) pour la divulgation responsable

## Licence

[GNU Affero General Public License v3.0](LICENSE) &mdash; Copyright 2024&ndash;2026 Rockxy Contributors.

## Historique des Étoiles

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Construit avec Swift, SwiftNIO, SwiftUI et AppKit.</sub>
</p>
