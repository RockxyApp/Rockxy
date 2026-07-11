<div dir="rtl">

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
  <strong>پروکسی اشکال زدایی منبع باز و قابل ممیزی برای macOS.</strong>
</p>

<p align="center">
  ترافیک HTTP/HTTPS/WebSocket/GraphQL را با یک برنامه بومی Swift که می توانید بازرسی، ایجاد و اعتماد کنید، رهگیری، بازرسی و اصلاح کنید.<br>
  با تکامل Rockxy برای API، تلفن همراه، با کمک MCP، AI و جریان های کاری اشکال زدایی دوران بلاک چین ساخته شده است.<br>
  یک جایگزین محلی اول، AGPL-3.0 برای <a href="#rockxy-vs-alternatives">پروکسی و چارلز پروکسی</a>.
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
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="Rockxy running on macOS" width="800" />
  </a>
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.29.0** — 2026-07-11

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

## نکات برجسته شعبه فعلی

- Upstream Proxy اکنون شامل پیکربندی خودکار پروکسی رایگان/هسته‌ای با مسیریابی PAC URL است `DIRECT` مسیرهای HTTP و HTTPS با حفظ SOCKS5 موجود و مرزهای خط مشی احراز هویت.
- گردش‌های کاری صادرات اکنون OpenAPI YAML/HTML و انتشارات Gist با ترافیک انتخابی را با ساختمان بارگیری آگاهانه از ویرایش پوشش می‌دهد.
- ابزارهای بازرس اکنون شامل فیلتر JSONPath/کلید/مقدار و پیش‌نمایش‌های سریع برای متن بار انتخابی مانند JWT است.
- Node.js Developer Setup اکنون کلاینت انتخاب شده را در حین اعتبارسنجی منعکس می کند و یک راهنمای نمونه لوکال هاست کامل تری دارد.
- Developer Setup Hub اکنون زمان اجرا، مرورگرها، کلاینت‌ها، دستگاه‌ها، چارچوب‌ها و محیط‌ها را با قطعه‌های خاص هدف، ناظران اعتبارسنجی و محتوای راهنمای صادقانه پوشش می‌دهد.
- کار WebSocket Protobuf به عنوان بخشی از مسیر بازرسی پروتکل غنی‌تر Rockxy ادامه دارد.
- برنامه‌ریزی نقشه راه عمومی اکنون شامل اشکال‌زدایی با آگاهی از پروتکل برای ترافیک هوش مصنوعی، جریان‌های Web3/RPC، جریان‌های پرداخت به سبک x402 و اشتراک‌گذاری شواهد ویرایش‌شده ایمن‌تر است.

## ویژگی ها

ابزارهایی که وقتی DevTools مرورگر کافی نیست به آنها دسترسی پیدا می کنید. اشکال‌زدایی ترافیک اصلی برای Mac و iOS کار می‌کند - بومی در macOS، با نسخه‌های عمومی و گردش کار محلی.

### ضبط ترافیک

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

ترافیک HTTP، HTTPS، WebSocket و GraphQL را از هر برنامه Mac، CLI یا دستگاه iOS بررسی کنید. مرورگر DevTools در مرورگر به پایان می رسد - Rockxy بقیه پشته شما را می بیند.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### فیلتر و جستجوی پیشرفته

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

هزاران درخواست ثبت شده را در چند ثانیه محدود کنید. فیلترهای روش، میزبان، وضعیت، سرصفحه، بدنه و فرآیند را با هم ترکیب کنید - یا یک جستجوی متن کامل را در کل جلسه اجرا کنید.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### سرور MCP برای دستیاران هوش مصنوعی

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

اجازه دهید Claude Desktop یا Cursor ترافیک ضبط شده شما را از طریق یک سرور MCP محلی بخواند. بپرسید "چرا این 500 شد؟" به جای چسباندن سرصفحه ها در چت. محلی، ویرایش آگاه، و منبع باز.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### مرکز راه اندازی توسعه دهنده

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

قطعه‌های پروکسی را برای Python، Node.js، Go، Rust، cURL، Docker و مرورگرها کپی کنید، سپس روی Run Test کلیک کنید تا مطمئن شوید که ترافیک واقعا جریان دارد.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### مدیریت گواهی برای اشکال زدایی HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

یک P-256 ECDSA root CA که در اولین پرتاب تولید شد و در Keychain شما مهر و موم شد. رمزگشایی HTTPS در اولین تلاش. هاست های پین شده به صورت خودکار عبور می کنند.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### پروکسی SSL و رمزگشایی HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

