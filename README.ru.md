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
  <strong>Прокси-сервер отладки с открытым исходным кодом для macOS.</strong>
</p>

<p align="center">
  Перехватывайте, проверяйте и изменяйте трафик HTTP/HTTPS/WebSocket/GraphQL с помощью собственного приложения Swift, которое вы можете проверять, создавать и доверять.<br>
  Создан для рабочих процессов отладки API, мобильных устройств, MCP, искусственного интеллекта и блокчейна по мере развития Rockxy.<br>
  Локальная (local-first), AGPL-3.0 альтернатива <a href="#rockxy-против-альтернатив">Proxyman и Charles Proxy</a>.
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

## Основные моменты текущего филиала

- AI Assistant теперь исследует один или несколько выбранных request с помощью встроенного локального анализа или опциональной настроенной модели Ollama/provider, с явным подтверждением Review Data, ограниченным redaction, потоковыми ответами, evidence reveal и инициируемыми пользователем handoff.
- Нативная боковая панель теперь включает переиспользуемые Focus Sets для scope app/domain/path, а также Noise Control уровня workspace, скрывающий совпадающие domain или path без остановки capture.
- Основной workspace теперь использует нативные вертикальные и горизонтальные split view для Context Dock и нижнего inspector, сохраняя разделители полной высоты, согласованные separator toolbar/footer и автоматическое изменение раскладки.
- Upstream Proxy теперь включает бесплатную/основную автоматическую настройку прокси-сервера с маршрутизацией URL-адресов PAC для `DIRECT`, HTTP и HTTPS маршруты, сохраняя при этом существующие границы SOCKS5 и политики аутентификации.
- Рабочие процессы экспорта теперь охватывают OpenAPI YAML/HTML и публикацию Gist с выбранным трафиком, а также сбор полезных данных с учетом редактирования.
- Инструменты инспектора теперь включают фильтрацию JSONPath/ключ/значение и быстрый предварительный просмотр выбранного текста полезной нагрузки, например JWT.
- Инспекция трафика AI и Web3 теперь добавляет метки протокола, вкладки inspector и сводки отладки для распознанных вызовов моделей, трафика JSON-RPC и подсказок оплаты в стиле x402.
- Программа установки разработчика Node.js теперь отражает выбранный клиент во время проверки и содержит более полное руководство по использованию локального хоста.
- Центр настройки разработчиков теперь охватывает среды выполнения, браузеры, клиенты, устройства, платформы и среды с фрагментами для конкретных целей, наблюдателями проверок и честным руководством.
- Инспекция бинарных frame WebSocket теперь включает ограниченные Protobuf wire-format heuristic по запросу, не добавляя decoder work в capture hot path.
- Публичная roadmap теперь сосредоточена на более глубоких protocol-aware rules, replay, comparison и безопасном обмене отредактированными доказательствами.

## Особенности

Инструменты, к которым вы обращаетесь, когда браузерных DevTools недостаточно. Отладка основного трафика для Mac и iOS — встроенная функция для macOS, с общедоступными выпусками и рабочим процессом, ориентированным на локальный уровень.

### Захват трафика

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Проверяйте трафик HTTP, HTTPS, WebSocket и GraphQL из любого приложения Mac, интерфейса командной строки или устройства iOS. Инструменты разработчика для браузера заканчиваются в браузере — Rockxy видит остальную часть вашего стека.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Расширенный фильтр и поиск

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Сократите тысячи перехваченных запросов за считанные секунды. Объедините фильтры метода, хоста, статуса, заголовка, тела и процесса — или запустите полнотекстовый поиск по всему сеансу.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets и Noise Control

Превратите повторяющиеся расследования в переиспользуемые scope боковой панели. Focus Sets объединяет include по app, domain и path с exclude по domain/path, сохраняется между запусками и доступен в каждом workspace. Noise Control продолжает захватывать телеметрию и малоценный трафик, но скрывает их в текущем workspace.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant объясняет выбранный трафик рядом с нативной таблицей request и боковой панелью" width="820" />

Выберите один или несколько захваченных request и спросите, что произошло, что сломалось, что изменилось или что проверить дальше. Rockxy начинает с анализа на основе доказательств на этом Mac; настроенная модель Ollama или provider запускается только после того, как Review Data покажет точный, ограниченный и отредактированный контекст. Ответы могут раскрыть source request и подготовить нативные follow-up workflow, но никогда автоматически не изменяют трафик и не выполняют действия.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Прочитать руководство AI Assistant](docs/features/ai-assistant.mdx).

