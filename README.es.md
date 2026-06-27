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
  <strong>El proxy de depuración open-source y auditable para macOS.</strong>
</p>

<p align="center">
  Intercepta, inspecciona y modifica tráfico HTTP/HTTPS/WebSocket/GraphQL con una app Swift nativa que puedes auditar, compilar y confiar.<br>
  Construido para workflows de depuración de API, mobile, MCP-assisted, AI y la era blockchain mientras Rockxy evoluciona.<br>
  Una alternativa local-first, AGPL-3.0 a <a href="#rockxy-vs-alternativas">Proxyman y Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Plataforma" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Licencia" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs bienvenidas" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Light.png" alt="Rockxy ejecutándose en macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Último Release Etiquetado

**v0.27.2** — 2026-06-18

### Cambios

- Mejora los controles de privacidad de metadatos
- Refina el layout de disclosure de metadatos

Consulta [CHANGELOG.md](CHANGELOG.md) para el historial completo.
<!-- END GENERATED: latest-release -->

## Highlights de la Rama Actual

- Upstream Proxy ahora incluye Automatic Proxy Configuration free/core con PAC URL routing para rutas `DIRECT`, HTTP y HTTPS, preservando los límites existentes de SOCKS5 y política de autenticación.
- Los workflows de exportación ahora cubren OpenAPI YAML/HTML y publicación de tráfico seleccionado en Gist con construcción de payload redaction-aware.
- Las herramientas del Inspector ahora incluyen filtros JSONPath/key/value y previews rápidos para texto de payload seleccionado, como JWTs.
- Node.js Developer Setup ahora replica el cliente seleccionado durante la validación y tiene una guía localhost más completa.
- Developer Setup Hub ahora cubre runtimes, navegadores, clientes, dispositivos, frameworks y entornos con snippets por target, validation watchers y guías honestas.
- El trabajo de WebSocket Protobuf continúa como parte de la dirección de Rockxy hacia inspección de protocolos más rica.
- La planificación pública del roadmap ahora incluye depuración protocol-aware para tráfico AI, flows Web3/RPC, payment flows estilo x402 y evidence sharing redactado más seguro.

## Funcionalidades

Las herramientas que buscas cuando Browser DevTools ya no alcanza. Depuración central de tráfico para trabajo Mac e iOS: nativa en macOS, con releases públicas y workflow local-first.

### Captura de Tráfico

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Inspecciona tráfico HTTP, HTTPS, WebSocket y GraphQL desde cualquier app Mac, CLI o dispositivo iOS. Browser DevTools termina en el navegador; Rockxy ve el resto de tu stack.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Filtros y Búsqueda Avanzada

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Reduce miles de requests capturados en segundos. Combina filtros por method, host, status, header, body y process, o ejecuta full-text search en toda la sesión.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### MCP Server para AI Assistants

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Permite que Claude Desktop o Cursor lean tu tráfico capturado mediante un MCP server local. Pregunta "¿por qué esto devolvió 500?" en vez de pegar headers en un chat. Local, redaction-aware y open source.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Copia snippets de proxy para Python, Node.js, Go, Rust, cURL, Docker y navegadores, luego pulsa Run Test para confirmar que el tráfico realmente fluye.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Gestión de Certificados para HTTPS Debugging

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Una root CA P-256 ECDSA generada en el primer launch y sellada en tu Keychain. Descifra HTTPS al primer intento; los hosts con pinning pasan automáticamente.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL Proxy y Descifrado HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Elige qué hosts se descifran con TLS. El tráfico descifrado muestra headers y JSON reales; el resto pasa cifrado. Las reglas wildcard permiten scope por dominio en un clic.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Omite hosts específicos para que apps con certificate pinning, servicios internos o telemetría ruidosa nunca entren en la captura.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Haz fallar cualquier host. Corta ad networks, trackers o una dependencia inestable para ver cómo se degrada tu app sin cambiar código.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Sirve un archivo guardado o un árbol de directorios en lugar de una respuesta real. Cambia un JSON, repite un snapshot o fija una API flaky a una copia local mientras depuras.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Reescribe el destino de un request capturado sin tocar el código de la app ni `/etc/hosts`. Manda tráfico de producción a staging, a tu dev server o a la máquina de un colega.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Breakpoints y Reglas

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Pausa un request o response, edita method, headers, body o status y continúa. La forma rápida de probar "¿qué pasa si la API devuelve 401?" sin tocar backend.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Modificar Headers

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Agrega, elimina o reemplaza headers en cualquier host sin redeploy. Prueba CORS, auth o cache en segundos con presets integrados.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Custom Request & Response Headers

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Sobrescribe headers por host con control completo de ambas fases. Inyecta auth tokens, elimina Set-Cookie o fija un User-Agent personalizado como reglas nombradas.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Condiciones de Red

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Limita a 3G, EDGE, LTE, WiFi o una latencia custom. Tu laptop está en fibra; tus usuarios no. Mira la UX a 400 ms RTT antes que ellos.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — Editar y Repetir

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Reconstruye cualquier request HTTP capturado, cambia method, URL, headers, query params o body, y vuelve a enviarlo sin salir de Rockxy. Itera prompts LLM, prueba límites de auth o reproduce fallos de endpoints OpenAI, Anthropic y Cohere en segundos.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Compare

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Pon dos responses capturadas lado a lado y detecta cada campo que cambió: status, headers, JSON keys y bytes del body. Encuentra regresiones silenciosas de API, outputs LLM no deterministas y prompt drift sin enviar datos a un diff de terceros.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Custom Previewer Tabs

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Renderiza request y response bodies como quieras. Fija tabs extra para JSON, GraphQL, JWT, imagen o tu propio formato, reutilizables en cada request capturado.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sesiones y Export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Guarda sesiones, importa/exporta HAR, copia cualquier request como cURL o JSON. Redacta authorization headers, cookies y bearer tokens antes de compartir.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Workspaces Multi-Tab

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

