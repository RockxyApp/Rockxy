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
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/26380?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-26380" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/26380/daily?language=Swift" alt="RockxyApp/Rockxy | Trendshift" width="250" height="55" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy ejecutándose en macOS" width="800" />
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

## Highlights de la Rama Actual

- AI Assistant ahora investiga una o más requests seleccionadas con análisis local integrado, modelos Ollama o provider configurados opcionales, confirmación explícita de Review Data, redacción acotada, respuestas en streaming, revelación de evidencia y handoffs iniciados por el usuario.
- El sidebar nativo ahora incluye Focus Sets reutilizables para scopes de app/domain/path más Noise Control por workspace que oculta domains o paths coincidentes sin detener la captura.
- El workspace principal ahora usa split views nativas verticales y horizontales para el Context Dock y el inspector inferior, preservando divisores de altura completa, separadores de toolbar/footer coordinados y redimensionamiento automático del layout.
- Upstream Proxy ahora incluye Automatic Proxy Configuration free/core con PAC URL routing para rutas `DIRECT`, HTTP y HTTPS, preservando los límites existentes de SOCKS5 y política de autenticación.
- Los workflows de exportación ahora cubren OpenAPI YAML/HTML y publicación de tráfico seleccionado en Gist con construcción de payload redaction-aware.
- Las herramientas del Inspector ahora incluyen filtros JSONPath/key/value y previews rápidos para texto de payload seleccionado, como JWTs.
- La inspección de tráfico AI y Web3 ahora añade etiquetas de protocolo, tabs del inspector y resúmenes de debug para model calls reconocidos, tráfico JSON-RPC y hints de pago estilo x402.
- Node.js Developer Setup ahora replica el cliente seleccionado durante la validación y tiene una guía localhost más completa.
- Developer Setup Hub ahora cubre runtimes, navegadores, clientes, dispositivos, frameworks y entornos con snippets por target, validation watchers y guías honestas.
- La inspección de frames binarios WebSocket ahora incluye heurísticas Protobuf wire-format acotadas y bajo demanda, sin añadir decoder work al capture hot path.
- El roadmap público ahora se centra en reglas protocol-aware más profundas, replay, comparación y evidence sharing redactado más seguro.

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

### Focus Sets y Noise Control

Convierte investigaciones recurrentes en scopes reutilizables del sidebar. Focus Sets combina inclusiones por app, domain y path con exclusiones por domain/path, persiste entre lanzamientos y está disponible en cada workspace. Noise Control sigue capturando telemetría y tráfico de poco valor, pero los oculta en el workspace actual.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant explicando tráfico seleccionado junto a la tabla de requests y el sidebar nativos" width="820" />

Selecciona una o más requests capturadas y pregunta qué pasó, qué falló, qué cambió o qué verificar después. Rockxy comienza con análisis basado en evidencia en este Mac; un modelo Ollama o provider configurado solo se ejecuta después de que Review Data muestre el contexto exacto, acotado y redactado. Las respuestas pueden revelar la request de origen y preparar workflows de seguimiento nativos, pero nunca modifican tráfico ni ejecutan acciones automáticamente.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Lee la guía de AI Assistant](docs/features/ai-assistant.mdx).

### MCP Server para clientes AI externos

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Permite que Claude Desktop o Cursor inspeccionen tu tráfico capturado mediante diez herramientas de solo lectura en el MCP server local de Rockxy. Pregunta "¿por qué esto devolvió 500?" en vez de pegar headers en un chat. La implementación es open source, con autenticación por token y mantiene la redacción de datos sensibles activada por defecto.

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

