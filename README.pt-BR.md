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
  <strong>O proxy de debug open-source e auditável para macOS.</strong>
</p>

<p align="center">
  Intercepte, inspecione e modifique tráfego HTTP/HTTPS/WebSocket/GraphQL com um app Swift nativo que você pode auditar, compilar e confiar.<br>
  Feito para workflows de debug de API, mobile, MCP-assisted, AI e da era blockchain enquanto o Rockxy evolui.<br>
  Uma alternativa local-first, AGPL-3.0 ao <a href="#rockxy-vs-alternativas">Proxyman e Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Plataforma" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Licença" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs bem-vindos" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy rodando no macOS" width="800" />
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

## Destaques da Branch Atual

- AI Assistant oferece análise local ou com Ollama/provider após Review Data; a sidebar inclui Focus Sets e Noise Control; o workspace usa split views nativas; e a inspeção AI/Web3/x402 agora é comportamento atual.
- Upstream Proxy agora inclui Automatic Proxy Configuration free/core com PAC URL routing para rotas `DIRECT`, HTTP e HTTPS, preservando os limites existentes de SOCKS5 e política de autenticação.
- Os workflows de export agora cobrem OpenAPI YAML/HTML e publicação de tráfego selecionado no Gist com construção de payload redaction-aware.
- As ferramentas do Inspector agora incluem filtros JSONPath/key/value e previews rápidos para texto de payload selecionado, como JWTs.
- Node.js Developer Setup agora espelha o client selecionado durante a validação e tem um guia localhost mais completo.
- Developer Setup Hub agora cobre runtimes, browsers, clients, devices, frameworks e environments com snippets por target, validation watchers e guias honestos.
- A inspeção de frames binários WebSocket agora inclui heurísticas Protobuf wire-format limitadas e sob demanda, sem adicionar decoder work ao capture hot path.
- O roadmap público agora se concentra em regras protocol-aware mais profundas, replay, comparação e compartilhamento mais seguro de evidence redigida.

## Funcionalidades

As ferramentas que você procura quando Browser DevTools já não basta. Debug de tráfego essencial para trabalho Mac e iOS: nativo no macOS, com releases públicas e workflow local-first.

### Captura de Tráfego

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Inspecione tráfego HTTP, HTTPS, WebSocket e GraphQL de qualquer app Mac, CLI ou dispositivo iOS. Browser DevTools para no navegador; Rockxy vê o resto da sua stack.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Filtro e Busca Avançados

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Reduza milhares de requests capturados em segundos. Combine filtros por method, host, status, header, body e process, ou rode full-text search na sessão inteira.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets e Noise Control

Transforme investigações recorrentes em scopes reutilizáveis na sidebar. Focus Sets combina includes por app, domain e path com excludes por domain/path, persiste entre execuções e fica disponível em todo workspace. Noise Control continua capturando telemetria e tráfego de baixo valor, mas os esconde no workspace atual.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant explicando tráfego selecionado ao lado da tabela de requests e da sidebar nativas" width="820" />

Selecione uma ou mais requests capturadas e pergunte o que aconteceu, o que falhou, o que mudou ou o que verificar depois. O Rockxy começa com análise baseada em evidências neste Mac; um modelo Ollama ou provider configurado só roda depois que Review Data mostra o contexto exato, limitado e redigido. As respostas podem revelar a request de origem e preparar workflows nativos de follow-up, mas nunca alteram tráfego nem executam ações automaticamente.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Leia o guia do AI Assistant](docs/features/ai-assistant.mdx).

