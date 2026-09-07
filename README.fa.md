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
  یک جایگزین local-first با مجوز AGPL-3.0 برای <a href="#rockxy-در-مقابل-جایگزین">Proxyman و Charles Proxy</a>.
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

## نکات برجسته شعبه فعلی

- AI Assistant اکنون یک یا چند request انتخاب‌شده را با تحلیل محلی داخلی یا مدل Ollama/provider پیکربندی‌شده اختیاری بررسی می‌کند، با تأیید صریح Review Data، ویرایش محدود، پاسخ‌های streaming، آشکارسازی شواهد و handoffهایی که کاربر آغاز می‌کند.
- sidebar بومی اکنون شامل Focus Sets قابل استفاده مجدد برای scopeهای app/domain/path به‌همراه Noise Control در سطح workspace است که domain یا pathهای منطبق را بدون توقف capture پنهان می‌کند.
- workspace اصلی اکنون از split viewهای بومی عمودی و افقی برای Context Dock و بازرس پایینی استفاده می‌کند و جداکننده‌های تمام‌ارتفاع، جداکننده‌های هماهنگ toolbar/footer و تغییر اندازه خودکار چیدمان را حفظ می‌کند.
- Upstream Proxy اکنون شامل پیکربندی خودکار پروکسی رایگان/هسته‌ای با مسیریابی PAC URL است `DIRECT` مسیرهای HTTP و HTTPS با حفظ SOCKS5 موجود و مرزهای خط مشی احراز هویت.
- گردش‌های کاری صادرات اکنون OpenAPI YAML/HTML و انتشارات Gist با ترافیک انتخابی را با ساختمان بارگیری آگاهانه از ویرایش پوشش می‌دهد.
- ابزارهای بازرس اکنون شامل فیلتر JSONPath/کلید/مقدار و پیش‌نمایش‌های سریع برای متن بار انتخابی مانند JWT است.
- بازرسی ترافیک AI و Web3 اکنون برچسب‌های پروتکل، برگه‌های بازرس و خلاصه‌های اشکال‌زدایی را برای تماس‌های مدل شناخته‌شده، ترافیک JSON-RPC و تلمیحات پرداخت به‌سبک x402 اضافه می‌کند.
- Node.js Developer Setup اکنون کلاینت انتخاب شده را در حین اعتبارسنجی منعکس می کند و یک راهنمای نمونه لوکال هاست کامل تری دارد.
- Developer Setup Hub اکنون زمان اجرا، مرورگرها، کلاینت‌ها، دستگاه‌ها، چارچوب‌ها و محیط‌ها را با قطعه‌های خاص هدف، ناظران اعتبارسنجی و محتوای راهنمای صادقانه پوشش می‌دهد.
- بازرسی WebSocket binary-frame اکنون heuristic محدود و on-demand برای Protobuf wire-format دارد، بدون افزودن decoder work به capture hot path.
- نقشه راه عمومی اکنون بر قوانین protocol-aware عمیق‌تر، replay، comparison و اشتراک‌گذاری امن‌تر شواهد ویرایش‌شده تمرکز دارد.

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

### Focus Sets وNoise Control

بررسی‌های تکراری را به scopeهای قابل استفاده مجدد در نوار کناری تبدیل کنید. Focus Sets شامل‌های app، domain و path را با excludeهای domain/path ترکیب می‌کند، بین اجراها باقی می‌ماند و در هر workspace در دسترس است. Noise Control همچنان telemetry و ترافیک کم‌ارزش را capture می‌کند اما آنها را در workspace فعلی پنهان می‌کند.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant ترافیک انتخاب‌شده را کنار جدول request و نوار کناری native توضیح می‌دهد" width="820" />

یک یا چند request ضبط‌شده را انتخاب کنید و بپرسید چه اتفاقی افتاد، چه چیزی شکست، چه چیزی تغییر کرد یا بعداً چه چیزی باید بررسی شود. Rockxy ابتدا روی همین Mac تحلیل مبتنی بر شواهد انجام می‌دهد؛ مدل تنظیم‌شده Ollama یا provider فقط پس از نمایش context دقیق، محدود و ویرایش‌شده در Review Data اجرا می‌شود. پاسخ‌ها می‌توانند source request را آشکار و workflow پیگیری native را آماده کنند، اما ترافیک را تغییر نمی‌دهند و actionها را خودکار اجرا نمی‌کنند.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[راهنمای AI Assistant را بخوانید](docs/features/ai-assistant.mdx).