انتخاب کنید کدام میزبان ها رمزگشایی TLS را دریافت می کنند. ترافیک رمزگشایی شده هدرهای واقعی و JSON را نشان می دهد. هر چیز دیگری از طریق رمزگذاری عبور می کند. قوانین Wildcard به شما این امکان را می دهد که با یک کلیک دامنه را بر اساس دامنه انتخاب کنید.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### دور زدن پروکسی

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

از میزبان‌های خاص رد شوید تا برنامه‌های دارای گواهی، سرویس‌های داخلی یا تله‌متری پر سر و صدا هرگز وارد عکس‌برداری نشوند. حروف عام لیست را کوتاه نگه می دارند و گزارش درخواست شما را بر آنچه واقعاً به آن اهمیت می دهید متمرکز می شود.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### لیست مسدود کردن

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

هر میزبانی را با شکست مواجه کنید. شبکه‌های تبلیغاتی، ردیاب‌های شخص ثالث، یا وابستگی ضعیف را رها کنید تا ببینید برنامه‌تان پس از از بین رفتن چگونه کاهش می‌یابد — بدون تغییر خط کد.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### نقشه محلی

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

یک فایل ذخیره شده یا درخت دایرکتوری را به جای پاسخ زنده ارائه دهید. هنگام اشکال زدایی، یک بار JSON را تعویض کنید، یک عکس فوری را دوباره پخش کنید، یا یک API شخص ثالث پوسته پوسته را به یک نسخه محلی پین کنید.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### نقشه از راه دور

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

مقصد درخواست ثبت شده را بدون لمس کد برنامه یا /etc/hosts بازنویسی کنید. ترافیک تولید را در مرحله مرحله‌بندی، سرور توسعه‌دهنده یا دستگاه همکار خود برای بازتولید اشکال تکرارپذیر مشخص کنید.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### نقاط شکست و قوانین

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

درخواست یا پاسخ، روش ویرایش، سرصفحه، بدنه یا وضعیت را متوقف کنید، سپس ادامه دهید. سریعترین راه برای آزمایش "اگر API 401 را برگرداند چه؟" بدون دست زدن به باطن

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### هدرها را اصلاح کنید

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

بدون استقرار مجدد، سرصفحه‌ها را در هر میزبانی اضافه، حذف یا جایگزین کنید. تغییرات CORS، auth یا cache را در چند ثانیه با تنظیمات از پیش تعیین شده داخلی آزمایش کنید.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### هدرهای درخواست و پاسخ سفارشی

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

با کنترل کامل بر هر دو فاز، سرصفحه‌ها را لغو کنید. در درخواست‌های خروجی، نشانه‌های احراز هویت را تزریق کنید، Set-Cookie را بر روی پاسخ‌ها حذف کنید، یا یک User-Agent سفارشی را پین کنید - به عنوان قوانین نام‌گذاری شده ذخیره می‌شود که می‌توانید در هر زمان آن را تغییر دهید.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### شرایط شبکه

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

دریچه گاز به 3G، EDGE، LTE، WiFi، یا تاخیر سفارشی. لپ تاپ شما روی فیبر است. کاربران شما اینطور نیستند - قبل از اینکه انجام دهند UX را در 400 میلی ثانیه RTT ببینید.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### نوشتن - ویرایش و پخش مجدد

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

هر درخواست HTTP گرفته شده را بازسازی کنید - روش، URL، هدرها، پارامترهای پرس و جو یا بدنه را تغییر دهید - و بدون خروج از Rockxy دوباره ارسال کنید. بدون پستچی، بی خوابی، یا حلقه کپی پیست. در اعلان‌های LLM تکرار کنید، مرزهای احراز هویت را مخدوش کنید، یا یک مورد ناموفق برای نقاط پایانی OpenAI، Anthropic و Cohere را در چند ثانیه بازتولید کنید.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### مقایسه کنید

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

دو پاسخ گرفته شده را در کنار هم قرار دهید و هر فیلدی را که برگردانده شده است مشاهده کنید - وضعیت، سرصفحه ها، کلیدهای JSON، بایت های بدن. رگرسیون‌های API بی‌صدا، خروجی‌های غیر قطعی LLM، و دریفت سریع را بدون لوله‌کشی چیزی به ابزار تفاوت شخص ثالث دریافت کنید. تفاوت پهلو به پهلو آنچه را که تغییر کرده را برجسته می کند. مقایسه عمیق JSON ترتیب کلید را نادیده می گیرد.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### برگه های پیش نمایش سفارشی

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