Omite hosts específicos para que apps con certificate pinning, servicios internos o telemetría ruidosa nunca entren en la captura. Los wildcards mantienen la lista corta y tu request log centrado en lo que realmente te importa.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Haz fallar cualquier host. Corta ad networks, trackers de terceros o una dependencia inestable para ver cómo se degrada tu app cuando desaparece, sin cambiar una línea de código.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Sirve un archivo guardado o un árbol de directorios en lugar de una respuesta real. Cambia un JSON, repite un snapshot o fija una API flaky a una copia local mientras depuras.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Reescribe el destino de un request capturado sin tocar el código de la app ni `/etc/hosts`. Manda tráfico de producción a staging, a tu dev server o a la máquina de un colega para un repro de bug reproducible.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Promueve cualquier header de request o response a una columna de primera clase en la tabla de tráfico. Mantén separadas las fuentes de request y response, guarda los headers que te importan y luego escanea request IDs, trace IDs, estado de cache o metadata personalizada sin abrir cada inspector.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Condiciones de Red

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Limita a 3G, EDGE, LTE, WiFi o una latencia custom. Tu laptop está en fibra; tus usuarios no. Mira la UX a 400 ms RTT antes que ellos.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — Editar y Repetir

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Reconstruye cualquier request HTTP capturado, cambia method, URL, headers, query params o body, y vuelve a enviarlo sin salir de Rockxy. Sin el bucle de copiar y pegar de Postman, Insomnia o curl. Itera prompts LLM, prueba límites de auth o reproduce fallos de endpoints OpenAI, Anthropic y Cohere en segundos.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Compare

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Apila dos transacciones capturadas o payloads pegados lado a lado y detecta cada campo que cambió: status, headers, JSON keys o bytes del body. Encuentra regresiones silenciosas de API, outputs LLM no deterministas y prompt drift sin enviar nada a un diff de terceros.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Custom Previewer Tabs

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Renderiza request y response bodies como quieras. Fija tabs extra para JSON, GraphQL, JWT, imagen o tu propio formato, reutilizables en cada request capturado.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sesiones y Export

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Guarda sesiones, importa/exporta HAR para el traspaso entre herramientas, copia cualquier request como cURL o JSON. Redacta authorization headers, cookies y bearer tokens antes de compartir: entrega a un compañero un repro de bug funcional sin filtrar secretos.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Workspaces Multi-Tab

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Workspaces multi-tab de Rockxy con vistas filtradas de forma independiente sobre la misma captura en vivo" width="820" />

Mantén vistas de investigación independientes lado a lado sobre la misma captura en vivo: un tab para tráfico de staging, otro para producción y otro para un flujo de dispositivo iOS. Cada tab conserva sus filtros, orden, selección, scope del sidebar y estado del inspector, mientras comparte el proxy y las transacciones capturadas.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript Scripting

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

Hooks JS en requests y responses para casos que una regla estática no cubre: redactar PII, firmar tokens, reescribir payloads. Los errores aparecen inline sin corromper tráfico.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Inspección Consciente del Protocolo

Rockxy ofrece inspección consciente del protocolo para AI, Web3 RPC y x402 dentro del workflow normal de depuración HTTP.

### AI Traffic Inspection

Rockxy detecta requests AI reconocidas dentro del workflow normal de captura. Inspecciona model calls seleccionados, estado de streaming, campos de usage cuando están presentes, warnings, retrieval hints y resúmenes de tool-call sin pegar payloads sensibles en otro servicio.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC Inspection

Rockxy convierte las llamadas de red de la era blockchain en evidencia de depuración legible. Inspecciona tráfico HTTP JSON-RPC estilo EVM y Solana con provider host, request ID, method, batch summary, error, chain, transaction, payload y debug intent, sin convertir Rockxy en wallet o block explorer.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 Payment Flow Hints

Rockxy resalta hints de payment-required y orientados a retry para que los flujos HTTP payment-gated sean comprensibles desde la capa de red, mientras la evidencia de depuración permanece local y redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Trabajo Futuro

Las siguientes secciones describen una dirección pública, no el comportamiento actual.

### Protocol-Aware Rules

Rockxy ya puede etiquetar e inspeccionar tráfico AI y Web3 hoy. El matching de reglas más profundo por model, tool call, JSON-RPC method, chain, transaction hash o batch subcall sigue siendo trabajo futuro; las herramientas actuales de modificación de tráfico aún hacen match por URL, HTTP method y headers.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Redacted Evidence Bundles `Próximamente`