### MCP-сервер для внешних AI-клиентов

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Позвольте Claude Desktop или Cursor проверять захваченный трафик с помощью десяти инструментов только для чтения в локальном MCP-сервере Rockxy. Спросите «почему это 500?» вместо вставки заголовков в чат. Реализация с открытым исходным кодом, аутентифицируется по токену и по умолчанию сохраняет redaction конфиденциальных данных включённым.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Центр настройки для разработчиков

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Скопируйте и вставьте фрагменты прокси-сервера для Python, Node.js, Go, Rust, cURL, Docker и браузеров, затем нажмите «Выполнить тест», чтобы убедиться, что трафик действительно проходит.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Управление сертификатами для отладки HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Корневой центр сертификации ECDSA P-256, созданный при первом запуске и запечатанный в вашей связке ключей. Расшифровать HTTPS с первой попытки; закрепленные хосты проходят автоматически.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL-прокси и расшифровка HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Выберите, какие хосты получат расшифровку TLS. Расшифрованный трафик показывает реальные заголовки и JSON; все остальное проходит в зашифрованном виде. Правила с подстановочными знаками позволяют масштабировать домены одним щелчком мыши.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Обход прокси

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Пропускайте определенные хосты, чтобы приложения, внутренние службы или данные телеметрии, закрепленные сертификатами, никогда не попадали в захват. Подстановочные знаки делают список коротким, и ваш журнал запросов фокусируется на том, что вас действительно волнует.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Черный список

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Заставьте любой хост выйти из строя. Откажитесь от рекламных сетей, сторонних трекеров или нестабильных зависимостей, чтобы увидеть, как ухудшается качество вашего приложения, когда оно исчезнет, ​​не меняя ни строчки кода.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Карта Местная

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Предоставляйте сохраненный файл или дерево каталогов вместо живого ответа. Замените полезные данные JSON, воспроизведите снимок или прикрепите нестабильный сторонний API к локальной копии во время отладки.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Карта удаленного доступа

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Перепишите назначение перехваченного запроса, не затрагивая код приложения или /etc/hosts. Направьте производственный трафик на промежуточную версию, на ваш сервер разработки или на компьютер коллеги для воспроизводимого воспроизведения ошибки.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Точки останова и правила

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Приостановите запрос или ответ, отредактируйте метод, заголовки, тело или статус, а затем продолжите. Самый быстрый способ проверить: «Что, если API вернет 401?» не касаясь бэкэнда.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Изменить заголовки

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Добавляйте, удаляйте или заменяйте заголовки на любом хосте без повторного развертывания. Тестируйте изменения CORS, аутентификации или кэширования за считанные секунды с помощью встроенных предустановок.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Пользовательские заголовки запросов и ответов

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Повысьте любой заголовок запроса или ответа до столбца первого класса в таблице трафика. Держите источники запросов и ответов раздельно, сохраните нужные заголовки, а затем просматривайте request ID, trace ID, состояние кэша или собственные метаданные, не открывая каждый inspector.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Условия сети

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Переключитесь на 3G, EDGE, LTE, Wi-Fi или установите пользовательскую задержку. Ваш ноутбук подключен к оптоволокну; ваши пользователи этого не делают — прежде чем они это сделают, посмотрите UX при RTT 400 мс.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Создание — Редактирование и воспроизведение

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Восстановите любой захваченный HTTP-запрос — измените метод, URL-адрес, заголовки, параметры запроса или тело — и повторите отправку, не покидая Rockxy. Без цикла копирования-вставки в Postman, Insomnia или curl. Выполняйте итерации по запросам LLM, фаззьте границы аутентификации или воспроизводите случай сбоя для конечных точек OpenAI, Anthropic и Cohere за считанные секунды.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Сравнить

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Сложите две захваченные транзакции или вставленные payload рядом и отметьте каждое изменённое поле — статус, заголовки, ключи JSON или байты тела. Улавливайте тихие регрессии API, недетерминированные выходные данные LLM и prompt drift, не передавая ничего в сторонний инструмент сравнения.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Пользовательские вкладки предварительного просмотра

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Отрисовывайте тела запросов и ответов так, как вы хотите. Прикрепите к инспектору дополнительные вкладки для JSON, GraphQL, JWT, изображения или вашего собственного формата — их можно будет использовать повторно для каждого перехваченного запроса.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Сессии и экспорт

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Сохраняйте сеансы, импортируйте/экспортируйте HAR для передачи между инструментами, копируйте любой запрос в формате cURL или JSON. Отредактируйте заголовки авторизации, файлы cookie и токены-носители перед тем, как поделиться ими — дайте товарищу по команде рабочий репродукцию ошибки без утечки секретов.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Рабочие пространства с несколькими вкладками

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Многовкладочные рабочие пространства Rockxy с независимо отфильтрованными представлениями одного live capture" width="820" />

