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
  <strong>Проксі-сервер для налагодження з відкритим вихідним кодом, який можна перевірити, для macOS.</strong>
</p>

<p align="center">
  Перехоплюйте, перевіряйте та змінюйте трафік HTTP/HTTPS/WebSocket/GraphQL за допомогою рідної програми Swift, яку можна перевіряти, створювати та довіряти.<br>
  Створено для робочих процесів налагодження API, мобільних пристроїв, MCP, штучного інтелекту та блокчейну в міру розвитку Rockxy.<br>
  Локальна (local-first), AGPL-3.0 альтернатива <a href="#rockxy-проти-альтернатив">Proxyman і Charles Proxy</a>.
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

## Поточні основні моменти філії

- AI Assistant тепер досліджує один або кілька вибраних request за допомогою вбудованого локального аналізу або опціональної налаштованої моделі Ollama/provider, з явним підтвердженням Review Data, обмеженим redaction, потоковими відповідями, evidence reveal та ініційованими користувачем handoff.
- Нативна бічна панель тепер містить багаторазові Focus Sets для scope app/domain/path, а також Noise Control рівня workspace, що приховує відповідні domain або path без зупинки capture.
- Основний workspace тепер використовує нативні вертикальні та горизонтальні split view для Context Dock і нижнього inspector, зберігаючи роздільники повної висоти, узгоджені separator toolbar/footer та автоматичну зміну розкладки.
- Вихідний проксі-сервер тепер включає безкоштовну/основну автоматичну конфігурацію проксі-сервера з маршрутизацією URL-адреси PAC `DIRECT`, HTTP і HTTPS, зберігаючи існуючі SOCKS5 і межі політики автентифікації.
- Робочі процеси експорту тепер охоплюють OpenAPI YAML/HTML і публікацію Gist із вибраним трафіком із створенням корисного навантаження з урахуванням редагування.
- Інструменти інспектора тепер включають фільтрацію JSONPath/ключ/значення та швидкий попередній перегляд вибраного тексту корисного навантаження, наприклад JWT.
- Інспекція трафіку AI та Web3 тепер додає мітки протоколу, вкладки inspector і зведення налагодження для розпізнаних викликів моделей, трафіку JSON-RPC та підказок оплати у стилі x402.
- Налаштування розробника Node.js тепер відображає вибраний клієнт під час перевірки та містить повніший приклад посібника для локального хосту.
- Developer Setup Hub тепер охоплює середовища виконання, браузери, клієнти, пристрої, фреймворки та середовища з цільовими фрагментами, спостерігачами перевірки та чесним посібником.
- Інспекція бінарних frame WebSocket тепер містить обмежені Protobuf wire-format heuristic на вимогу, не додаючи decoder work до capture hot path.
- Публічна roadmap тепер зосереджена на глибших protocol-aware rules, replay, comparison і безпечнішому обміні redacted evidence.

## особливості

Інструментів, до яких ви тягнетеся, коли браузер DevTools недостатньо. Налагодження основного трафіку для роботи з Mac і iOS — вбудовано в macOS, із загальнодоступними випусками та локальним робочим процесом.

### Захоплення трафіку

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Перевірте трафік HTTP, HTTPS, WebSocket і GraphQL з будь-якої програми Mac, CLI або пристрою iOS. Browser DevTools закінчуються в браузері — Rockxy бачить решту вашого стека.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Розширений фільтр і пошук

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Звужуйте тисячі отриманих запитів за секунди. Комбінуйте фільтри методу, хосту, статусу, заголовка, тіла та процесу — або запустіть повнотекстовий пошук протягом усього сеансу.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets і Noise Control

Перетворюйте повторювані дослідження на багаторазові scope бічної панелі. Focus Sets поєднує include для app, domain і path з exclude для domain/path, зберігається між запусками й доступний у кожному workspace. Noise Control продовжує захоплювати телеметрію та малоцінний трафік, але приховує їх у поточному workspace.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant пояснює вибраний трафік поруч із нативною таблицею request і бічною панеллю" width="820" />

Виберіть один або кілька захоплених request і запитайте, що сталося, що не вдалося, що змінилося або що перевірити далі. Rockxy починає з аналізу на основі доказів на цьому Mac; налаштована модель Ollama або provider запускається лише після того, як Review Data покаже точний, обмежений і редагований контекст. Відповіді можуть відкрити source request і підготувати нативні follow-up workflow, але ніколи автоматично не змінюють трафік і не виконують дії.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Прочитати посібник AI Assistant](docs/features/ai-assistant.mdx).

