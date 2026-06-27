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
  Місцева альтернатива AGPL-3.0 <a href="#rockxy-vs-alternatives">Проксімен і Чарльз Проксі</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Light.png" alt="Rockxy running on macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Останній випуск із тегами

**v0.27.2** — 2026-06-18

### Змінено

- Покращте засоби керування конфіденційністю метаданих
- Уточніть макет розкриття метаданих

див [CHANGELOG.md](CHANGELOG.md) для повної історії випусків.
<!-- END GENERATED: latest-release -->

## Поточні основні моменти філії

- Вихідний проксі-сервер тепер включає безкоштовну/основну автоматичну конфігурацію проксі-сервера з маршрутизацією URL-адреси PAC `DIRECT`, HTTP і HTTPS, зберігаючи існуючі SOCKS5 і межі політики автентифікації.
- Робочі процеси експорту тепер охоплюють OpenAPI YAML/HTML і публікацію Gist із вибраним трафіком із створенням корисного навантаження з урахуванням редагування.
- Інструменти інспектора тепер включають фільтрацію JSONPath/ключ/значення та швидкий попередній перегляд вибраного тексту корисного навантаження, наприклад JWT.
- Налаштування розробника Node.js тепер відображає вибраний клієнт під час перевірки та містить повніший приклад посібника для локального хосту.
- Developer Setup Hub тепер охоплює середовища виконання, браузери, клієнти, пристрої, фреймворки та середовища з цільовими фрагментами, спостерігачами перевірки та чесним посібником.
- Робота над WebSocket Protobuf продовжується в рамках розширеного напряму перевірки протоколів Rockxy.
- Публічне планування дорожньої карти тепер включає налагодження з урахуванням протоколу для трафіку ШІ, потоків Web3/RPC, потоків платежів у стилі x402 і безпечнішого обміну відредагованими доказами.

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

### Сервер MCP для помічників AI

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Дозвольте Claude Desktop або Cursor читати ваш захоплений трафік через локальний сервер MCP. Запитайте "навіщо це 500?" замість того, щоб вставляти заголовки в чат. Локальний, з можливістю редагування та з відкритим кодом.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Перевизначення заголовків для кожного хоста з повним контролем над обома фазами. Вставляйте токени автентифікації у вихідні запити, видаляйте Set-Cookie у відповідях або закріплюйте спеціальний User-Agent — збережені як іменовані правила, які можна будь-коли змінити.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Умови мережі

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Перейдіть до 3G, EDGE, LTE, WiFi або власної затримки. Ваш ноутбук підключено до оптоволокна; ваші користувачі ні — подивіться UX на 400 мс RTT раніше, ніж вони.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Створити — Редагувати та відтворити

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Перебудуйте будь-який захоплений HTTP-запит — змініть метод, URL-адресу, заголовки, параметри запиту або тіло — і надішліть повторно, не виходячи з Rockxy. Немає листоноші, безсоння чи циклу копіювання та вставки curl. Виконуйте ітерацію підказок LLM, розчісуйте межі авторизації або відтворюйте невдалий випадок для кінцевих точок OpenAI, Anthropic і Cohere за лічені секунди.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Порівняйте

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Помістіть дві отримані відповіді поруч і помітьте кожне перевернуте поле — статус, заголовки, ключі JSON, байти тіла. Виловлюйте мовчазні регресії API, недетерміновані виходи LLM і миттєвий дрейф, не передаючи нічого в сторонній інструмент розрізнення. Паралельна різниця підкреслює, що змінилося; глибоке порівняння JSON ігнорує порядок ключів.

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

Запускайте незалежні сеанси захоплення пліч-о-пліч — одна вкладка для постановки, одна для виробництва, одна для збірки пристрою iOS. Кожна вкладка має власні фільтри, вибір і стан інспектора, тому перемикання контексту не коштує нічого.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Сценарії JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS перехоплює запити та відповіді у випадках, які статичні правила не можуть охопити — редагувати ідентифікаційну інформацію, підписувати маркери, переписувати корисні дані. Помилки з’являються всередині, а не пошкоджують трафік.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Більше функцій незабаром

Майбутні функції відстежуються публічно та надсилаються лише тоді, коли будуть готові впровадження, тести, конфіденційність і документація.

### ШІ дорожня інспекція `Незабаром`

Спростіть налагодження трафіку моделі в рамках звичайного робочого процесу захоплення. Виявляйте запити штучного інтелекту, перевіряйте виклики обраної моделі, діагностуйте потокові відповіді, порівнюйте поведінку підказок/виводів і розумійте ланцюжки викликів інструментів, не вставляючи конфіденційні дані в іншу службу.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Перевірка Web3/RPC `Незабаром`