بدنه های درخواست و پاسخ را همانطور که می خواهید ارائه دهید. برگه‌های اضافی را برای JSON، GraphQL، JWT، تصویر یا فرمت خودتان به بازرس پین کنید — قابل استفاده مجدد در هر درخواست ثبت‌شده.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### جلسات و صادرات

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

جلسات را ذخیره کنید، HAR را برای انتقال ابزارهای متقابل وارد یا صادر کنید، هر درخواستی را به صورت cURL یا JSON کپی کنید. قبل از اشتراک‌گذاری، سرصفحه‌های مجوز، کوکی‌ها و توکن‌های حامل را ویرایش کنید - بدون افشای اسرار، به هم تیمی‌تان یک بازپرداخت باگ کارآمد بدهید.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### فضاهای کاری چند برگه

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

جلسات ضبط مستقل را در کنار هم اجرا کنید - یک برگه برای مرحله بندی، یکی برای پرود، یکی برای ساخت دستگاه iOS. هر تب فیلترها، انتخاب و حالت بازرس مخصوص به خود را دارد، بنابراین تعویض متن هیچ هزینه ای ندارد.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### اسکریپت جاوا اسکریپت

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS روی درخواست‌ها و پاسخ‌ها برای مواردی که یک قانون ثابت نمی‌تواند پوشش دهد قلاب می‌کند - PII را ویرایش کنید، نشانه‌ها را امضا کنید، بارهای پرداختی را بازنویسی کنید. خطاها به جای خراب کردن ترافیک، به صورت خطی ظاهر می شوند.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## ویژگی های بیشتر به زودی

ویژگی‌های آینده به صورت عمومی ردیابی می‌شوند و تنها زمانی ارسال می‌شوند که پیاده‌سازی، آزمایش‌ها، رفتار حفظ حریم خصوصی و مستندات آماده باشند.

### بازرسی ترافیک هوش مصنوعی `به‌زودی`

اشکال زدایی ترافیک مدل را در گردش کار ضبط معمولی آسان تر کنید. درخواست‌های هوش مصنوعی را شناسایی کنید، تماس‌های مدل انتخاب‌شده را بررسی کنید، پاسخ‌های جریانی را تشخیص دهید، رفتار اعلان/خروجی را مقایسه کنید و زنجیره‌های تماس ابزار را بدون چسباندن بارهای حساس به سرویس دیگر درک کنید.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### بازرسی Web3/RPC `به‌زودی`

تماس‌های شبکه دوران بلاک چین را به شواهد اشکال‌زدایی قابل خواندن تبدیل کنید. ترافیک JSON-RPC و Solana RPC را بررسی کنید، تماس‌های مرتبط را در جریان‌ها گروه‌بندی کنید، خطاهای رایج RPC را توضیح دهید، و درخواست‌های انتخابی را بدون تبدیل شدن به یک کیف پول یا کاوشگر بلاک، دوباره پخش کنید.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### اشکال زدایی جریان پرداخت x402 `به‌زودی`

جریان های HTTP با دریچه پرداخت از لایه شبکه را درک کنید. پاسخ های مورد نیاز پرداخت را برجسته کنید، مسیر تلاش مجدد را دنبال کنید و شواهد اشکال زدایی را محلی و آگاه به ویرایش نگه دارید.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### بسته های شواهد ویرایش شده `به‌زودی`

حقایق مورد نیاز برای بازتولید یک اشکال را بدون افشای اسرار به اشتراک بگذارید. ترافیک انتخابی را با خلاصه‌های پروتکل، پیش‌نمایش‌های ویرایش، و زمینه‌ای که یک هم تیمی می‌تواند بررسی کند، بسته‌بندی کنید.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### فیلترها و قوانین آگاه از پروتکل `به‌زودی`

از ابرداده‌های هوش مصنوعی و Web3 در جایی که Rockxy قبلاً کار می‌کند استفاده کنید: فیلترها، نشان‌ها، ستون‌های اختیاری، مقایسه، قوانین، تنظیمات برنامه‌نویس و خلاصه‌های MCP محلی.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### اشتراک و همکاری تیم `به‌زودی`