Ejecuta sesiones de captura independientes lado a lado: una tab para staging, otra para prod y otra para el build de iOS device.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript Scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

Hooks JS en requests y responses para casos que una regla estática no cubre: redactar PII, firmar tokens, reescribir payloads. Los errores aparecen inline sin corromper tráfico.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Más Funciones Próximamente

Las funcionalidades futuras se rastrean públicamente y se publican solo cuando la implementación, tests, privacidad y documentación están listas.

### AI Traffic Inspection `Próximamente`

Haz que el tráfico de modelos sea más fácil de depurar dentro del workflow normal de captura. Detecta requests AI, inspecciona model calls seleccionados, diagnostica streaming responses, compara prompt/output behavior y entiende tool-call chains sin pegar payloads sensibles en otro servicio.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Web3/RPC Inspection `Próximamente`

Convierte llamadas de red blockchain-era en evidence de depuración legible. Inspecciona JSON-RPC y Solana RPC traffic, agrupa llamadas relacionadas en flows, explica errores RPC comunes y replay selected requests sin convertir Rockxy en wallet o block explorer.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### x402 Payment Flow Debugging `Próximamente`

Entiende payment-gated HTTP flows desde la capa de red. Resalta payment-required responses, sigue el retry path y mantiene la evidence local y redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### Redacted Evidence Bundles `Próximamente`

Comparte los hechos necesarios para reproducir un bug sin filtrar secretos. Empaqueta selected traffic con protocol summaries, redaction previews y source-backed context auditable.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Protocol-Aware Filters & Rules `Próximamente`

Usa metadata AI y Web3 donde Rockxy ya trabaja: filters, badges, optional columns, comparison, rules, Developer Setup y local MCP summaries.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Team Sharing & Collaboration `Próximamente`

Envía una sesión capturada a un compañero con un clic. Anota requests fallidos inline, ve quién mira qué en tiempo real y pair-debuggea tráfico HTTPS sin compartir pantalla.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% macOS nativo. Sin Electron. Sin web views. SwiftUI + AppKit + SwiftNIO.

## Quick Start

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Compila y ejecuta en Xcode. La ventana Welcome te guía por la configuración de root CA, instalación del helper y activación del proxy.

**Requisitos:** macOS 14.0+, Xcode 16+, Swift 5.9

Si quieres conectar Rockxy a un cliente MCP local tras instalarlo, consulta la [guía de integración MCP](docs/features/mcp.mdx).