### سرور MCP برای کلاینت‌های هوش مصنوعی خارجی

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

اجازه دهید Claude Desktop یا Cursor ترافیک ضبط‌شده شما را از طریق ده ابزار فقط‌خواندنی در سرور MCP محلی Rockxy بررسی کند. بپرسید "چرا این 500 شد؟" به جای چسباندن سرصفحه‌ها در چت. پیاده‌سازی منبع باز است، با token احراز هویت می‌شود و ویرایش داده‌های حساس را به‌صورت پیش‌فرض فعال نگه می‌دارد.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

هر سرصفحه درخواست یا پاسخ را به یک ستون درجه‌یک در جدول ترافیک ارتقا دهید. منابع درخواست و پاسخ را جدا نگه دارید، سرصفحه‌های موردنظرتان را ذخیره کنید، سپس request IDها، trace IDها، وضعیت cache یا فراداده سفارشی را بدون باز کردن هر بازرس مرور کنید.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### شرایط شبکه

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

دریچه گاز به 3G، EDGE، LTE، WiFi، یا تاخیر سفارشی. لپ تاپ شما روی فیبر است. کاربران شما اینطور نیستند - قبل از اینکه انجام دهند UX را در 400 میلی ثانیه RTT ببینید.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### نوشتن - ویرایش و پخش مجدد

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

هر درخواست HTTP گرفته‌شده را بازسازی کنید - روش، URL، هدرها، پارامترهای پرس‌وجو یا بدنه را تغییر دهید - و بدون خروج از Rockxy دوباره ارسال کنید. بدون حلقه کپی‌وپیست به Postman، Insomnia یا curl. روی promptهای LLM تکرار کنید، مرزهای احراز هویت را fuzz کنید، یا یک مورد ناموفق برای نقاط پایانی OpenAI، Anthropic و Cohere را در چند ثانیه بازتولید کنید.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### مقایسه کنید

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

دو تراکنش گرفته‌شده یا payload چسبانده‌شده را در کنار هم قرار دهید و هر فیلدی را که تغییر کرده مشاهده کنید - وضعیت، سرصفحه‌ها، کلیدهای JSON یا بایت‌های بدنه. رگرسیون‌های API خاموش، خروجی‌های غیرقطعی LLM و prompt drift را بدون ارسال چیزی به ابزار diff شخص ثالث دریافت کنید.

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="فضاهای کاری چندبرگه Rockxy با نماهای مستقل فیلترشده از یک ضبط زنده" width="820" />

نماهای بررسی مستقل از یک ضبط زنده را کنار هم نگه دارید — یک برگه برای ترافیک staging، یکی برای production و یکی برای جریان دستگاه iOS. هر برگه فیلتر، مرتب‌سازی، انتخاب، محدوده نوار کناری و وضعیت بازرس خود را دارد، اما پروکسی و تراکنش‌های ضبط‌شده مشترک هستند.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### اسکریپت جاوا اسکریپت

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS روی درخواست‌ها و پاسخ‌ها برای مواردی که یک قانون ثابت نمی‌تواند پوشش دهد قلاب می‌کند - PII را ویرایش کنید، نشانه‌ها را امضا کنید، بارهای پرداختی را بازنویسی کنید. خطاها به جای خراب کردن ترافیک، به صورت خطی ظاهر می شوند.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## بازرسی آگاه از پروتکل

Rockxy بازرسی protocol-aware برای AI، Web3 RPC و x402 را در workflow معمول debugging HTTP ارائه می‌دهد.

### بازرسی ترافیک هوش مصنوعی

Rockxy درخواست‌های AI شناخته‌شده را در گردش‌کار معمول capture شناسایی می‌کند. تماس‌های مدل انتخاب‌شده، وضعیت streaming، فیلدهای usage در صورت وجود، هشدارها، retrieval hints و خلاصه‌های tool-call را بدون چسباندن payloadهای حساس به سرویس دیگر بررسی کنید.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### بازرسی Web3/RPC