Comparte los hechos necesarios para reproducir un bug sin filtrar secretos. Empaqueta selected traffic con protocol summaries, redaction previews y source-backed context auditable.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Team Sharing & Collaboration `Próximamente`

Envía una sesión capturada a un compañero con un clic. Anota requests fallidos inline, ve quién mira qué en tiempo real y pair-debuggea tráfico HTTPS sin compartir pantalla.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Shell de aplicación macOS nativo — sin Electron. SwiftUI + AppKit + SwiftNIO, con WebKit usado solo para la preview del body HTML.

## Quick Start

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Compila y ejecuta en Xcode. La ventana Welcome te guía por la configuración de root CA, instalación del helper y activación del proxy.

**Requisitos:** macOS 14.0+, Xcode 16+, Swift 5.9

Si quieres conectar Rockxy a un cliente MCP local tras instalarlo, consulta la [guía de integración MCP](docs/features/mcp.mdx).

## Rockxy frente a alternativas

La matriz principal cubre servidores proxy de depuración web de uso general. Pruebas de seguridad
suites e interceptores orientados al navegador/API con una superposición sustancial del flujo de trabajo
se enumeran por separado, por lo que los productos diferentes no se presentan como intercambiables.
Los analizadores de paquetes y los clientes exclusivos de API están fuera de esta comparación.