Держите рядом независимые представления расследования одного live capture — одна вкладка для трафика staging, одна для production и одна для потока устройства iOS. Каждая вкладка сохраняет собственные фильтры, сортировку, выбор, scope боковой панели и состояние инспектора, разделяя proxy и захваченные транзакции.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript-скрипты

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS перехватывает запросы и ответы в тех случаях, когда статическое правило не может охватить — редактирование личных данных, подписание токенов, перезапись полезных данных. Ошибки появляются внутри, а не портят трафик.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Инспекция с учетом протокола

Rockxy предоставляет protocol-aware inspection для AI, Web3 RPC и x402 в обычном workflow отладки HTTP.

### Инспекция AI-трафика

Rockxy обнаруживает распознанные запросы AI в рамках обычного workflow захвата. Проверяйте выбранные вызовы моделей, потоковое состояние, поля usage при их наличии, предупреждения, retrieval hints и сводки tool-call, не вставляя конфиденциальные payload в другой сервис.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Проверка Web3/RPC

Rockxy превращает сетевые вызовы эпохи блокчейна в читаемые доказательства отладки. Проверяйте трафик HTTP JSON-RPC в стиле EVM и Solana с provider host, request ID, method, batch summary, error, chain, transaction, payload и debug-intent, не превращая Rockxy в кошелёк или обозреватель блоков.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### Подсказки потока платежей x402

Rockxy выделяет подсказки payment-required и ориентированные на retry, чтобы платёжные HTTP-потоки были понятны с сетевого уровня, при этом доказательства отладки остаются локальными и redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Будущая Работа

Следующие разделы описывают публичное направление, а не текущее поведение.

### Правила с учетом протоколов

Rockxy уже сегодня может маркировать и проверять трафик AI и Web3. Более глубокое сопоставление правил по model, tool call, методу JSON-RPC, chain, transaction hash или batch subcall остаётся будущей работой; текущие инструменты изменения трафика по-прежнему сопоставляют URL, HTTP-метод и заголовки.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Пакеты отредактированных доказательств `Скоро`

Поделитесь фактами, необходимыми для воспроизведения ошибки, не разглашая секретов. Упакуйте выбранный трафик со сводками протоколов, предварительным просмотром изменений и контекстом на основе источника, который партнер по команде может проверить.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Совместное использование команды и сотрудничество `Скоро`

Отправьте записанную сессию товарищу по команде одним щелчком мыши. Аннотируйте неудачные запросы в режиме реального времени, узнавайте, кто что смотрит, и выполняйте парную отладку HTTPS-трафика без совместного использования экрана. Предназначен для будущего выпуска.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Нативная оболочка приложения macOS — без Electron. SwiftUI + AppKit + SwiftNIO, WebKit используется только для предпросмотра тела HTML.

## Быстрый старт

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Соберите и запустите в Xcode. Окно приветствия поможет вам выполнить настройку корневого центра сертификации, установку помощника и активацию прокси-сервера.

**Требования:** macOS 14.0+, Xcode 16+, Swift 5.9

Если вы хотите подключить Rockxy к локальному клиенту MCP после установки, см. [Руководство по интеграции MCP](docs/features/mcp.mdx).

## Rockxy против альтернатив

Основная матрица охватывает прокси-серверы общего назначения для веб-отладки. Тестирование безопасности
пакеты и браузерные/ориентированные на API перехватчики со значительным перекрытием рабочих процессов
перечислены отдельно, поэтому разные продукты не представлены как взаимозаменяемые.
Анализаторы пакетов и клиенты только для API не входят в это сравнение.