### Сервер MCP для зовнішніх AI-клієнтів

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Дозвольте Claude Desktop або Cursor перевіряти захоплений трафік за допомогою десяти інструментів лише для читання в локальному MCP-сервері Rockxy. Запитайте "навіщо це 500?" замість того, щоб вставляти заголовки в чат. Реалізація з відкритим кодом, автентифікується за токеном і за замовчуванням тримає redaction конфіденційних даних увімкненим.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Центр налаштування розробника

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Скопіюйте та вставте фрагменти проксі-сервера для Python, Node.js, Go, Rust, cURL, Docker і браузерів, а потім натисніть «Запустити тест», щоб підтвердити, що трафік дійсно надходить.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Керування сертифікатами для налагодження HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Кореневий CA P-256 ECDSA, створений під час першого запуску, запечатаний у вашому брелоку. Розшифрувати HTTPS з першої спроби; закріплені хости проходять автоматично.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### Проксі SSL і дешифрування HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Виберіть, які хости отримують розшифровку TLS. Розшифрований трафік показує справжні заголовки та JSON; все інше проходить через зашифроване. Правила підстановки дають змогу одним клацанням миші визначити область за доменом.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Обхід проксі

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Пропускайте певні хости, щоб програми із закріпленими сертифікатами, внутрішні служби чи шумна телеметрія ніколи не входили в запис. Символи підстановки роблять список коротким, а журнал запитів зосереджується на тому, що вас насправді хвилює.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Список блокувань

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Зробіть будь-який хост невдалим. Виключіть рекламні мережі, трекери сторонніх розробників або нестабільну залежність, щоб побачити, як ваш додаток погіршується, коли його більше немає, не змінюючи жодного рядка коду.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Місцева карта

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Подавати збережений файл або дерево каталогів замість живої відповіді. Поміняйте корисне навантаження JSON, відтворіть знімок або закріпіть нестабільний сторонній API до локальної копії під час налагодження.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Карта дистанційного керування

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Перепишіть призначення захопленого запиту, не торкаючись коду програми чи /etc/hosts. Направте робочий трафік на проміжну роботу, ваш сервер розробника або машину колеги для відтворюваного відтворення помилок.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Точки зупинки та правила

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Призупиніть запит або відповідь, відредагуйте метод, заголовки, тіло чи статус, а потім продовжіть. Найшвидший спосіб перевірити "що, якщо API поверне 401?" не торкаючись бекенда.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Змінити заголовки

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Додайте, видаліть або замініть заголовки на будь-якому хості без повторного розгортання. Перевірте CORS, автентифікацію або зміни кешу за секунди за допомогою вбудованих попередніх налаштувань.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Спеціальні заголовки запитів і відповідей

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Підвищте будь-який заголовок запиту або відповіді до стовпця першого класу в таблиці трафіку. Тримайте джерела запитів і відповідей окремо, збережіть потрібні заголовки, а потім переглядайте request ID, trace ID, стан кешу чи власні метадані, не відкриваючи кожен inspector.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Умови мережі

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Перейдіть до 3G, EDGE, LTE, WiFi або власної затримки. Ваш ноутбук підключено до оптоволокна; ваші користувачі ні — подивіться UX на 400 мс RTT раніше, ніж вони.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Створити — Редагувати та відтворити

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Перебудуйте будь-який захоплений HTTP-запит — змініть метод, URL-адресу, заголовки, параметри запиту або тіло — і надішліть повторно, не виходячи з Rockxy. Без циклу копіювання та вставки до Postman, Insomnia чи curl. Виконуйте ітерацію підказок LLM, фаззьте межі авторизації або відтворюйте невдалий випадок для кінцевих точок OpenAI, Anthropic і Cohere за лічені секунди.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Порівняйте

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Помістіть дві захоплені транзакції або вставлені payload поруч і помітьте кожне змінене поле — статус, заголовки, ключі JSON чи байти тіла. Виловлюйте мовчазні регресії API, недетерміновані виходи LLM і prompt drift, не передаючи нічого в сторонній інструмент розрізнення.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Спеціальні вкладки попереднього перегляду

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Відображайте тіла запиту та відповіді так, як вам потрібно. Закріпіть додаткові вкладки в інспекторі для JSON, GraphQL, JWT, зображення чи власного формату — їх можна повторно використовувати в кожному отриманому запиті.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Сеанси та експорт

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Зберігайте сеанси, імпортуйте/експортуйте HAR для передачі між інструментами, копіюйте будь-які запити як cURL або JSON. Відредагуйте заголовки авторизації, файли cookie та маркери носіїв, перш ніж ділитися — передайте колезі робоче відтворення помилки, не розкриваючи секретів.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Робочі області з кількома вкладками

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Багатовкладкові робочі області Rockxy з незалежно відфільтрованими поданнями одного live capture" width="820" />