### Proxies de depuración web directa

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Forma del producto** | Proxy de depuración nativo de macOS | Aplicación nativa de macOS; Ediciones Windows/Linux basadas en Electron | Proxy de depuración de escritorio multiplataforma | CLI/TUI multiplataforma y kit de herramientas de proxy de interfaz de usuario web | Proxy de escritorio multiplataforma Electron y cliente HTTP | Proxy de depuración de escritorio multiplataforma |
| **Modelo de origen y construcción** | Fuente de la comunidad pública bajo AGPL-3.0-or-later; Construible con Xcode. El DMG oficial también contiene componentes posteriores no públicos | Fuente cerrada; no se identifica ninguna fuente de aplicación pública en los materiales oficiales revisados ​​| Fuente cerrada; no se identifica ninguna fuente de aplicación pública en los materiales oficiales revisados ​​| Fuente pública con licencia MIT; construible desde la fuente | Fuente de escritorio pública AGPL; edificable desde la fuente; los binarios publicados tienen opciones de licencia adicionales | Fuente cerrada; distribuido como código objeto bajo Fiddler Everywhere EULA |
| **Captura y configuración** | Proxy del sistema local con configuración guiada para aplicaciones, tiempos de ejecución, dispositivos iOS y simulador de Mac | Configuración automática para aplicaciones, tiempos de ejecución y dispositivos móviles de Mac | Proxy local con macOS, iOS y guías de configuración multiplataforma | Modos de captura regular, de proceso local, WireGuard, inverso, transparente y otros | Intercepción de proxy manual y dirigida para navegadores, tiempos de ejecución, contenedores y dispositivos móviles | Modos de captura de sistema, red, navegador, terminal, explícito y de dispositivo remoto |
| **Modificar y simular** | Puntos de interrupción, Map Local/Remote, reglas de encabezado, bloqueo y reglas de latencia | Puntos de interrupción, Map Local/Remote, listas de bloqueo, condiciones de red y reglas JavaScript | Puntos de interrupción, reescritura, Map Local/Remote, bloqueo y limitación | Map Local/Remote, modificación de cuerpo/encabezado, bloqueo y reproducción del servidor | Puntos de interrupción más reescritura, redirección, simulacro e inyección de errores basados ​​en reglas; parte de la automatización está limitada al plan | Reglas, puntos de interrupción, redirecciones, modificación de respuestas y burlas |
| **Reproducir y comparar** | Redactar/reproducir más solicitud local en paralelo, encabezado y comparación de cuerpo | Redactar, repetir y diferenciar | Repetir y editar solicitudes | Reproducción del lado del cliente y del lado del servidor | Cliente HTTP integrado para redactar y enviar solicitudes | API Compositor, reproducción de tráfico y comparación de tráfico documentados como versión beta |
| **Flujos de trabajo WebSocket** | Inspección de marco de texto/binario con heurística Protobuf acotada | Inspección WS/WSS; los scripts pueden modificar las URL/encabezados del protocolo de enlace, no los mensajes | La compatibilidad con WebSocket está documentada en el historial de versiones oficial | WebSocket interceptación y secuencias de comandos; La reproducción WebSocket no es compatible | Inspección WebSocket más reglas específicas de WebSocket | Captura e inspección WebSocket |
| **Secuencias de comandos y extensibilidad** | Ganchos JavaScriptCore en espacio aislado con un API acotado y tiempo de espera de ejecución | JavaScript secuencias de comandos de solicitud/respuesta | Reescribir reglas y una interfaz web de control; no se documenta ninguna característica general de secuencias de comandos JavaScript | Complementos Python y automatización de línea de comandos | Automatización basada en reglas más bibliotecas de fuentes públicas y proxy | Automatización basada en reglas; no se documenta ninguna característica de secuencias de comandos generales propia |
| **Enrutamiento ascendente** | [Proxy ascendente HTTP/HTTPS y enrutamiento URL PAC](docs/features/upstream-proxy.mdx); La política comunitaria deshabilita la autenticación de proxy y SOCKS5 y limita las reglas de omisión en tres | Enrutamiento externo HTTP/HTTPS/SOCKS y PAC con reglas de omisión | Proxies externos HTTP/HTTPS/SOCKS con reglas de autenticación y omisión | Modo ascendente HTTP/HTTPS más modos de escucha inverso y SOCKS | Configuraciones ascendentes del sistema, HTTP, HTTPS y SOCKS; se pueden aplicar límites del plan | Encadenamiento automático a servidores proxy del sistema más captura de proxy inverso |
| **AI y MCP** | [Asistente de IA en la aplicación](docs/features/ai-assistant.mdx) y [MCP local integrado](docs/features/mcp.mdx) con 10 herramientas de solo lectura, autenticación de token y redacción activadas de forma predeterminada | MCP integrado para clientes de IA externos, incluidas lecturas de tráfico y controles de aplicaciones/reglas | No documentado | No documentado | Un puente MCP local incluido está presente en la fuente oficial actual; no se documenta ningún asistente en la aplicación | MCP integrado más un asistente de depuración de nivel profesional cuya documentación actual requiere que los detalles del tráfico capturado se peguen en el chat |

### Herramientas de interceptación adyacentes

Estos productos se superponen significativamente con Rockxy pero lideran con pruebas de seguridad,
reglas del navegador o flujos de trabajo del cliente API en lugar del mismo propósito general
enfoque de proxy de depuración nativo.

| **Producto** | **Por qué es adyacente** | **Modelo de origen y construcción** | **Superposición relevante** | **AI y MCP** |
|---|---|---|---|---|
| **Burp Suite** | Suite de pruebas de seguridad web con un proxy interceptor | Aplicación de código cerrado; su EULA afirma que los usuarios no tienen derecho a la fuente de la aplicación. Las extensiones pueden utilizar licencias independientes | Intercepción de proxy y coincidencia/reemplazo, repetidor, WebSocket, proxy ascendente/SOCKS y un gran ecosistema de extensión | Burp AI está disponible en Repetidor; PortSwigger también mantiene una extensión de servidor público MCP para clientes externos de IA |
| **ZAP** | Escáner de seguridad y proxy de interceptación | Fuente pública Apache-2.0; construible desde la fuente | Intercepción/edición, reenvío manual, scripts y puntos de interrupción WebSocket, scripts en varios idiomas, complementos y automatización | Integración oficial de MCP y complementos de soporte opcionales de LLM |
| **Requestly HTTP Interceptor** | Extensión de navegador y herramienta simulada/interceptor de escritorio multiplataforma | Fuente pública del interceptor de escritorio AGPL; el cliente independiente Requestly API es propietario según su aviso de repositorio comunitario público | Captura, redireccionamiento de todo el sistema/navegador, Map Local/Remote, modificación de encabezado/cuerpo, transformaciones JavaScript, simulacros y simulación de retraso/error | Un servidor oficial MCP independiente gestiona reglas y grupos; no se documenta ningún asistente de análisis de tráfico en la aplicación |