### Прямые прокси-серверы для веб-отладки

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Форма продукта** | Собственный прокси-сервер для отладки macOS | Родное приложение для macOS; Редакции Windows/Linux на базе Electron | Межплатформенный прокси-сервер для отладки настольных компьютеров | Кроссплатформенный CLI/TUI и набор инструментов прокси-сервера веб-интерфейса | Кроссплатформенный настольный прокси-сервер Electron и HTTP-клиент | Межплатформенный прокси-сервер для отладки настольных компьютеров |
| **Исходный код и модель сборки** | Публичный источник сообщества под номером AGPL-3.0-or-later; можно построить с помощью Xcode. Официальный DMG также содержит закрытые последующие компоненты | Закрытый исходный код; в рассмотренных официальных материалах не указан общедоступный источник приложения | Закрытый исходный код; в рассмотренных официальных материалах не указан общедоступный источник приложения | Публичный источник под лицензией MIT; сборка из исходников | Публичный исходный код рабочего стола AGPL; возможность сборки из исходного кода; опубликованные двоичные файлы имеют дополнительные возможности лицензирования | Закрытый исходный код; распространяется как объектный код под Fiddler Everywhere EULA |
| **Захват и настройка** | Локальный системный прокси с пошаговой настройкой для приложений Mac, сред выполнения, устройств iOS и симулятора | Автоматическая настройка приложений, сред выполнения и мобильных устройств Mac | Локальный прокси-сервер с macOS, iOS и руководства по кроссплатформенной настройке | Обычный, локальный процесс, WireGuard, обратный, прозрачный и другие режимы захвата | Целевой и ручной перехват прокси-серверов для браузеров, сред выполнения, контейнеров и мобильных устройств | Системный, сетевой, браузерный, терминальный, явный режимы захвата и режимы захвата с удаленного устройства |
| **Изменить и высмеять** | Точки останова, Map Local/Remote, правила заголовков, правила блокировки и задержки | Точки останова, Map Local/Remote, списки блокировки, сетевые условия и правила JavaScript | Точки останова, перезапись, Map Local/Remote, блокировка и регулирование | Map Local/Remote, модификация тела/заголовка, блокировка и воспроизведение сервера | Точки останова, а также перезапись, перенаправление, макетирование и внедрение ошибок на основе правил; некоторая автоматизация ограничена планом | Правила, точки останова, перенаправления, модификация ответов и насмешки |
| **Воспроизведите и сравните** | Создание/воспроизведение, а также локальный параллельный запрос, сравнение заголовка и тела | Составление, повторение и сравнение | Повторять и редактировать запросы | Воспроизведение на стороне клиента и на стороне сервера | Встроенный HTTP-клиент для формирования и отправки запросов | API Composer, воспроизведение трафика и сравнение трафика задокументированы как бета-версия |
| **Рабочие процессы WebSocket** | Проверка текстового/двоичного фрейма с помощью ограниченной эвристики Protobuf | WS/WSS проверка; сценарии могут изменять URL/заголовки рукопожатия, а не сообщения | Поддержка WebSocket задокументирована в официальной истории версий | перехват и создание сценариев WebSocket; Воспроизведение WebSocket не поддерживается | Проверка WebSocket плюс правила, специфичные для WebSocket | WebSocket захват и проверка |
| **Сценарии и расширяемость** | Хуки JavaScriptCore в песочнице с ограниченным API и таймаутом выполнения | JavaScript скрипты запроса/ответа | Переписать правила и веб-интерфейс управления; общая функция сценариев JavaScript не документирована | Python дополнения и автоматизация командной строки | Автоматизация на основе правил, а также общедоступные библиотеки и прокси-библиотеки | Автоматизация на основе правил; не задокументирована общая функция создания собственных сценариев |
| **Восходящая маршрутизация** | [восходящий прокси-сервер HTTP/HTTPS и маршрутизация URL-адресов PAC](docs/features/upstream-proxy.mdx); Политика сообщества отключает аутентификацию прокси и SOCKS5 и ограничивает правила обхода тремя | Внешняя маршрутизация HTTP/HTTPS/SOCKS и PAC с правилами обхода | Внешние прокси HTTP/HTTPS/SOCKS с аутентификацией и обходом правил | HTTP/HTTPS восходящий режим плюс обратный режим и режимы прослушивания SOCKS | Системные, HTTP, HTTPS и исходящие настройки SOCKS; могут применяться ограничения плана | Автоматическое связывание с системными прокси и захват обратного прокси |
| **AI и MCP** | [ИИ-помощник в приложении](docs/features/ai-assistant.mdx) и [встроенный локальный MCP](docs/features/mcp.mdx) с 10 инструментами только для чтения, аутентификацией по токену и редактированием по умолчанию | Встроенный MCP для внешних клиентов AI, включая чтение трафика и управление приложениями/правилами | Не документировано | Не документировано | Входящий в комплект локальный мост MCP присутствует в текущем официальном исходнике; нет документального помощника в приложении | Встроенный MCP плюс помощник по отладке профессионального уровня, текущая документация которого требует вставки в чат перехваченных данных о трафике |

