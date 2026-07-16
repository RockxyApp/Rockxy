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
  Локальная альтернатива AGPL-3.0 <a href="#rockxy-vs-alternatives">Проксимен и Чарльз Прокси</a>.
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

## Основные моменты текущего филиала

- Upstream Proxy теперь включает бесплатную/основную автоматическую настройку прокси-сервера с маршрутизацией URL-адресов PAC для `DIRECT`, HTTP и HTTPS маршруты, сохраняя при этом существующие границы SOCKS5 и политики аутентификации.
- Рабочие процессы экспорта теперь охватывают OpenAPI YAML/HTML и публикацию Gist с выбранным трафиком, а также сбор полезных данных с учетом редактирования.
- Инструменты инспектора теперь включают фильтрацию JSONPath/ключ/значение и быстрый предварительный просмотр выбранного текста полезной нагрузки, например JWT.
- Программа установки разработчика Node.js теперь отражает выбранный клиент во время проверки и содержит более полное руководство по использованию локального хоста.
- Центр настройки разработчиков теперь охватывает среды выполнения, браузеры, клиенты, устройства, платформы и среды с фрагментами для конкретных целей, наблюдателями проверок и честным руководством.
- Работа над WebSocket Protobuf продолжается в рамках более обширного направления Rockxy по проверке протоколов.
- Планирование общедоступной дорожной карты теперь включает отладку с учетом протоколов для трафика AI, потоков Web3/RPC, потоков платежей в стиле x402 и более безопасный обмен отредактированными данными.

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

### MCP-сервер для AI-помощников

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Позвольте Claude Desktop или Cursor читать захваченный трафик через локальный сервер MCP. Спросите «почему это 500?» вместо вставки заголовков в чат. Локальный, с учетом редактирования и с открытым исходным кодом.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Переопределение заголовков для каждого хоста с полным контролем над обеими фазами. Вставляйте токены аутентификации в исходящие запросы, удаляйте Set-Cookie из ответов или закрепляйте собственный пользовательский агент — сохраненные в виде именованных правил, которые вы можете переключать в любое время.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Условия сети

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Переключитесь на 3G, EDGE, LTE, Wi-Fi или установите пользовательскую задержку. Ваш ноутбук подключен к оптоволокну; ваши пользователи этого не делают — прежде чем они это сделают, посмотрите UX при RTT 400 мс.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Создание — Редактирование и воспроизведение

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Восстановите любой захваченный HTTP-запрос — измените метод, URL-адрес, заголовки, параметры запроса или тело — и повторите отправку, не покидая Rockxy. Никакого Postman, Insomnia или цикла копирования-вставки. Выполняйте итерации по запросам LLM, уточняйте границы аутентификации или воспроизводите случай сбоя для конечных точек OpenAI, Anthropic и Cohere за считанные секунды.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Сравнить

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Сложите два захваченных ответа рядом и отметьте каждое перевернутое поле — статус, заголовки, ключи JSON, байты тела. Улавливайте тихие регрессии API, недетерминированные выходные данные LLM и оперативно реагируйте на изменения, не передавая ничего в сторонний инструмент сравнения. Параллельный дифференциал показывает, что изменилось; глубокое сравнение JSON игнорирует порядок ключей.

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

Запускайте независимые сеансы захвата параллельно — одна вкладка для промежуточной обработки, одна для рабочей версии и одна для сборки устройства iOS. Каждая вкладка имеет свои собственные фильтры, выбор и состояние инспектора, поэтому переключение контекста ничего не требует.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript-скрипты

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS перехватывает запросы и ответы в тех случаях, когда статическое правило не может охватить — редактирование личных данных, подписание токенов, перезапись полезных данных. Ошибки появляются внутри, а не портят трафик.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Дополнительные функции появятся в ближайшее время

Будущие функции отслеживаются публично и выпускаются только тогда, когда готовы реализация, тесты, поведение конфиденциальности и документация.

### AI-инспекция дорожного движения `Скоро`

Упростите отладку трафика модели в рамках обычного рабочего процесса захвата. Обнаруживайте запросы ИИ, проверяйте выбранные вызовы моделей, диагностируйте потоковые ответы, сравнивайте поведение подсказок и выходных данных и анализируйте цепочки вызовов инструментов без вставки конфиденциальных полезных данных в другой сервис.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Проверка Web3/RPC `Скоро`