La disponibilidad de las funciones puede variar según la edición, el plan, la plataforma o el complemento.
"No documentado" significa que no se encontró una capacidad en el archivo oficial
fuentes revisadas en 2026-08-22; no es prueba de que la capacidad esté ausente.
Las declaraciones de productos y características anteriores se compararon con la documentación del proveedor.
repositorios de origen mantenidos por el proveedor, o términos de licencia del proveedor en esa fecha y
puede cambiar. Los nombres de productos y las marcas comerciales pertenecen a sus respectivos propietarios;
Rockxy no está afiliado ni respaldado por ellos. Las correcciones son bienvenidas.
a través del rastreador de problemas Rockxy.

En la hoja de ruta: reglas más profundas que tienen en cuenta los protocolos, paquetes de evidencia redactados más seguros, flujos de trabajo de comparación y reproducción más sólidos, una guía de configuración para desarrolladores más amplia e investigación continua sobre HTTP/2 y HTTP/3.

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
- [AI Assistant](docs/features/ai-assistant.mdx) — investiga tráfico seleccionado localmente o con un modelo configurado tras Review Data
- [Filtros y búsqueda](docs/core-features/filters-and-search.mdx) — scopes del sidebar, Focus Sets, Noise Control, filtros del toolbar y búsqueda
- [Inspección AI y Web3](docs/features/ai-web3-inspection.mdx) — inspecciona tráfico reconocido de model API, JSON-RPC y x402
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

Rockxy se mantiene de forma independiente. Los sponsorships ayudan a financiar el desarrollo continuo, la infraestructura de releases, la documentación y el trabajo de seguridad.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy cuenta con el patrocinio fiscal de [Open Source Collective](https://docs.oscollective.org/). Las contribuciones y los gastos del proyecto se registran en la [p&aacute;gina p&uacute;blica de Open Collective de Rockxy](https://opencollective.com/rockxy), ofreciendo una visi&oacute;n transparente de c&oacute;mo se reciben y utilizan los fondos.

| Nivel | Contribuci&oacute;n | Qu&eacute; apoya |
|-------|------------------|----------------|
| **Backer** | Desde $5/mes | Mantenimiento de c&oacute;digo abierto, documentaci&oacute;n, pruebas y lanzamientos |
| **Builder** | Desde $25/mes | Pruebas de regresi&oacute;n, mejoras de rendimiento y flujos de depuraci&oacute;n cotidianos |
| **Sponsor** | $100/mes | Mantenimiento a largo plazo de una herramienta centrada en la privacidad y gratuita para desarrolladores |
| **Sustaining Sponsor** | $500/mes | Mantenimiento y desarrollo de producto focalizados, incluida la automatizaci&oacute;n de lanzamientos y el soporte de protocolos |

**Consultas de partnership** — empresas de developer tools, firmas de seguridad y equipos enterprise que buscan integraciones custom o soluciones white-label: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Soporte

- [Open Collective](https://opencollective.com/rockxy/donate) — contribuye a Rockxy mediante su presupuesto de proyecto transparente
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — apoya el desarrollo de Rockxy
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — bug reports y feature requests
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — preguntas y comunidad
- **Email** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Security issues** — consulta [SECURITY.md](SECURITY.md) para responsible disclosure

## Licencia

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## Star History

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Hecho por <a href="https://github.com/LocNguyenHuu">Stephen</a>. Construido con Swift, SwiftNIO, SwiftUI y AppKit.</sub>
</p>