### Соседние инструменты перехвата

Эти продукты во многом совпадают с Rockxy, но лидируют в тестировании безопасности.
правила браузера или рабочие процессы клиента API, а не тот же универсальный
собственный фокус прокси-отладки.

| **Продукт** | **Почему это соседство** | **Исходный код и модель сборки** | **Соответствующее совпадение** | **AI и MCP** |
|---|---|---|---|---|
| **Burp Suite** | Пакет тестирования веб-безопасности с перехватывающим прокси-сервером | Приложение с закрытым исходным кодом; его EULA гласит, что пользователи не имеют прав на исходный код приложения. Расширения могут использовать отдельные лицензии | Перехват прокси и сопоставление/замена, повторитель, WebSocket, прокси-сервер восходящего потока/SOCKS и большая экосистема расширений | Burp AI доступен в Повторителе; PortSwigger также поддерживает общедоступное расширение сервера MCP для внешних клиентов AI |
| **ZAP** | Сканер безопасности и перехватывающий прокси | Публичный источник Apache-2.0; сборка из исходников | Перехват/редактирование, повторная отправка вручную, точки останова и сценарии WebSocket, многоязычные сценарии, надстройки и автоматизация | Официальная интеграция MCP и дополнительные надстройки поддержки LLM |
| **Requestly HTTP Interceptor** | Расширение для браузера и кроссплатформенный инструмент-перехватчик/макет рабочего стола | Публичный исходный код настольного перехватчика AGPL; отдельный клиент Requestly API является собственностью согласно уведомлению об общедоступном репозитории сообщества | Захват в масштабе всей системы/браузера, перенаправление, Map Local/Remote, модификация заголовка/тела, преобразования JavaScript, имитация и моделирование задержек/ошибок | Отдельный официальный сервер MCP управляет правилами и группами; нет встроенного в приложение помощника по анализу трафика |

Доступность функций может зависеть от выпуска, плана, платформы или дополнения.
«Не задокументировано» означает, что возможность не была обнаружена в официальном исходном файле.
источники, проверенные на 2026-08-22; это не является доказательством отсутствия такой возможности.
Приведенные выше заявления о продуктах и функциях были проверены на соответствие документации поставщика.
репозитории исходных текстов, поддерживаемые поставщиком, или условия лицензии поставщика на эту дату и
может измениться. Названия продуктов и товарные знаки принадлежат их соответствующим владельцам;
Rockxy не связан с ними и не одобрен ими. Исправления приветствуются
через систему отслеживания ошибок Rockxy.

В планах: более глубокие правила с учетом протоколов, более безопасные отредактированные пакеты доказательств, более эффективные рабочие процессы воспроизведения и сравнения, более широкие рекомендации по настройке для разработчиков и продолжение исследований HTTP/2 и HTTP/3.

## Безопасность

Rockxy перехватывает сетевой трафик — безопасность является основополагающей, а не дополнительной.

- Помощник XPC проверяет вызывающих абонентов через **сравнение цепочки сертификатов**, а не только идентификатор пакета
- Плагины запускаются **JavaScriptCore в песочнице** с 5-секундным таймаутом, без доступа к файловой системе/сети
- **Проверка ввода** на всех границах — ограничения размера тела, ограничения URI, защита от DoS регулярных выражений, предотвращение обхода пути.
- Полномочия **автоматически редактируется** в захваченных журналах
- Конфиденциальные файлы, хранящиеся с **0o600 разрешения**

Сообщайте об уязвимостях через [SECURITY.md](SECURITY.md). См. [полная архитектура безопасности](docs/development/security.mdx) для получения подробной информации.

## Дорожная карта

Публичная дорожная карта Rockxy ориентирована на рабочий процесс и не требует дат. Основное внимание уделяется надежности, встроенному пользовательскому интерфейсу macOS, рабочим процессам отладки, поддержке протоколов, видимости трафика эпохи AI/Web3, документации и адаптации участников.