Перетворіть мережеві виклики епохи блокчейну на читабельний доказ налагодження. Перевіряйте трафік JSON-RPC і Solana RPC, групуйте пов’язані виклики в потоки, пояснюйте поширені помилки RPC і відтворюйте вибрані запити, не переходячи в гаманець або дослідник блоків.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### Налагодження потоку платежів x402 `Незабаром`

Зрозумійте контрольовані платежами потоки HTTP з мережевого рівня. Виділіть відповіді, які вимагають оплати, дотримуйтеся шляху повторної спроби та зберігайте докази налагодження локальними та з урахуванням редагування.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### Відредаговані комплекти доказів `Незабаром`

Поділіться фактами, необхідними для відтворення помилки без витоку секретів. Укомплектуйте вибраний трафік зі зведеннями протоколів, попереднім переглядом редагування та контекстом із підтримкою джерела, який може перевіряти член команди.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Фільтри та правила з урахуванням протоколу `Незабаром`

Використовуйте метадані AI та Web3 там, де вже працює Rockxy: фільтри, значки, додаткові стовпці, порівняння, правила, налаштування розробника та локальні підсумки MCP.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Командний обмін і співпраця `Незабаром`

Надішліть записаний сеанс партнеру одним клацанням миші. Вбудовано коментуйте невдалі запити, дивіться, хто що переглядає в режимі реального часу, і налагоджуйте трафік HTTPS у парах без показу екрана. Націлено на майбутній випуск.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% рідна macOS. Немає електрона. Немає веб-переглядів. SwiftUI + AppKit + SwiftNIO.

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

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Модель проекту** | Проект з відкритим кодом AGPL-3.0 | Власна комерційна програма | Власна комерційна програма |
| **Вихідний код** | Громадський, перевірений, розгалужений | Закритий вихідний код | Закритий вихідний код |
| **Збірка з джерела** | Безкоштовно з Xcode із цього репо | Недоступно з загальнодоступного джерела | Недоступно з загальнодоступного джерела |
| **Рідна основа macOS** | Swift + SwiftNIO + SwiftUI/AppKit | Рідна комерційна програма для macOS | Кросплатформенний комерційний додаток |
| **Локальне захоплення** | Локальний проксі-сервер, сертифікати, допоміжні дані та дані захоплення залишаються на вашому Mac | Настільний проксі-додаток | Настільний проксі-додаток |
| **Робочий процес налаштування розробника** | Вбудований центр налаштування розробника для середовища виконання, клієнтів, пристроїв, фреймворків і середовищ | Інструкції з налаштування для конкретного продукту | Інструкції з налаштування для конкретного продукту |
| **Зовнішній проксі + маршрутизація PAC** | Вихідний проксі HTTP/HTTPS, автоматична конфігурація PAC і правила обходу | Зрілий комерційний проксі-інструмент | Зрілий комерційний проксі-інструмент |
| **MCP/локальний міст автоматизації** | Вбудований, автентифікований маркером, редагування за замовчуванням | Не заявлено в перевірених публічних документах | Не заявлено в перевірених публічних документах |
| **Відкрити шлях внеску** | Публічні теми, дискусії, дорожня карта та PR | Контрольований постачальником продукт | Контрольований постачальником продукт |

На дорожній карті: глибші робочі процеси відтворення/різниць/правил/сценаріїв, покращена інспекція WebSocket і GraphQL, налагодження з урахуванням протоколу AI та Web3/RPC, видимість потоку платежів у стилі x402 та дослідження gRPC/Protobuf, а також підтримка HTTP/2 і HTTP/3.

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

Rockxy створено та підтримується незалежними розробниками. Спонсорство фінансує продовження розвитку, аудити безпеки та нові функції.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

| Рівень | Переваги |
|------|----------|
| **Золотий спонсор** | Логотип на сайті README + документи, запити пріоритетних функцій, прямий канал підтримки |
| **Срібний спонсор** | Логотип на README, назва підтвердження в примітках до випуску |
| **Бронзовий спонсор** | Названа підтвердження в README та документах |
| **Партнер** | Спільна розробка, підтримка інтеграції, ранній доступ до майбутніх функцій |

**Партнерські запити** — компанії-розробники інструментів, охоронні фірми та корпоративні команди, які шукають користувальницькі інтеграції або рішення білої мітки: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Підтримка

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — підтримати розвиток Rockxy
- [Проблеми GitHub](https://github.com/RockxyApp/Rockxy/issues) — звіти про помилки та запити на функції
- [Обговорення GitHub](https://github.com/RockxyApp/Rockxy/discussions) — запитання та чат спільноти
- **Електронна пошта** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Питання безпеки** — див [SECURITY.md](SECURITY.md) за відповідальне розголошення

## Ліцензія

[Загальна публічна ліцензія GNU Affero v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## Зоряна історія

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Зроблено <a href="https://github.com/LocNguyenHuu">Степан</a>. Створено за допомогою Swift, SwiftNIO, SwiftUI та AppKit.</sub>
</p>