Тримайте поруч незалежні подання дослідження одного live capture — одна вкладка для трафіку staging, одна для production і одна для потоку пристрою iOS. Кожна вкладка зберігає власні фільтри, сортування, вибір, scope бічної панелі та стан інспектора, спільно використовуючи proxy і захоплені транзакції.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Сценарії JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS перехоплює запити та відповіді у випадках, які статичні правила не можуть охопити — редагувати ідентифікаційну інформацію, підписувати маркери, переписувати корисні дані. Помилки з’являються всередині, а не пошкоджують трафік.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Інспекція з урахуванням протоколу

Rockxy надає protocol-aware inspection для AI, Web3 RPC і x402 у звичайному workflow налагодження HTTP.

### Інспекція AI-трафіку

Rockxy виявляє розпізнані запити AI у межах звичайного workflow захоплення. Перевіряйте вибрані виклики моделей, потоковий стан, поля usage за їх наявності, попередження, retrieval hints та зведення tool-call, не вставляючи конфіденційні payload в інший сервіс.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Перевірка Web3/RPC

Rockxy перетворює мережеві виклики епохи блокчейну на читабельні докази налагодження. Перевіряйте HTTP JSON-RPC трафік у стилі EVM і Solana з provider host, request ID, method, batch summary, error, chain, transaction, payload і debug intent, не перетворюючи Rockxy на wallet або block explorer.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### Підказки потоку платежів x402

Rockxy виділяє підказки payment-required та орієнтовані на retry, щоб платіжні HTTP-потоки були зрозумілі з мережевого рівня, тоді як докази налагодження залишаються локальними та redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Майбутня Робота

Наступні розділи описують публічний напрямок, а не поточну поведінку.

### Правила з урахуванням протоколу

Rockxy вже сьогодні може маркувати та перевіряти трафік AI і Web3. Глибше зіставлення правил за model, tool call, методом JSON-RPC, chain, transaction hash чи batch subcall залишається майбутньою роботою; поточні інструменти зміни трафіку й далі зіставляють URL, HTTP-метод і заголовки.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Відредаговані комплекти доказів `Незабаром`

Поділіться фактами, необхідними для відтворення помилки без витоку секретів. Укомплектуйте вибраний трафік зі зведеннями протоколів, попереднім переглядом редагування та контекстом із підтримкою джерела, який може перевіряти член команди.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Командний обмін і співпраця `Незабаром`

Надішліть записаний сеанс партнеру одним клацанням миші. Вбудовано коментуйте невдалі запити, дивіться, хто що переглядає в режимі реального часу, і налагоджуйте трафік HTTPS у парах без показу екрана. Націлено на майбутній випуск.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Нативна оболонка застосунку macOS — без Electron. SwiftUI + AppKit + SwiftNIO, WebKit використовується лише для попереднього перегляду тіла HTML.

## Швидкий старт

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Створюйте та запускайте в Xcode. Вікно привітання допоможе вам налаштувати кореневий ЦС, установити допоміжну програму та активувати проксі-сервер.

**Вимоги:** macOS 14.0+, Xcode 16+, Swift 5.9

Якщо ви хочете підключити Rockxy до локального клієнта MCP після встановлення, див [Посібник з інтеграції MCP](docs/features/mcp.mdx).

## Rockxy проти альтернатив

Основна матриця охоплює проксі-сервери загального призначення для веб-налагодження. Тестування безпеки
пакети програм і перехоплювачі, орієнтовані на браузер/API, із значним перекриттям робочого процесу
перераховані окремо, тому на відміну від продуктів не представлені як взаємозамінні.
Аналізатори пакетів і клієнти лише для API не входять у це порівняння.