Rockxy تماس‌های شبکه دوران بلاک‌چین را به شواهد اشکال‌زدایی قابل‌خواندن تبدیل می‌کند. ترافیک HTTP JSON-RPC به‌سبک EVM و Solana را با provider host، request ID، method، batch summary، error، chain، transaction، payload و debug-intent بررسی کنید، بدون تبدیل Rockxy به کیف پول یا کاوشگر بلاک.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### راهنمای جریان پرداخت x402

Rockxy تلمیحات payment-required و مبتنی بر retry را برجسته می‌کند تا جریان‌های HTTP دارای دریچه پرداخت از لایه شبکه قابل‌فهم باشند، در حالی که شواهد اشکال‌زدایی محلی و آگاه به ویرایش باقی می‌مانند.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## کارهای آینده

بخش‌های زیر جهت عمومی را توصیف می‌کنند، نه رفتار فعلی را.

### قوانین آگاه از پروتکل

Rockxy امروز می‌تواند ترافیک AI و Web3 را برچسب‌گذاری و بررسی کند. تطبیق عمیق‌تر قوانین بر اساس model، tool call، متد JSON-RPC، chain، transaction hash یا batch subcall همچنان کار آینده است؛ ابزارهای فعلی تغییر ترافیک همچنان URL، متد HTTP و سرصفحه‌ها را تطبیق می‌دهند.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### بسته های شواهد ویرایش شده `به‌زودی`

حقایق مورد نیاز برای بازتولید یک اشکال را بدون افشای اسرار به اشتراک بگذارید. ترافیک انتخابی را با خلاصه‌های پروتکل، پیش‌نمایش‌های ویرایش، و زمینه‌ای که یک هم تیمی می‌تواند بررسی کند، بسته‌بندی کنید.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### اشتراک و همکاری تیم `به‌زودی`

یک جلسه ضبط شده را با یک کلیک برای یک هم تیمی ارسال کنید. درخواست‌های ناموفق را به صورت خطی حاشیه‌نویسی کنید، ببینید چه کسی به چه چیزی در زمان واقعی نگاه می‌کند، و ترافیک HTTPS را بدون اشتراک‌گذاری صفحه، اشکال‌زدایی جفت کنید. برای انتشار آینده هدف گذاری شده است.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> پوسته اپلیکیشن بومی macOS — بدون Electron. SwiftUI + AppKit + SwiftNIO، با WebKit که فقط برای پیش‌نمایش بدنه HTML استفاده می‌شود.

## شروع سریع

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

در Xcode بسازید و اجرا کنید. پنجره خوش آمدگویی شما را از طریق راه اندازی root CA، نصب کمکی و فعال سازی پروکسی راهنمایی می کند.

**الزامات:** macOS 14.0+، Xcode 16+، Swift 5.9

اگر می خواهید Rockxy را پس از نصب به یک کلاینت MCP محلی متصل کنید، به این قسمت مراجعه کنید [راهنمای ادغام MCP](docs/features/mcp.mdx).

## Rockxy در مقابل گزینه های جایگزین

ماتریس اصلی پراکسی های اشکال زدایی وب همه منظوره را پوشش می دهد. تست امنیتی
مجموعه ها و مرورگر/ رهگیرهای مبتنی بر API با همپوشانی جریان کار قابل توجه
به طور جداگانه لیست شده اند بنابراین بر خلاف محصولات به عنوان قابل تعویض ارائه نمی شوند.
تحلیلگرهای بسته و مشتریان فقط API خارج از این مقایسه هستند.