یک جلسه ضبط شده را با یک کلیک برای یک هم تیمی ارسال کنید. درخواست‌های ناموفق را به صورت خطی حاشیه‌نویسی کنید، ببینید چه کسی به چه چیزی در زمان واقعی نگاه می‌کند، و ترافیک HTTPS را بدون اشتراک‌گذاری صفحه، اشکال‌زدایی جفت کنید. برای انتشار آینده هدف گذاری شده است.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100٪ macOS بومی. بدون الکترون بدون مشاهده وب SwiftUI + AppKit + SwiftNIO.

## شروع سریع

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

در Xcode بسازید و اجرا کنید. پنجره خوش آمدگویی شما را از طریق راه اندازی root CA، نصب کمکی و فعال سازی پروکسی راهنمایی می کند.

**الزامات:** macOS 14.0+، Xcode 16+، Swift 5.9

اگر می خواهید Rockxy را پس از نصب به یک کلاینت MCP محلی متصل کنید، به این قسمت مراجعه کنید [راهنمای ادغام MCP](docs/features/mcp.mdx).

## Rockxy در مقابل جایگزین

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **مدل پروژه** | پروژه منبع باز AGPL-3.0 | اپلیکیشن تجاری اختصاصی | اپلیکیشن تجاری اختصاصی |
| **کد منبع** | عمومی، قابل ممیزی، چنگال پذیر | منبع بسته | منبع بسته |
| **ساخت از منبع** | رایگان با Xcode از این مخزن | از منبع عمومی در دسترس نیست | از منبع عمومی در دسترس نیست |
| **بنیاد بومی macOS** | Swift + SwiftNIO + SwiftUI/AppKit | برنامه تجاری بومی macOS | اپلیکیشن تجاری بین پلتفرمی |
| **ضبط اول محلی** | پروکسی محلی، گواهی ها، کمک کننده و داده های ضبط در مک شما باقی می مانند | برنامه پروکسی دسکتاپ | برنامه پروکسی دسکتاپ |
| **گردش کار راه اندازی برنامه نویس** | مرکز راه‌اندازی توسعه‌دهنده داخلی برای زمان‌های اجرا، کلاینت‌ها، دستگاه‌ها، چارچوب‌ها و محیط‌ها | راهنمای راه اندازی محصول خاص | راهنمای راه اندازی محصول خاص |
| **پروکسی خارجی + مسیریابی PAC** | پروکسی بالادست HTTP/HTTPS، پیکربندی خودکار PAC و قوانین دور زدن | ابزار پروکسی تجاری بالغ | ابزار پروکسی تجاری بالغ |
| **MCP/پل اتوماسیون محلی** | به طور پیش‌فرض ویرایش داخلی، تأیید شده با رمز | در اسناد عمومی بازبینی شده ادعا نشده است | در اسناد عمومی بازبینی شده ادعا نشده است |
| **باز کردن مسیر مشارکت** | مسائل عمومی، بحث ها، نقشه راه و روابط عمومی | محصول تحت کنترل فروشنده | محصول تحت کنترل فروشنده |

در نقشه راه: بازپخش عمیق‌تر/تفاوت/قوانین/جریان‌های کاری اسکریپت‌نویسی، بازرسی WebSocket و GraphQL بهبودیافته، اشکال‌زدایی هوش مصنوعی آگاه از پروتکل و Web3/RPC، دید جریان پرداخت به سبک x402، و کاوش در gRPC/Protobuf به علاوه پشتیبانی HTTP/2 و HTTP/3.

## امنیت

Rockxy ترافیک شبکه را رهگیری می کند - امنیت اساسی است، نه اختیاری.

- کمک کننده XPC تماس گیرندگان را از طریق اعتبارسنجی می کند **مقایسه گواهی-زنجیره**، نه فقط شناسه بسته
- پلاگین ها اجرا می شوند **جاوا اسکریپت کور سندباکس شده** با وقفه 5 ثانیه ای، بدون دسترسی به سیستم فایل/شبکه
- **اعتبار سنجی ورودی** در همه مرزها - کلاهک های اندازه بدن، محدودیت های URI، حفاظت Regex DoS، جلوگیری از پیمایش مسیر
- اعتبارنامه **به طور خودکار ویرایش شد** در سیاهههای مربوط
- فایل های حساس ذخیره شده با **مجوزهای 0o600**

گزارش آسیب پذیری ها از طریق [SECURITY.md](SECURITY.md). را ببینید [معماری امنیتی کامل](docs/development/security.mdx) برای جزئیات