### Проксі-сервери прямого веб-налагодження

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Форма продукту** | Власний проксі-сервер для налагодження macOS | Рідна програма macOS; Версії Windows/Linux на базі Electron | Кросплатформенний проксі-сервер для налагодження робочого столу | Кросплатформенний CLI/TUI і набір проксі-інструментів веб-інтерфейсу | Кросплатформенний проксі Electron для робочого столу та клієнт HTTP | Кросплатформенний проксі-сервер для налагодження робочого столу |
| **Вихідний код і модель збірки** | Загальнодоступне джерело спільноти під AGPL-3.0-or-later; можна побудувати з Xcode. Офіційний DMG також містить закриті нижчі компоненти | Закритий джерело; у розглянутих офіційних матеріалах не вказано джерело публічної заявки | Закритий джерело; у розглянутих офіційних матеріалах не вказано джерело публічної заявки | Загальнодоступне ліцензоване джерело MIT; можливість створення з джерела | Загальнодоступний робочий стіл AGPL; можливість створення з джерела; опубліковані двійкові файли мають додаткові параметри ліцензування | Закритий джерело; поширюється як об’єктний код під Fiddler Everywhere EULA |
| **Захоплення та налаштування** | Локальний системний проксі-сервер із покроковим налаштуванням для програм Mac, середовища виконання, пристроїв iOS і Simulator | Автоматичне налаштування програм Mac, середовища виконання та мобільних пристроїв | Локальний проксі-сервер із macOS, iOS і посібники з налаштування між платформами | Звичайний, локальний процес, WireGuard, зворотний, прозорий та інші режими захоплення | Цільове та ручне перехоплення проксі-серверів для браузерів, середовища виконання, контейнерів і мобільних пристроїв | Системний, мережевий, браузерний, термінальний, явний і режими захоплення віддаленого пристрою |
| **Змінити та імітувати** | Точки зупину, Map Local/Remote, правила заголовків, блокування та правила затримки | Точки зупину, Map Local/Remote, списки блокувань, умови мережі та правила JavaScript | Точки зупину, перезапис, Map Local/Remote, блокування та обмеження | Map Local/Remote, модифікація тіла/заголовка, блокування та відтворення на сервері | Точки зупину плюс перезапис на основі правил, перенаправлення, імітація та впровадження помилок; деяка автоматизація обмежена планом | Правила, точки зупинки, перенаправлення, модифікація відповіді та знущання |
| **Повторіть і порівняйте** | Створити/відтворити плюс локальний паралельний запит, заголовок і порівняння тексту | Створити, повторити та змінити | Повторити та редагувати запити | Відтворення на стороні клієнта та на стороні сервера | Вбудований HTTP-клієнт для складання та відправки запитів | API Композитор, відтворення трафіку та порівняння трафіку задокументовано як бета |
| **Робочі процеси WebSocket** | Перевірка текстових/бінарних кадрів із обмеженою евристикою Protobuf | перевірка WS/WSS; сценарії можуть змінювати URL/заголовки рукостискання, а не повідомлення | Підтримка WebSocket задокументована в офіційній історії версій | WebSocket перехоплення та створення сценаріїв; Повторне відтворення WebSocket не підтримується | Перевірка WebSocket плюс спеціальні правила для WebSocket | WebSocket захоплення та перевірка |
| **Сценарії та розширюваність** | Хуки JavaScriptCore із обмеженим API і тайм-аутом виконання | JavaScript сценарій запиту/відповіді | Переписати правила та веб-інтерфейс керування; загальна функція сценаріїв JavaScript не задокументована | Python аддони та автоматизація командного рядка | Автоматизація на основі правил плюс загальнодоступні вихідні та проксі-бібліотеки | Автоматизація на основі правил; не задокументовано загальну функцію сценарію першої сторони |
| **Вихідна маршрутизація** | [HTTP/HTTPS висхідний проксі та маршрутизація URL-адреси PAC](docs/features/upstream-proxy.mdx); Політика спільноти вимикає автентифікацію проксі та SOCKS5 і обмежує правила обходу на трьох | Зовнішня маршрутизація HTTP/HTTPS/SOCKS і PAC з правилами обходу | Зовнішні HTTP/HTTPS/SOCKS проксі з правилами автентифікації та обходу | HTTP/HTTPS висхідний режим плюс реверс і режими прослуховування SOCKS | Налаштування системи, HTTP, HTTPS і SOCKS; можуть застосовуватися обмеження плану | Автоматичне прив’язування до системних проксі-серверів плюс захоплення зворотного проксі-сервера |
| **AI та MCP** | [Помічник штучного інтелекту в програмі](docs/features/ai-assistant.mdx) і [вбудований локальний MCP](docs/features/mcp.mdx) із 10 інструментами лише для читання, автентифікацією маркерів і редагуванням за умовчанням | Вбудований MCP для зовнішніх клієнтів ШІ, включаючи зчитування трафіку та керування додатками/правилами | Не документально | Не документально | Локальний міст MCP у комплекті присутній у поточному офіційному джерелі; немає задокументованого помічника в програмі | Вбудований MCP плюс професійний помічник з налагодження, чия поточна документація вимагає вставляти дані трафіку в чат |