Превратите сетевые вызовы эпохи блокчейна в читаемые доказательства отладки. Проверяйте трафик JSON-RPC и Solana RPC, группируйте связанные вызовы в потоки, объясняйте распространенные ошибки RPC и воспроизводите выбранные запросы, не превращаясь в кошелька или обозревателя блоков.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### Отладка потока платежей x402 `Скоро`

Понимание платёжных HTTP-потоков на сетевом уровне. Выделяйте ответы, требующие оплаты, следуйте по пути повторной попытки и сохраняйте доказательства отладки локальными и доступными для редактирования.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### Пакеты отредактированных доказательств `Скоро`

Поделитесь фактами, необходимыми для воспроизведения ошибки, не разглашая секретов. Упакуйте выбранный трафик со сводками протоколов, предварительным просмотром изменений и контекстом на основе источника, который партнер по команде может проверить.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Фильтры и правила с учетом протоколов `Скоро`

Используйте метаданные AI и Web3 там, где Rockxy уже работает: фильтры, значки, дополнительные столбцы, сравнение, правила, настройки разработчика и локальные сводки MCP.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Совместное использование команды и сотрудничество `Скоро`

Отправьте записанную сессию товарищу по команде одним щелчком мыши. Аннотируйте неудачные запросы в режиме реального времени, узнавайте, кто что смотрит, и выполняйте парную отладку HTTPS-трафика без совместного использования экрана. Предназначен для будущего выпуска.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% родная macOS. Нет Электрона. Нет веб-просмотров. SwiftUI + AppKit + SwiftNIO.

## Быстрый старт

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Соберите и запустите в Xcode. Окно приветствия поможет вам выполнить настройку корневого центра сертификации, установку помощника и активацию прокси-сервера.

**Требования:** macOS 14.0+, Xcode 16+, Swift 5.9

Если вы хотите подключить Rockxy к локальному клиенту MCP после установки, см. [Руководство по интеграции MCP](docs/features/mcp.mdx).

## Роккси против альтернатив

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Модель проекта** | Проект с открытым исходным кодом AGPL-3.0 | Собственное коммерческое приложение | Собственное коммерческое приложение |
| **Исходный код** | Публичный, проверяемый, форкируемый | Закрытый исходный код | Закрытый исходный код |
| **Сборка из исходного кода** | Бесплатно с Xcode из этого репозитория | Недоступно из открытого источника | Недоступно из открытого источника |
| **Собственная основа macOS** | Swift + SwiftNIO + SwiftUI/AppKit | Нативное коммерческое приложение для macOS | Кроссплатформенное коммерческое приложение |
| **Локальный захват** | Локальный прокси, сертификаты, помощник и данные сбора остаются на вашем Mac. | Прокси-приложение для ПК | Прокси-приложение для ПК |
| **Рабочий процесс настройки разработчика** | Встроенный центр настройки разработчиков для сред выполнения, клиентов, устройств, платформ и сред. | Руководство по настройке для конкретного продукта | Руководство по настройке для конкретного продукта |
| **Внешний прокси + PAC-маршрутизация** | Восходящий прокси-сервер HTTP/HTTPS, автоматическая настройка PAC и правила обхода | Продуманный коммерческий инструментарий прокси | Продуманный коммерческий инструментарий прокси |
| **MCP/мост локальной автоматизации** | Встроенный, с аутентификацией по токену, редактирование по умолчанию | Не заявлено в проверенных общедоступных документах | Не заявлено в проверенных общедоступных документах |
| **Открытый путь вклада** | Общественные вопросы, дискуссии, дорожная карта и PR | Продукт, контролируемый поставщиком | Продукт, контролируемый поставщиком |

В планах: более глубокие рабочие процессы воспроизведения, различий, правил и сценариев, улучшенная проверка WebSocket и GraphQL, отладка искусственного интеллекта с учетом протоколов и Web3/RPC, видимость потока платежей в стиле x402 и исследование gRPC/Protobuf плюс поддержка HTTP/2 и HTTP/3.

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

Rockxy создается и поддерживается независимыми разработчиками. Спонсорские средства финансируют дальнейшее развитие, аудит безопасности и новые функции.

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

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Сделано <a href="https://github.com/LocNguyenHuu">Стивен</a>. Создано с использованием Swift, SwiftNIO, SwiftUI и AppKit.</sub>
</p>