### پروکسی های مستقیم اشکال زدایی وب

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **شکل محصول** | پروکسی بومی اشکال زدایی macOS | برنامه بومی macOS؛ نسخه های ویندوز/لینوکس مبتنی بر Electron | پروکسی اشکال زدایی دسکتاپ بین پلتفرمی | کراس پلتفرم CLI/TUI و بسته ابزار پروکسی رابط کاربری وب | کراس پلتفرم پروکسی دسکتاپ Electron و سرویس گیرنده HTTP | پروکسی اشکال زدایی دسکتاپ بین پلتفرمی |
| **منبع و مدل ساخت** | منبع جامعه عمومی تحت AGPL-3.0-or-later؛ قابل ساخت با Xcode. DMG رسمی همچنین شامل اجزای پایین دستی غیرعمومی | منبع بسته؛ هیچ منبع برنامه عمومی در مطالب رسمی بررسی شده مشخص نشده است | منبع بسته؛ هیچ منبع برنامه عمومی در مطالب رسمی بررسی شده مشخص نشده است | منبع مجوز عمومی MIT؛ قابل ساخت از منبع | منبع دسکتاپ عمومی AGPL; قابل ساخت از منبع؛ باینری های منتشر شده دارای گزینه های مجوز اضافی هستند | منبع بسته؛ به عنوان کد شی تحت Fiddler Everywhere EULA |
| **گرفتن و راه اندازی** | پروکسی سیستم محلی با راه اندازی راهنما برای برنامه های مک، زمان اجرا، دستگاه های iOS و شبیه ساز | راه اندازی خودکار برای برنامه های مک، زمان اجرا و دستگاه های تلفن همراه | پروکسی محلی با macOS، iOS، و راهنماهای راه اندازی چند پلتفرمی | حالت های ضبط منظم، محلی، WireGuard، معکوس، شفاف و سایر حالت های ضبط | رهگیری پراکسی هدفمند و دستی برای مرورگرها، زمان اجرا، کانتینرها و دستگاه های تلفن همراه | حالت های ضبط سیستم، شبکه، مرورگر، ترمینال، صریح و از راه دور دستگاه |
| **تغییر و تمسخر** | نقاط شکست، Map Local/Remote، قوانین سرصفحه، مسدود کردن، و قوانین تاخیر | نقاط شکست، Map Local/Remote، لیست های بلاک، شرایط شبکه و قوانین JavaScript | نقاط شکست، بازنویسی، Map Local/Remote، مسدود کردن، و throttling | Map Local/Remote، اصلاح بدنه/هدر، مسدود کردن، و پخش مجدد سرور | نقاط شکست به علاوه بازنویسی، تغییر مسیر، ساختگی و تزریق خطا مبتنی بر قانون. برخی از اتوماسیون ها با طرح محدود هستند | قوانین، نقاط شکست، تغییر مسیرها، اصلاح پاسخ، و تمسخر |
| **بازپخش و مقایسه** | نوشتن/بازپخش به اضافه درخواست محلی، هدر و مقایسه بدنه | نوشتن، تکرار، و تفاوت | تکرار و ویرایش درخواست ها | پخش مجدد سمت کلاینت و سمت سرور | سرویس گیرنده HTTP داخلی برای نوشتن و ارسال درخواست | API آهنگساز، پخش مجدد ترافیک و مقایسه ترافیک به صورت بتا مستند شده است |
| ** گردش کار WebSocket ** | بازرسی متن/قاب باینری با اکتشافی محدود Protobuf | بازرسی WS/WSS؛ اسکریپت ها می توانند URL/هدرهای دست دادن را تغییر دهند، نه پیام ها | پشتیبانی WebSocket در تاریخچه نسخه رسمی مستند شده است | رهگیری و برنامه نویسی WebSocket. پخش مجدد WebSocket پشتیبانی نمی شود | بازرسی WebSocket به اضافه قوانین خاص WebSocket | ضبط و بازرسی WebSocket |
| **اسکریپت نویسی و توسعه پذیری** | Sandboxed قلاب JavaScriptCore با API محدود و زمان اجرا | برنامه نویسی درخواست/پاسخ JavaScript | بازنویسی قوانین و یک رابط وب کنترلی. هیچ ویژگی کلی برنامه نویسی JavaScript مستند نشده است | افزونه های Python و اتوماسیون خط فرمان | اتوماسیون مبتنی بر قانون به همراه منابع عمومی و کتابخانه های پراکسی | اتوماسیون مبتنی بر قانون؛ هیچ ویژگی برنامه نویسی عمومی شخص اول مستند نشده |
| **مسیریابی بالادست** | [پراکسی بالادست HTTP/HTTPS و مسیریابی URL PAC](docs/features/upstream-proxy.mdx); خط مشی انجمن، احراز هویت پروکسی و SOCKS5 را غیرفعال می کند و قوانین بای پس را در سه | مسیریابی خارجی HTTP/HTTPS/SOCKS و PAC با قوانین بای پس | پراکسی های خارجی HTTP/HTTPS/SOCKS با احراز هویت و قوانین دور زدن | حالت بالادستی HTTP/HTTPS به همراه حالت های شنونده معکوس و SOCKS | تنظیمات بالادستی سیستم، HTTP، HTTPS و SOCKS؛ ممکن است محدودیت های طرح اعمال شود | زنجیره‌سازی خودکار به پراکسی‌های سیستم به علاوه ضبط پراکسی معکوس |
| **AI و MCP** | [دستیار هوش مصنوعی درون برنامه ای](docs/features/ai-assistant.mdx) و [MCP داخلی داخلی](docs/features/mcp.mdx) با 10 ابزار فقط خواندنی، احراز هویت رمز و ویرایش به طور پیش فرض فعال | MCP داخلی برای مشتریان هوش مصنوعی خارجی، از جمله خواندن ترافیک و کنترل‌های برنامه/قانون | مستند نشده | مستند نشده | یک پل محلی همراه MCP در منبع رسمی فعلی موجود است. هیچ دستیار درون برنامه ای مستند نیست | MCP داخلی به‌علاوه یک دستیار اشکال‌زدایی حرفه‌ای که مستندات فعلی آن نیاز به چسباندن جزئیات ترافیک ضبط‌شده در چت دارد |