### Інструменти суміжного перехоплення

Ці продукти суттєво збігаються з Rockxy, але лідирують у тестуванні безпеки,
правила браузера або робочі процеси клієнта API, а не ті самі загального призначення
власний фокус налагодження-проксі.

| **Продукт** | **Чому це поруч** | **Вихідний код і модель збірки** | **Відповідне перекриття** | **AI та MCP** |
|---|---|---|---|---|
| **Burp Suite** | Набір тестів веб-безпеки з перехоплюючим проксі | Додаток із закритим кодом; його EULA стверджує, що користувачі не мають прав на джерело програми. Розширення можуть використовувати окремі ліцензії | Перехоплення та збіг/заміна проксі-сервера, ретранслятор, WebSockets, проксі-сервер висхідного потоку/SOCKS і велика екосистема розширення | Burp AI доступний у Repeater; PortSwigger також підтримує публічне розширення сервера MCP для зовнішніх клієнтів ШІ |
| **ZAP** | Сканер безпеки та проксі-перехоплення | Загальнодоступне джерело Apache-2.0; можливість створення з джерела | Перехоплення/редагування, повторне надсилання вручну, WebSocket точки зупину та сценарії, багатомовні сценарії, доповнення та автоматизація | Офіційна інтеграція MCP і додаткові модулі підтримки LLM |
| **Requestly HTTP Interceptor** | Розширення для веб-переглядача та крос-платформний перехоплювач робочого столу/імітаційний інструмент | Загальнодоступне джерело перехоплювача робочого столу AGPL; окремий клієнт Requestly API є пропрієтарним згідно з повідомленням публічного сховища спільноти | Загальносистемне/браузерне захоплення, перенаправлення, Map Local/Remote, модифікація заголовка/тіла, перетворення JavaScript, імітація та моделювання затримки/помилки | Окремий офіційний сервер MCP керує правилами та групами; немає задокументованого помічника з аналізу трафіку в програмі |

Доступність функцій залежить від версії, плану, платформи чи доповнення.
«Не задокументовано» означає, що можливість не знайдено в офіційній першій стороні
джерела, розглянуті на 2026-08-22; це не є доказом відсутності можливості.
Наведені вище заяви про продукт і функції були перевірені на відповідність документації постачальника,
репозиторії вихідних кодів, що підтримуються постачальниками, або умови ліцензії постачальників на цю дату та
може змінитися. Назви продуктів і товарні знаки належать відповідним власникам;
Rockxy не пов’язана з ними та не схвалена ними. Виправлення вітаються
через засіб відстеження проблем Rockxy.

На плані: глибші правила з урахуванням протоколів, безпечніші пакети відредагованих доказів, ефективніші робочі процеси відтворення та порівняння, ширші інструкції з налаштування розробника та продовження досліджень HTTP/2 і HTTP/3.

## Безпека

Rockxy перехоплює мережевий трафік — безпека є основою, а не обов’язковою.

- Помічник XPC перевіряє абонентів через **порівняння ланцюжка сертифікатів**, а не лише ідентифікатор пакета
- Плагіни запускаються **ізольоване програмне середовище JavaScriptCore** з 5-секундним тайм-аутом, без доступу до файлової системи/мережі
- **Перевірка введених даних** на всіх границях — обмеження розміру тіла, обмеження URI, захист регулярних виразів від DoS, запобігання обходу шляху
- Облікові дані **автоматично редагується** в захоплених журналах
- Конфіденційні файли, збережені в **0o600 дозволів**

Повідомити про вразливості через [SECURITY.md](SECURITY.md). Див [повна архітектура безпеки](docs/development/security.mdx) для деталей.

## Дорожня карта

Публічна дорожня карта Rockxy орієнтована на робочий процес і не містить дат. Він зосереджений на надійності, рідному macOS UX, робочих процесах налагодження, підтримці протоколів, видимості трафіку епохи AI/Web3, документації та адаптації учасників.