### MCP Server para clients AI externos

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Deixe Claude Desktop ou Cursor lerem seu tráfego capturado por um MCP server local. Pergunte "por que isso retornou 500?" em vez de colar headers no chat. Local, redaction-aware e open source.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Copie snippets de proxy para Python, Node.js, Go, Rust, cURL, Docker e browsers, depois clique em Run Test para confirmar que o tráfego está fluindo.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Gerenciamento de Certificados para HTTPS Debugging

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Uma root CA P-256 ECDSA gerada no primeiro launch e selada no seu Keychain. Decifre HTTPS na primeira tentativa; hosts com pinning passam automaticamente.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL Proxy e Decriptação HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Escolha quais hosts recebem TLS decryption. O tráfego decriptado mostra headers e JSON reais; o resto passa criptografado. Regras wildcard permitem scope por domínio em um clique.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Pule hosts específicos para que apps com certificate pinning, serviços internos ou telemetria barulhenta nunca entrem na captura.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Faça qualquer host falhar. Corte ad networks, trackers ou uma dependência instável para ver como sua app degrada sem mudar código.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Sirva um arquivo salvo ou uma árvore de diretórios no lugar de uma resposta real. Troque um JSON, repita um snapshot ou fixe uma API flaky em uma cópia local enquanto debuga.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Reescreva o destino de um request capturado sem tocar no código da app nem em `/etc/hosts`. Aponte tráfego de produção para staging, seu dev server ou a máquina de um colega.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Breakpoints e Regras

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Pause um request ou response, edite method, headers, body ou status e continue. O jeito rápido de testar "e se a API retornar 401?" sem tocar no backend.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Modificar Headers

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Adicione, remova ou substitua headers em qualquer host sem redeploy. Teste CORS, auth ou cache em segundos com presets integrados.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Custom Request & Response Headers

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Sobrescreva headers por host com controle total das duas fases. Injete auth tokens, remova Set-Cookie ou fixe um User-Agent customizado como regras nomeadas.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Condições de Rede

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Limite para 3G, EDGE, LTE, WiFi ou uma latência customizada. Seu laptop está na fibra; seus usuários não. Veja a UX a 400 ms RTT antes deles.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — Editar e Repetir

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Reconstrua qualquer request HTTP capturado, mude method, URL, headers, query params ou body, e reenvie sem sair do Rockxy. Itere prompts LLM, teste limites de auth ou reproduza falhas em endpoints OpenAI, Anthropic e Cohere em segundos.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Compare

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Coloque duas responses capturadas lado a lado e encontre cada campo que mudou: status, headers, JSON keys e bytes do body. Pegue regressões silenciosas de API, outputs LLM não determinísticos e prompt drift sem mandar dados para diff de terceiros.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Custom Previewer Tabs

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Renderize request e response bodies do seu jeito. Fixe tabs extras para JSON, GraphQL, JWT, imagem ou seu próprio formato, reutilizáveis em cada request capturado.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sessões e Export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Salve sessões, importe/exporte HAR, copie qualquer request como cURL ou JSON. Redija authorization headers, cookies e bearer tokens antes de compartilhar.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Workspaces Multi-Tab

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Workspaces multi-tab do Rockxy com views filtradas de forma independente sobre a mesma captura ao vivo" width="820" />

Mantenha views de investigação independentes lado a lado sobre a mesma captura ao vivo. Cada tab preserva filtros, ordenação, seleção, scope da sidebar e estado do inspector, compartilhando o proxy e as transações capturadas.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript Scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

Hooks JS em requests e responses para casos que uma regra estática não cobre: redigir PII, assinar tokens, reescrever payloads. Erros aparecem inline sem corromper tráfego.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Inspeção Consciente de Protocolo

O Rockxy oferece inspeção consciente de protocolo para AI, Web3 RPC e x402 no workflow normal de debug HTTP.

### AI Traffic Inspection

Torne model traffic mais fácil de debugar dentro do workflow normal de captura. Detecte AI requests, inspecione model calls selecionados, diagnostique streaming responses, compare prompt/output behavior e entenda tool-call chains sem colar payloads sensíveis em outro serviço.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC Inspection

Inspecione tráfego HTTP JSON-RPC estilo EVM e Solana com provider host, request ID, method, batch summary, error, chain, transaction, payload e debug intent, sem transformar o Rockxy em wallet ou block explorer.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 Payment Flow Hints

Entenda payment-gated HTTP flows pela camada de rede. Destaque payment-required responses, siga o retry path e mantenha a evidence local e redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Trabalho Futuro

As seções seguintes descrevem uma direção pública, não o comportamento atual.

### Redacted Evidence Bundles `Em Breve`

Compartilhe os fatos necessários para reproduzir um bug sem vazar secrets. Empacote selected traffic com protocol summaries, redaction previews e source-backed context auditável.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Protocol-Aware Rules

Use metadata AI e Web3 onde Rockxy já trabalha: filters, badges, optional columns, comparison, rules, Developer Setup e local MCP summaries.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Team Sharing & Collaboration `Em Breve`

Envie uma sessão capturada para um colega com um clique. Anote requests com falha inline, veja quem está olhando o quê em tempo real e faça pair-debug de tráfego HTTPS sem compartilhar tela.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% macOS nativo. Sem Electron. Sem web views. SwiftUI + AppKit + SwiftNIO.

## Quick Start

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Compile e rode no Xcode. A janela Welcome guia você pela configuração da root CA, instalação do helper e ativação do proxy.

**Requisitos:** macOS 14.0+, Xcode 16+, Swift 5.9

Se quiser conectar Rockxy a um client MCP local após a instalação, veja o [guia de integração MCP](docs/features/mcp.mdx).

## Rockxy vs. Alternativas

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Modelo de projeto** | Projeto open-source AGPL-3.0 | App comercial proprietário | App comercial proprietário |
| **Código-fonte** | Público, auditável, forkable | Fechado | Fechado |
| **Compilar do source** | Grátis com Xcode a partir deste repo | Não disponível por source público | Não disponível por source público |
| **Base macOS nativa** | Swift + SwiftNIO + SwiftUI/AppKit | App macOS comercial nativo | App comercial multiplataforma |
| **Captura local-first** | Proxy, certificados, helper e dados ficam no seu Mac | App desktop proxy | App desktop proxy |
| **Developer setup workflow** | Developer Setup Hub integrado para runtimes, clients, devices, frameworks e environments | Guias específicos do produto | Guias específicos do produto |
| **External proxy + PAC routing** | HTTP/HTTPS upstream proxy, PAC auto-configuration e bypass rules | Tooling proxy comercial maduro | Tooling proxy comercial maduro |
| **MCP/local automation bridge** | Integrado, token-authenticated, redaction por padrão | Não declarado em docs públicas revisadas | Não declarado em docs públicas revisadas |
| **Caminho aberto de contribuição** | Issues, discussions, roadmap e PRs públicos | Produto controlado por vendor | Produto controlado por vendor |