## Rockxy vs. Alternativas

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Modelo de proyecto** | Proyecto open-source AGPL-3.0 | App comercial propietaria | App comercial propietaria |
| **Código fuente** | Público, auditable, forkable | Cerrado | Cerrado |
| **Compilar desde source** | Gratis con Xcode desde este repo | No disponible desde source público | No disponible desde source público |
| **Base macOS nativa** | Swift + SwiftNIO + SwiftUI/AppKit | App macOS comercial nativa | App comercial multiplataforma |
| **Captura local-first** | Proxy, certificados, helper y datos quedan en tu Mac | App desktop proxy | App desktop proxy |
| **Developer setup workflow** | Developer Setup Hub integrado para runtimes, clients, devices, frameworks y environments | Guías específicas del producto | Guías específicas del producto |
| **External proxy + PAC routing** | HTTP/HTTPS upstream proxy, PAC auto-configuration y bypass rules | Tooling proxy comercial maduro | Tooling proxy comercial maduro |
| **MCP/local automation bridge** | Integrado, token-authenticated, redaction por defecto | No declarado en docs públicas revisadas | No declarado en docs públicas revisadas |
| **Ruta de contribución abierta** | Issues, discussions, roadmap y PRs públicos | Producto controlado por vendor | Producto controlado por vendor |

En el roadmap: workflows replay/diff/rules/scripting más profundos, mejor inspección WebSocket y GraphQL, depuración protocol-aware AI y Web3/RPC, visibilidad de payment flows estilo x402, y exploración de gRPC/Protobuf más HTTP/2 y HTTP/3.

## Seguridad

Rockxy intercepta tráfico de red: la seguridad es fundacional, no opcional.

- El helper XPC valida callers mediante **comparación de certificate-chain**, no solo bundle ID
- Los plugins corren en **JavaScriptCore sandboxed** con timeout de 5 segundos, sin acceso a filesystem/network
- **Validación de input** en todos los boundaries: caps de body size, URI limits, regex DoS protection, path traversal prevention
- Credenciales **automáticamente redactadas** en logs capturados
- Archivos sensibles guardados con permisos **0o600**

Reporta vulnerabilidades mediante [SECURITY.md](SECURITY.md). Consulta la [arquitectura de seguridad completa](docs/development/security.mdx).

## Roadmap

El roadmap público de Rockxy está orientado a workflows y no tiene fechas fijas. Se enfoca en confiabilidad, UX macOS nativa, debugging workflows, protocol support, visibilidad de tráfico AI/Web3-era, documentación y onboarding de contributors.

- [ROADMAP.md](ROADMAP.md): dirección pública de ingeniería de alto nivel
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): visibilidad operacional para issues del roadmap

## Documentación

Documentación completa en [Rockxy Docs](docs/index.mdx):

- [Quickstart Guide](docs/quickstart.mdx) — empieza en minutos
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — snippets por runtime, device guides, validation probes y support matrix
- [MCP Integration](docs/features/mcp.mdx) — conecta Rockxy a clientes MCP locales
- [Architecture](docs/development/architecture.mdx) — proxy engine, actor model, data flow
- [Security Model](docs/development/security.mdx) — trust boundaries, XPC validation, certificate management
- [Design Decisions](docs/development/design-decisions.mdx) — por qué SwiftNIO, NSTableView, actors
- [Building from Source](docs/development/building.mdx) — build, test, lint y debug
- [Code Style](docs/development/code-style.mdx) — SwiftLint, SwiftFormat y convenciones
- [Changelog](CHANGELOG.md) — trabajo unreleased y releases etiquetados

## Contribuir

Contribuciones bienvenidas: código, tests, docs, bug reports y feedback UX.

Consulta **[CONTRIBUTING.md](CONTRIBUTING.md)** para setup, code style y checklist PR.

Los issues para empezar están etiquetados como [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Al abrir un PR, aceptas el [CLA](CLA.md).

## Sponsors & Partners

Rockxy es construido y mantenido por desarrolladores independientes. Los sponsorships financian desarrollo continuo, auditorías de seguridad y nuevas funciones.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

| Tier | Beneficios |
|------|------------|
| **Gold Sponsor** | Logo en README + docs site, feature requests prioritarios, canal de soporte directo |
| **Silver Sponsor** | Logo en README, agradecimiento en release notes |
| **Bronze Sponsor** | Agradecimiento en README y docs |
| **Partner** | Co-desarrollo, soporte de integración, early access a próximas funciones |

**Consultas de partnership** — empresas de developer tools, firmas de seguridad y equipos enterprise que buscan integraciones custom o soluciones white-label: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Soporte

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — apoya el desarrollo de Rockxy
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — bug reports y feature requests
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — preguntas y comunidad
- **Email** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Security issues** — consulta [SECURITY.md](SECURITY.md) para responsible disclosure

## Licencia

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
  <sub>Hecho por <a href="https://github.com/LocNguyenHuu">Stephen</a>. Construido con Swift, SwiftNIO, SwiftUI y AppKit.</sub>
</p>