- [ДОРОЖНЯ КАРТА.md](ROADMAP.md): напрямок громадського будівництва високого рівня
- [Публічна дорожня карта Rockxy](https://github.com/orgs/RockxyApp/projects/1): оперативна видимість проблем, які відстежуються за допомогою дорожньої карти

## Документація

Повна документація доступна на [Rockxy Docs](docs/index.mdx):

- [Короткий посібник](docs/quickstart.mdx) — встати і почати працювати за лічені хвилини
- [Центр налаштування розробника](docs/features/developer-setup-hub.mdx) — фрагменти середовища виконання, посібники з пристроїв, зонди перевірки та матриця підтримки
- [AI Assistant](docs/features/ai-assistant.mdx) — досліджуйте вибраний трафік локально або з налаштованою моделлю після Review Data
- [Фільтри та пошук](docs/core-features/filters-and-search.mdx) — scope бічної панелі, Focus Sets, Noise Control, фільтри toolbar і пошук
- [Інспекція AI та Web3](docs/features/ai-web3-inspection.mdx) — перевіряйте розпізнаний трафік model API, JSON-RPC і x402
- [Інтеграція MCP](docs/features/mcp.mdx) — підключати Rockxy до локальних клієнтів MCP
- [Архітектура](docs/development/architecture.mdx) — механізм проксі, модель актора, потік даних
- [Модель безпеки](docs/development/security.mdx) — межі довіри, перевірка XPC, керування сертифікатами
- [Проектні рішення](docs/development/design-decisions.mdx) — чому SwiftNIO, NSTableView, актори
- [Будівництво з першоджерела](docs/development/building.mdx) — збірка, тестування, лінзування та налагодження
- [Стиль коду](docs/development/code-style.mdx) — SwiftLint, SwiftFormat і угоди
- [Журнал змін](CHANGELOG.md) — неопубліковані роботи та релізи з тегами

## Сприяння

Вітаються внески — код, тести, документи, звіти про помилки та відгуки про UX.

див **[CONTRIBUTING.md](CONTRIBUTING.md)** інструкції з налаштування, стиль коду та повний контрольний список PR.

Гарні перші номери позначені [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Відкриваючи PR, ви погоджуєтеся з [CLA](CLA.md).

## Спонсори та партнери

Rockxy підтримується незалежно. Спонсорство допомагає фінансувати безперервну розробку, інфраструктуру релізів, документацію та роботу над безпекою.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy отримує фіскальний супровід від [Open Source Collective](https://docs.oscollective.org/). Внески та витрати проєкту публікуються на [відкритій сторінці Rockxy в Open Collective](https://opencollective.com/rockxy), забезпечуючи прозорість отримання та використання коштів.

| Рівень | Внесок | Що підтримує |
|--------|--------|--------------|
| **Backer** | Від $5/місяць | Підтримку відкритого коду, документацію, тестування та релізи |
| **Builder** | Від $25/місяць | Регресійне тестування, покращення продуктивності та щоденні процеси налагодження |
| **Sponsor** | $100/місяць | Довгострокову підтримку орієнтованого на приватність інструмента, безкоштовного для розробників |
| **Sustaining Sponsor** | $500/місяць | Цілеспрямовану підтримку й розвиток продукту, включно з автоматизацією релізів і підтримкою протоколів |

**Партнерські запити** — компанії-розробники інструментів, охоронні фірми та корпоративні команди, які шукають користувальницькі інтеграції або рішення білої мітки: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Підтримка

- [Open Collective](https://opencollective.com/rockxy/donate) — підтримати Rockxy через прозорий бюджет проєкту
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — підтримати розвиток Rockxy
- [Проблеми GitHub](https://github.com/RockxyApp/Rockxy/issues) — звіти про помилки та запити на функції
- [Обговорення GitHub](https://github.com/RockxyApp/Rockxy/discussions) — запитання та чат спільноти
- **Електронна пошта** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Питання безпеки** — див [SECURITY.md](SECURITY.md) за відповідальне розголошення

## Ліцензія

[Загальна публічна ліцензія GNU Affero v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## Зоряна історія

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Зроблено <a href="https://github.com/LocNguyenHuu">Stephen</a>. Створено за допомогою Swift, SwiftNIO, SwiftUI та AppKit.</sub>
</p>