- [ROADMAP.md](ROADMAP.md): высшее государственное инженерное направление
- [Общественная дорожная карта Rockxy](https://github.com/orgs/RockxyApp/projects/1): оперативная видимость проблем, отслеживаемых в дорожной карте.

## Документация

Полная документация доступна на сайте [Роккси Документы](docs/index.mdx):

- [Краткое руководство](docs/quickstart.mdx) — приступить к работе за считанные минуты
- [Центр настройки для разработчиков](docs/features/developer-setup-hub.mdx) — фрагменты времени выполнения, руководства по устройствам, тесты проверки и матрица поддержки.
- [AI Assistant](docs/features/ai-assistant.mdx) — исследуйте выбранный трафик локально или с настроенной моделью после Review Data
- [Фильтры и поиск](docs/core-features/filters-and-search.mdx) — scope боковой панели, Focus Sets, Noise Control, фильтры toolbar и поиск
- [Инспекция AI и Web3](docs/features/ai-web3-inspection.mdx) — проверяйте распознанный трафик model API, JSON-RPC и x402
- [Интеграция MCP](docs/features/mcp.mdx) — подключить Rockxy к локальным клиентам MCP
- [Архитектура](docs/development/architecture.mdx) — прокси-движок, модель актера, поток данных
- [Модель безопасности](docs/development/security.mdx) — границы доверия, проверка XPC, управление сертификатами
- [Дизайнерские решения](docs/development/design-decisions.mdx) — почему SwiftNIO, NSTableView, актеры
- [Сборка из исходного кода](docs/development/building.mdx) — сборка, тестирование, анализ и отладка
- [Стиль кода](docs/development/code-style.mdx) — SwiftLint, SwiftFormat и соглашения
- [Журнал изменений](CHANGELOG.md) — неизданные работы и отмеченные релизы

## Содействие

Вклад приветствуется — код, тесты, документация, отчеты об ошибках и отзывы о UX.

См. **[CONTRIBUTING.md](CONTRIBUTING.md)** инструкции по настройке, стиль кода и полный контрольный список PR.

Хорошие первые проблемы помечены [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Открывая PR, вы соглашаетесь с [CLA](CLA.md).

## Спонсоры и партнеры

Rockxy поддерживается независимо. Спонсорство помогает финансировать непрерывную разработку, инфраструктуру релизов, документацию и работу над безопасностью.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy получает фискальное сопровождение от [Open Source Collective](https://docs.oscollective.org/). Взносы и расходы проекта публикуются на [открытой странице Rockxy в Open Collective](https://opencollective.com/rockxy), обеспечивая прозрачность получения и использования средств.

| Уровень | Взнос | Что поддерживает |
|---------|-------|------------------|
| **Backer** | От $5/месяц | Поддержку открытого исходного кода, документацию, тестирование и релизы |
| **Builder** | От $25/месяц | Регрессионное тестирование, повышение производительности и ежедневные процессы отладки |
| **Sponsor** | $100/месяц | Долгосрочную поддержку ориентированного на конфиденциальность инструмента, бесплатного для разработчиков |
| **Sustaining Sponsor** | $500/месяц | Целенаправленную поддержку и развитие продукта, включая автоматизацию релизов и поддержку протоколов |

**Запросы о партнерстве** — компании-разработчики инструментов, охранные фирмы и корпоративные команды, которым нужны индивидуальные интеграции или решения «white label»: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Поддержка

- [Open Collective](https://opencollective.com/rockxy/donate) — поддержать Rockxy через прозрачный бюджет проекта
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — поддержать развитие Rockxy
- [Проблемы с GitHub](https://github.com/RockxyApp/Rockxy/issues) — отчеты об ошибках и запросы функций
- [Обсуждения на GitHub](https://github.com/RockxyApp/Rockxy/discussions) — вопросы и чат сообщества
- **электронная почта** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Проблемы безопасности** - см. [SECURITY.md](SECURITY.md) за ответственное раскрытие информации

## Лицензия

[Стандартная общественная лицензия GNU Affero v3.0](LICENSE) — Авторские права Rockxy Contributors, 2024–2026 гг.

## Звездная история

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Сделано <a href="https://github.com/LocNguyenHuu">Stephen</a>. Создано с использованием Swift, SwiftNIO, SwiftUI и AppKit.</sub>
</p>