### ابزارهای رهگیری مجاور

این محصولات به طور معنی‌داری با Rockxy همپوشانی دارند، اما در تست‌های امنیتی پیشرو هستند.
قوانین مرورگر، یا گردش‌های کاری مشتری API به جای همان هدف عمومی
فوکوس بومی اشکال زدایی-پراکسی.

| **محصول** | **چرا مجاور است** | **منبع و مدل ساخت** | **همپوشانی مرتبط** | **AI و MCP** |
|---|---|---|---|---|
| **Burp Suite** | مجموعه تست امنیت وب با یک پروکسی رهگیری | برنامه منبع بسته؛ EULA آن بیان می کند که کاربران هیچ حقی نسبت به منبع برنامه ندارند. برنامه های افزودنی می توانند از مجوزهای جداگانه استفاده کنند | رهگیری پراکسی و مطابقت/تعویض، تکرارکننده، WebSocket، پروکسی upstream/SOCKS، و اکوسیستم توسعه بزرگ | Burp AI در Repeater موجود است. PortSwigger همچنین یک افزونه عمومی سرور MCP را برای مشتریان هوش مصنوعی خارجی دارد |
| **ZAP** | اسکنر امنیتی و پروکسی رهگیری | منبع عمومی Apache-2.0; قابل ساخت از منبع | رهگیری/ویرایش، ارسال مجدد دستی، نقاط شکست و اسکریپت های WebSocket، اسکریپت نویسی چند زبانه، افزونه ها و اتوماسیون | یکپارچه سازی رسمی MCP و افزونه های پشتیبانی اختیاری LLM |
| **Requestly HTTP Interceptor** | افزونه مرورگر و ابزار رهگیری دسکتاپ بین پلتفرمی/ساختار | منبع رهگیر دسکتاپ عمومی AGPL. درخواست جداگانه مشتری API طبق اطلاعیه مخزن عمومی آن اختصاصی است | ضبط در سطح سیستم/مرورگر، تغییر مسیر، Map Local/Remote، اصلاح سرصفحه/بدنه، تبدیل JavaScript، تمسخر، و شبیه سازی تاخیر/خطا | یک سرور رسمی جداگانه MCP قوانین و گروه ها را مدیریت می کند. هیچ دستیار تحلیل ترافیک درون برنامه ای مستند نشده است |