## نقشه راه

نقشه راه عمومی Rockxy مبتنی بر گردش کار و بدون تاریخ است. این برنامه بر قابلیت اطمینان، رابط کاربری macOS بومی، جریان‌های کاری اشکال‌زدایی، پشتیبانی از پروتکل، دید ترافیک دوره AI/Web3، اسناد و مدارک و نصب مشارکت‌کننده تمرکز دارد.

- [ROADMAP.md](ROADMAP.md): رشته مهندسی عمومی سطح بالا
- [نقشه راه عمومی Rockxy](https://github.com/orgs/RockxyApp/projects/1): دید عملیاتی برای مسائل ردیابی شده توسط نقشه راه

## مستندات

اسناد کامل موجود در [Rockxy Docs](docs/index.mdx):

- [راهنمای شروع سریع](docs/quickstart.mdx) - در عرض چند دقیقه بلند شوید و اجرا کنید
- [مرکز راه اندازی توسعه دهنده](docs/features/developer-setup-hub.mdx) - قطعه‌های زمان اجرا، راهنمای دستگاه، پروب‌های اعتبارسنجی و ماتریس پشتیبانی
- [یکپارچه سازی MCP](docs/features/mcp.mdx) - Rockxy را به مشتریان MCP محلی متصل کنید
- [معماری](docs/development/architecture.mdx) - موتور پروکسی، مدل بازیگر، جریان داده
- [مدل امنیتی](docs/development/security.mdx) - مرزهای اعتماد، اعتبار سنجی XPC، مدیریت گواهی
- [تصمیمات طراحی](docs/development/design-decisions.mdx) - چرا SwiftNIO، NSTableView، بازیگران
- [ساختمان از منبع](docs/development/building.mdx) - ساخت، تست، پرز و اشکال زدایی
- [سبک کد](docs/development/code-style.mdx) - SwiftLint، SwiftFormat، و قراردادها
- [تغییرات](CHANGELOG.md) - آثار منتشرنشده و انتشارات برچسب‌گذاری شده

## کمک کردن

مشارکت‌ها استقبال می‌شود - کد، آزمایش‌ها، اسناد، گزارش‌های اشکال، و بازخورد UX.

ببینید **[CONTRIBUTING.md](CONTRIBUTING.md)** برای دستورالعمل های راه اندازی، سبک کد، و چک لیست کامل روابط عمومی.

اولین مسائل خوب برچسب گذاری شده اند [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). با باز کردن روابط عمومی، با [CLA](CLA.md).

## حامیان و شرکا

Rockxy توسط توسعه دهندگان مستقل ساخته و نگهداری می شود. حامیان مالی توسعه مستمر، ممیزی های امنیتی و ویژگی های جدید را تامین می کنند.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

| ردیف | مزایا |
|------|----------|
| **حامی طلایی** | نشان‌واره در سایت README + اسناد، درخواست‌های ویژگی اولویت، کانال پشتیبانی مستقیم |
| **حامی نقره ای** | لوگو در README که در یادداشت‌های انتشار به نام تصدیق نامگذاری شده است |
| **حامی برنز** | تأیید نام در README و اسناد |
| **شریک** | توسعه مشترک، پشتیبانی از یکپارچه سازی، دسترسی زودهنگام به ویژگی های آینده |

**سوالات مشارکت** - شرکت‌های ابزار توسعه‌دهنده، شرکت‌های امنیتی و تیم‌های سازمانی که به دنبال ادغام‌های سفارشی یا راه‌حل‌های برچسب سفید هستند: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## پشتیبانی کنید

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) - از توسعه Rockxy پشتیبانی کنید
- [مشکلات GitHub](https://github.com/RockxyApp/Rockxy/issues) - گزارش اشکال و درخواست ویژگی
- [بحث های GitHub](https://github.com/RockxyApp/Rockxy/discussions) - سوالات و چت جامعه
- **ایمیل** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **مسائل امنیتی** - ببینید [SECURITY.md](SECURITY.md) برای افشای مسئولانه

## مجوز

[مجوز عمومی عمومی GNU Affero نسخه 3.0](LICENSE) - حق چاپ 2024–2026 Rockxy Contributors.

## تاریخچه ستاره

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>ساخته شده توسط <a href="https://github.com/LocNguyenHuu">استفان</a>. ساخته شده با Swift، SwiftNIO، SwiftUI و AppKit.</sub>
</p>

</div>