No roadmap: regras protocol-aware mais profundas, bundles de evidência redigida mais seguros, workflows de replay e comparação mais fortes, guias de Developer Setup mais amplos e pesquisa contínua sobre HTTP/2 e HTTP/3.

## Segurança

Rockxy intercepta tráfego de rede: segurança é fundação, não opcional.

- O helper XPC valida callers por **comparação de certificate-chain**, não só bundle ID
- Plugins rodam em **JavaScriptCore sandboxed** com timeout de 5 segundos, sem acesso a filesystem/network
- **Validação de input** em todos os boundaries: caps de body size, URI limits, regex DoS protection, path traversal prevention
- Credenciais são **automaticamente redigidas** em logs capturados
- Arquivos sensíveis salvos com permissões **0o600**

Reporte vulnerabilidades via [SECURITY.md](SECURITY.md). Veja a [arquitetura de segurança completa](docs/development/security.mdx).

## Roadmap

O roadmap público do Rockxy é orientado a workflows e sem datas fixas. Ele foca em confiabilidade, UX macOS nativa, debugging workflows, protocol support, visibilidade de tráfego AI/Web3-era, documentação e onboarding de contributors.

- [ROADMAP.md](ROADMAP.md): direção pública de engenharia em alto nível
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): visibilidade operacional para issues do roadmap

## Documentação

Documentação completa em [Rockxy Docs](docs/index.mdx):

- [Quickstart Guide](docs/quickstart.mdx) — comece em minutos
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — snippets por runtime, device guides, validation probes e support matrix
- [AI Assistant](docs/features/ai-assistant.mdx) — investigue tráfego selecionado localmente ou com um modelo configurado após Review Data
- [Filtros e busca](docs/core-features/filters-and-search.mdx) — scopes da sidebar, Focus Sets, Noise Control, filtros do toolbar e busca
- [Inspeção AI e Web3](docs/features/ai-web3-inspection.mdx) — inspecione tráfego reconhecido de model API, JSON-RPC e x402
- [MCP Integration](docs/features/mcp.mdx) — conecte Rockxy a clients MCP locais
- [Architecture](docs/development/architecture.mdx) — proxy engine, actor model, data flow
- [Security Model](docs/development/security.mdx) — trust boundaries, XPC validation, certificate management
- [Design Decisions](docs/development/design-decisions.mdx) — por que SwiftNIO, NSTableView, actors
- [Building from Source](docs/development/building.mdx) — build, test, lint e debug
- [Code Style](docs/development/code-style.mdx) — SwiftLint, SwiftFormat e convenções
- [Changelog](CHANGELOG.md) — trabalho unreleased e releases taggeadas

## Contribuindo

Contribuições são bem-vindas: código, tests, docs, bug reports e feedback UX.

Veja **[CONTRIBUTING.md](CONTRIBUTING.md)** para setup, code style e checklist PR.

Issues para começar são marcadas como [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Ao abrir um PR, você concorda com o [CLA](CLA.md).

## Sponsors & Partners

Rockxy é construído e mantido por desenvolvedores independentes. Sponsorships financiam desenvolvimento contínuo, auditorias de segurança e novas funcionalidades.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy é hospedado fiscalmente pela [Open Source Collective](https://docs.oscollective.org/). As contribuições e despesas do projeto são registradas na [página pública do Rockxy no Open Collective](https://opencollective.com/rockxy), oferecendo uma visão transparente de como os recursos são recebidos e utilizados.

| Nível | Contribuição | O que apoia |
|-------|-------------|-------------|
| **Backer** | A partir de US$ 5/mês | Manutenção open source, documentação, testes e releases |
| **Builder** | A partir de US$ 25/mês | Testes de regressão, melhorias de desempenho e workflows diários de depuração |
| **Sponsor** | US$ 100/mês | Manutenção de longo prazo de uma ferramenta focada em privacidade e gratuita para desenvolvedores |
| **Sustaining Sponsor** | US$ 500/mês | Manutenção e desenvolvimento de produto focados, incluindo automação de releases e suporte a protocolos |

**Consultas de partnership** — empresas de developer tools, firmas de segurança e times enterprise buscando integrações customizadas ou soluções white-label: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Suporte

- [Open Collective](https://opencollective.com/rockxy/donate) — contribua com o Rockxy por meio de seu orçamento de projeto transparente
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — apoie o desenvolvimento do Rockxy
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — bug reports e feature requests
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — perguntas e comunidade
- **Email** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Security issues** — veja [SECURITY.md](SECURITY.md) para responsible disclosure

## Licença

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## Star History

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Feito por <a href="https://github.com/LocNguyenHuu">Stephen</a>. Construído com Swift, SwiftNIO, SwiftUI e AppKit.</sub>
</p>