در دسترس بودن ویژگی می تواند بر اساس نسخه، طرح، پلتفرم یا افزونه متفاوت باشد.
"مستند نشده" به این معنی است که قابلیتی در شخص اول رسمی یافت نشد
منابع بررسی شده در 2026-08-22؛ دلیلی بر عدم وجود قابلیت نیست.
بیانیه های محصول و ویژگی های بالا با اسناد فروشنده بررسی شد،
مخازن منبع نگهداری شده توسط فروشنده، یا شرایط مجوز فروشنده در آن تاریخ و
ممکن است تغییر کند. نام محصول و علائم تجاری متعلق به صاحبان مربوطه می باشد.
Rockxy به آنها وابسته نیست یا توسط آنها تأیید شده است. اصلاحات استقبال می شود
از طریق ردیاب مسئله Rockxy.

در نقشه راه: قوانین آگاه از پروتکل عمیق‌تر، بسته‌های شواهد ویرایش‌شده ایمن‌تر، جریان‌های کاری تکرار و مقایسه قوی‌تر، راهنمایی‌های گسترده‌تر برای راه‌اندازی برنامه‌نویس، و ادامه تحقیقات HTTP/2 و HTTP/3.

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
- [AI Assistant](docs/features/ai-assistant.mdx) — ترافیک انتخاب‌شده را محلی یا با مدل تنظیم‌شده پس از Review Data بررسی کنید
- [فیلتر و جستجو](docs/core-features/filters-and-search.mdx) — sidebar scope، Focus Sets، Noise Control، toolbar filter و search
- [بازرسی AI و Web3](docs/features/ai-web3-inspection.mdx) — ترافیک شناخته‌شده model API، JSON-RPC و x402 را بررسی کنید
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

Rockxy به‌صورت مستقل نگهداری می‌شود. حمایت مالی به تأمین توسعه مستمر، زیرساخت انتشار، مستندات و کارهای امنیتی کمک می‌کند.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy از نظر مالی توسط [Open Source Collective](https://docs.oscollective.org/) میزبانی می‌شود. کمک‌ها و هزینه‌های پروژه در [صفحه عمومی Open Collective راکسی](https://opencollective.com/rockxy) ثبت می‌شوند تا حامیان دیدی شفاف از دریافت و مصرف منابع مالی داشته باشند.

| سطح | مشارکت | آنچه پشتیبانی می‌کند |
|-----|---------|----------------------|
| **Backer** | از ۵ دلار در ماه | نگهداری متن‌باز، مستندات، آزمایش‌ها و انتشارها |
| **Builder** | از ۲۵ دلار در ماه | آزمایش رگرسیون، بهبود عملکرد و جریان‌های کاری روزمره اشکال‌زدایی |
| **Sponsor** | ۱۰۰ دلار در ماه | نگهداری بلندمدت ابزاری با تمرکز بر حریم خصوصی که برای توسعه‌دهندگان رایگان می‌ماند |
| **Sustaining Sponsor** | ۵۰۰ دلار در ماه | نگهداری و توسعه متمرکز محصول، شامل خودکارسازی انتشار و پشتیبانی پروتکل‌ها |

**سوالات مشارکت** - شرکت‌های ابزار توسعه‌دهنده، شرکت‌های امنیتی و تیم‌های سازمانی که به دنبال ادغام‌های سفارشی یا راه‌حل‌های برچسب سفید هستند: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## پشتیبانی کنید

- [Open Collective](https://opencollective.com/rockxy/donate) - از طریق بودجه شفاف پروژه به Rockxy کمک کنید
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) - از توسعه Rockxy پشتیبانی کنید
- [مشکلات GitHub](https://github.com/RockxyApp/Rockxy/issues) - گزارش اشکال و درخواست ویژگی
- [بحث های GitHub](https://github.com/RockxyApp/Rockxy/discussions) - سوالات و چت جامعه
- **ایمیل** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **مسائل امنیتی** - ببینید [SECURITY.md](SECURITY.md) برای افشای مسئولانه

## مجوز

[مجوز عمومی عمومی GNU Affero نسخه 3.0](LICENSE) - حق چاپ 2024–2026 Rockxy Contributors.

## تاریخچه ستاره

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>ساخته شده توسط <a href="https://github.com/LocNguyenHuu">Stephen</a>. ساخته شده با Swift، SwiftNIO، SwiftUI و AppKit.</sub>
</p>

</div>
