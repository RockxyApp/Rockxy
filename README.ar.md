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
  <strong>وكيل تصحيح الأخطاء مفتوح المصدر وقابل للتدقيق لنظام التشغيل macOS.</strong>
</p>

<p align="center">
  يمكنك اعتراض حركة مرور HTTP/HTTPS/WebSocket/GraphQL وفحصها وتعديلها باستخدام تطبيق Swift أصلي يمكنك فحصه وإنشاؤه والوثوق به.<br>
  تم تصميمه لسير عمل تصحيح الأخطاء في عصر API والهواتف المحمولة وMCP والذكاء الاصطناعي وعصر blockchain مع تطور Rockxy.<br>
  بديل محلي أول، AGPL-3.0 لـ <a href="#rockxy-vs-alternatives">بروكسيمان وتشارلز بروكسي</a>.
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

## أبرز الفروع الحالية

- يشتمل Upstream Proxy الآن على تكوين الوكيل التلقائي المجاني/الأساسي مع توجيه عنوان URL لـ PAC `DIRECT` وHTTP وHTTPS مع الحفاظ على SOCKS5 وحدود سياسة المصادقة الحالية.
- تغطي مسارات عمل التصدير الآن OpenAPI YAML/HTML ونشر Gist لحركة المرور المحددة مع إنشاء حمولة قابلة للتنقيح.
- تتضمن أدوات المفتش الآن تصفية JSONPath/المفتاح/القيمة ومعاينات سريعة لنص الحمولة النافعة المحدد مثل JWTs.
- يعكس إعداد مطور Node.js الآن العميل المحدد أثناء التحقق من الصحة ويحتوي على نموذج دليل أكمل للمضيف المحلي.
- يغطي Developer Setup Hub الآن أوقات التشغيل والمتصفحات والعملاء والأجهزة والأطر والبيئات باستخدام مقتطفات خاصة بالهدف ومراقبي التحقق من الصحة ومحتوى الدليل الصادق.
- يستمر عمل WebSocket Protobuf كجزء من اتجاه فحص بروتوكول Rockxy الأكثر ثراءً.
- يتضمن تخطيط خارطة الطريق العامة الآن تصحيحًا مدركًا للأخطاء لحركة مرور الذكاء الاصطناعي، وتدفقات Web3/RPC، وتدفقات الدفع بنمط x402، ومشاركة الأدلة المنقحة بشكل أكثر أمانًا.

## الميزات

الأدوات التي تستخدمها عندما لا تكون أدوات تطوير المتصفح كافية. يعمل تصحيح أخطاء حركة المرور الأساسية لنظامي التشغيل Mac وiOS، وهو موجود في نظام التشغيل macOS، مع الإصدارات العامة وسير العمل المحلي أولاً.

### التقاط حركة المرور

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

افحص حركة مرور HTTP، وHTTPS، وWebSocket، وGraphQL من أي تطبيق Mac، أو CLI، أو جهاز iOS. تنتهي أدوات تطوير المتصفح عند المتصفح — يرى Rockxy بقية مجموعتك.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### تصفية وبحث متقدم

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

تضييق نطاق آلاف الطلبات التي تم التقاطها في ثوانٍ. اجمع بين عوامل تصفية الطريقة والمضيف والحالة والرأس والنص والعملية - أو قم بإجراء بحث عن النص الكامل عبر الجلسة بأكملها.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### خادم MCP لمساعدي الذكاء الاصطناعي

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

اسمح لـ Claude Desktop أو Cursor بقراءة حركة المرور التي تم التقاطها من خلال خادم MCP محلي. اسأل "لماذا فعل هذا 500؟" بدلاً من لصق الرؤوس في الدردشة. محلية، واعية بالتنقيح، ومفتوحة المصدر.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### مركز إعداد المطور

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

انسخ ولصق مقتطفات الوكيل لـ Python وNode.js وGo وRust وcURL وDocker والمتصفحات، ثم انقر فوق "تشغيل اختبار" للتأكد من تدفق حركة المرور فعليًا.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### إدارة الشهادات لتصحيح أخطاء HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

تم إنشاء CA الجذر P-256 ECDSA عند الإطلاق لأول مرة، ومختومًا في سلسلة المفاتيح الخاصة بك. فك تشفير HTTPS من المحاولة الأولى؛ تمر المضيفات المثبتة تلقائيًا.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### وكيل SSL وفك تشفير HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

اختر المضيفين الذين سيحصلون على فك تشفير TLS. تعرض حركة المرور التي تم فك تشفيرها الرؤوس الحقيقية وJSON؛ كل شيء آخر يمر عبر مشفرة. تتيح لك قواعد Wildcard النطاق حسب المجال بنقرة واحدة.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### تجاوز الوكيل

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

تخطي مضيفين محددين حتى لا تدخل التطبيقات المثبتة بالشهادة أو الخدمات الداخلية أو القياس عن بعد المزعج أبدًا في الالتقاط. تحافظ أحرف البدل على القائمة قصيرة ويركز سجل طلباتك على ما يهمك بالفعل.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### قائمة الحظر

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

جعل أي مضيف يفشل. أسقط شبكات الإعلانات، أو أدوات التتبع التابعة لجهات خارجية، أو التبعية غير المستقرة لترى كيف يتدهور تطبيقك عند اختفائه - دون تغيير سطر من التعليمات البرمجية.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### الخريطة المحلية

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

قم بتقديم ملف محفوظ أو شجرة دليل بدلاً من الاستجابة المباشرة. قم بتبديل حمولة JSON أو إعادة تشغيل لقطة أو تثبيت واجهة برمجة التطبيقات غير المستقرة التابعة لجهة خارجية على نسخة محلية أثناء تصحيح الأخطاء.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### خريطة عن بعد

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

أعد كتابة وجهة الطلب الذي تم التقاطه دون لمس رمز التطبيق أو /etc/hosts. قم بتوجيه حركة الإنتاج إلى التدريج، أو خادم التطوير الخاص بك، أو جهاز زميل للحصول على نسخة مكررة من الأخطاء.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### نقاط التوقف والقواعد

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

قم بإيقاف طلب أو استجابة مؤقتًا، أو تحرير الطريقة، أو الرؤوس، أو النص، أو الحالة، ثم تابع. أسرع طريقة لاختبار "ماذا لو قامت واجهة برمجة التطبيقات بإرجاع 401؟" دون لمس الخلفية.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### تعديل الرؤوس

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

قم بإضافة أو إزالة أو استبدال الرؤوس على أي مضيف دون إعادة النشر. اختبر تغييرات CORS أو المصادقة أو ذاكرة التخزين المؤقت في ثوانٍ باستخدام الإعدادات المسبقة المضمنة.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### رؤوس الطلبات والاستجابة المخصصة

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

تجاوز الرؤوس لكل مضيف مع التحكم الكامل في كلتا المرحلتين. أدخل رموز المصادقة المميزة في الطلبات الصادرة، أو قم بإزالة Set-Cookie من الاستجابات، أو قم بتثبيت وكيل مستخدم مخصص - يتم حفظه كقواعد مسماة يمكنك تبديلها في أي وقت.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### ظروف الشبكة

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

يمكنك التبديل إلى شبكات 3G أو EDGE أو LTE أو WiFi أو تأخير مخصص. الكمبيوتر المحمول الخاص بك متصل بالألياف. المستخدمون لديك ليسوا كذلك - شاهد تجربة المستخدم عند 400 مللي ثانية RTT قبل أن يفعلوا ذلك.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### يؤلف - تحرير وإعادة التشغيل

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

أعد بناء أي طلب HTTP تم التقاطه - قم بتغيير الطريقة أو عنوان URL أو الرؤوس أو معلمات الاستعلام أو النص - وأعد الإرسال دون مغادرة Rockxy. لا توجد حلقة ساعي البريد أو الأرق أو حلقة النسخ واللصق. قم بالتكرار على مطالبات LLM أو تشويش حدود المصادقة أو إعادة إنتاج حالة فاشلة لنقاط نهاية OpenAI وAnthropic وCohere في ثوانٍ.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### قارن

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

قم بتجميع استجابتين تم التقاطهما جنبًا إلى جنب وحدد كل حقل تم قلبه - الحالة، والرؤوس، ومفاتيح JSON، ووحدات البايت الأساسية. احصل على انحدارات واجهة برمجة التطبيقات الصامتة، ومخرجات LLM غير الحتمية، والانجراف السريع دون توصيل أي شيء إلى أداة فرق تابعة لجهة خارجية. يسلط الاختلاف جنبًا إلى جنب الضوء على ما تغير؛ تتجاهل مقارنة JSON العميقة ترتيب المفاتيح.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### علامات تبويب المعاينة المخصصة

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

تقديم أجسام الطلب والاستجابة بالطريقة التي تريدها. قم بتثبيت علامات تبويب إضافية في المفتش لـ JSON، أو GraphQL، أو JWT، أو الصورة، أو التنسيق الخاص بك - بحيث يمكن إعادة استخدامها عبر كل طلب تم التقاطه.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### الجلسات والتصدير

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

حفظ الجلسات، واستيراد/تصدير HAR للتسليم عبر الأدوات، ونسخ أي طلب بتنسيق cURL أو JSON. قم بتنقيح رؤوس التفويض وملفات تعريف الارتباط والرموز المميزة لحاملها قبل المشاركة - قم بتسليم زميل في الفريق نسخة تجريبية من الأخطاء دون تسريب الأسرار.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### مساحات عمل متعددة علامات التبويب

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

قم بتشغيل جلسات التقاط مستقلة جنبًا إلى جنب - علامة تبويب واحدة للتشغيل المرحلي، وواحدة للمنتجات، وواحدة لبناء جهاز iOS. تحتوي كل علامة تبويب على عوامل التصفية والتحديد وحالة المفتش الخاصة بها، لذا فإن تبديل السياق لا يكلف شيئًا.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### البرمجة النصية جافا سكريبت

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

ترتبط JS بالطلبات والاستجابات للحالات التي لا يمكن أن تغطيها القاعدة الثابتة - قم بتنقيح معلومات تحديد الهوية الشخصية (PII)، وتوقيع الرموز المميزة، وإعادة كتابة الحمولات. تظهر الأخطاء في السطر بدلاً من إتلاف حركة المرور.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## المزيد من الميزات قريبا

يتم تتبع الميزات المستقبلية علنًا ولا يتم شحنها إلا عندما يكون التنفيذ والاختبارات وسلوك الخصوصية والوثائق جاهزة.

### التفتيش المروري بالذكاء الاصطناعي `قريبًا`

اجعل حركة مرور النموذج أسهل في تصحيح الأخطاء داخل سير عمل الالتقاط العادي. اكتشف طلبات الذكاء الاصطناعي، وافحص مكالمات النماذج المحددة، وتشخيص استجابات البث، وقارن سلوك المطالبة/الإخراج، وفهم سلاسل استدعاء الأدوات دون لصق الحمولات الحساسة في خدمة أخرى.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### فحص Web3/RPC `قريبًا`

تحويل مكالمات الشبكة في عصر blockchain إلى أدلة تصحيح قابلة للقراءة. افحص حركة مرور JSON-RPC وSolana RPC، وقم بتجميع الاستدعاءات ذات الصلة في التدفقات، وشرح أخطاء RPC الشائعة، وأعد تشغيل الطلبات المحددة دون أن تصبح محفظة أو مستكشف حظر.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### تصحيح أخطاء تدفق الدفع إلى x402 `قريبًا`

فهم تدفقات HTTP ذات بوابات الدفع من طبقة الشبكة. قم بتمييز الاستجابات المطلوبة للدفع، واتبع مسار إعادة المحاولة، واحتفظ بدليل تصحيح الأخطاء محليًا وقابلاً للتنقيح.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### حزم الأدلة المنقحة `قريبًا`

شارك الحقائق اللازمة لإعادة إنتاج الخلل دون تسريب الأسرار. قم بتعبئة حركة المرور المحددة بملخصات البروتوكول ومعاينات التنقيح والسياق المدعوم بالمصدر الذي يمكن لزميل الفريق تدقيقه.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### عوامل التصفية والقواعد المدركة للبروتوكول `قريبًا`

استخدم بيانات تعريف AI وWeb3 حيث يعمل Rockxy بالفعل: المرشحات والشارات والأعمدة الاختيارية والمقارنة والقواعد وإعداد المطور وملخصات MCP المحلية.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### مشاركة الفريق والتعاون `قريبًا`

أرسل جلسة تم التقاطها إلى أحد أعضاء الفريق بنقرة واحدة. قم بإضافة تعليقات توضيحية للطلبات الفاشلة بشكل مضمن، ومعرفة من الذي ينظر إلى ماذا في الوقت الفعلي، وتصحيح أخطاء حركة مرور HTTPS بدون مشاركة الشاشة. تستهدف الإصدار المستقبلي.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> نظام التشغيل macOS الأصلي بنسبة 100%. لا إلكترون. لا توجد مشاهدات على شبكة الإنترنت. SwiftUI + AppKit + SwiftNIO.

## بداية سريعة

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

البناء والتشغيل في Xcode. ترشدك نافذة الترحيب خلال عملية إعداد CA الجذر وتثبيت المساعد وتنشيط الوكيل.

**المتطلبات:** ماك 14.0+، Xcode 16+، سويفت 5.9

إذا كنت تريد توصيل Rockxy بعميل MCP محلي بعد التثبيت، فراجع ملف [دليل التكامل MCP](docs/features/mcp.mdx).

## Rockxy مقابل البدائل

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **نموذج المشروع** | AGPL-3.0 مشروع مفتوح المصدر | التطبيق التجاري الخاص | التطبيق التجاري الخاص |
| **كود المصدر** | عام، قابل للتدقيق، قابل للتشعب | مصدر مغلق | مصدر مغلق |
| **البناء من المصدر** | مجانًا مع Xcode من هذا الريبو | غير متوفر من مصدر عام | غير متوفر من مصدر عام |
| **أساس macOS الأصلي** | سويفت + SwiftNIO + SwiftUI/AppKit | تطبيق macOS التجاري الأصلي | تطبيق تجاري متعدد المنصات |
| **الالتقاط المحلي الأول** | يبقى الوكيل المحلي والشهادات والمساعد وبيانات الالتقاط على جهاز Mac الخاص بك | تطبيق وكيل سطح المكتب | تطبيق وكيل سطح المكتب |
| **سير عمل إعداد المطور** | مركز إعداد المطور المدمج لأوقات التشغيل والعملاء والأجهزة والأطر والبيئات | إرشادات الإعداد الخاصة بالمنتج | إرشادات الإعداد الخاصة بالمنتج |
| **الوكيل الخارجي + توجيه PAC** | وكيل HTTP/HTTPS الرئيسي، والتكوين التلقائي لـ PAC، وقواعد التجاوز | أدوات الوكيل التجارية الناضجة | أدوات الوكيل التجارية الناضجة |
| **MCP/جسر الأتمتة المحلية** | مدمج، ومصادق عليه بالرمز، ويتم التنقيح بشكل افتراضي | لم تتم المطالبة بها في المستندات العامة التي تمت مراجعتها | لم تتم المطالبة بها في المستندات العامة التي تمت مراجعتها |
| **فتح مسار المساهمة** | القضايا العامة والمناقشات وخارطة الطريق والعلاقات العامة | المنتج الذي يسيطر عليه البائع | المنتج الذي يسيطر عليه البائع |

على خريطة الطريق: سير عمل إعادة التشغيل/الفرق/القواعد/البرمجة النصية بشكل أعمق، وفحص WebSocket وGraphQL المحسّن، وتصحيح أخطاء الذكاء الاصطناعي المدرك للبروتوكول وWeb3/RPC، ورؤية تدفق الدفع بنمط x402، واستكشاف gRPC/Protobuf بالإضافة إلى دعم HTTP/2 وHTTP/3.

## الأمن

يعترض Rockxy حركة مرور الشبكة - الأمان أساسي وليس اختياريًا.

- يقوم مساعد XPC بالتحقق من صحة المتصلين عبر **مقارنة سلسلة الشهادات**، وليس معرف الحزمة فقط
- يتم تشغيل المكونات الإضافية **JavaScriptCore في وضع الحماية** مع مهلة 5 ثوانٍ، لا يمكن الوصول إلى نظام الملفات/الشبكة
- **التحقق من صحة الإدخال** على جميع الحدود - الحدود القصوى لحجم الجسم، وحدود URI، وحماية DoS، ومنع اجتياز المسار
- أوراق الاعتماد **تم تنقيحه تلقائيًا** في السجلات الملتقطة
- الملفات الحساسة المخزنة مع **0o600 أذونات**

الإبلاغ عن نقاط الضعف عبر [الأمن.md](SECURITY.md). انظر [بنية أمنية كاملة](docs/development/security.mdx) للحصول على التفاصيل.

## خريطة الطريق

إن خريطة الطريق العامة لـ Rockxy موجهة نحو سير العمل وخالية من التاريخ. وهو يركز على الموثوقية، وmacOS UX الأصلي، وسير عمل تصحيح الأخطاء، ودعم البروتوكول، ورؤية حركة المرور في عصر AI/Web3، والوثائق، وإعداد المساهمين.

- [خريطة الطريق.md](ROADMAP.md): توجيه هندسي عام رفيع المستوى
- [خريطة الطريق العامة Rockxy](https://github.com/orgs/RockxyApp/projects/1): الرؤية التشغيلية للمشكلات التي تتبعها خارطة الطريق

## التوثيق

الوثائق الكاملة متوفرة في [مستندات روككسي](docs/index.mdx):

- [دليل البدء السريع](docs/quickstart.mdx) - انهض واعمل في دقائق
- [مركز إعداد المطور](docs/features/developer-setup-hub.mdx) — مقتطفات وقت التشغيل، وأدلة الأجهزة، وتحقيقات التحقق من الصحة، ومصفوفة الدعم
- [التكامل MCP](docs/features/mcp.mdx) — قم بتوصيل Rockxy بعملاء MCP المحليين
- [الهندسة المعمارية](docs/development/architecture.mdx) - محرك الوكيل، نموذج الممثل، تدفق البيانات
- [نموذج الأمان](docs/development/security.mdx) — حدود الثقة، والتحقق من صحة XPC، وإدارة الشهادات
- [قرارات التصميم](docs/development/design-decisions.mdx) — لماذا SwiftNIO، NSTableView، الجهات الفاعلة
- [البناء من المصدر](docs/development/building.mdx) - البناء والاختبار والوبر والتصحيح
- [نمط الكود](docs/development/code-style.mdx) — SwiftLint، وSwiftFormat، والاتفاقيات
- [سجل التغيير](CHANGELOG.md) - الأعمال غير المنشورة والإصدارات الموسومة

## المساهمة

نرحب بالمساهمات - التعليمات البرمجية والاختبارات والمستندات وتقارير الأخطاء وتعليقات تجربة المستخدم.

انظر **[المساهمة.md](CONTRIBUTING.md)** للحصول على تعليمات الإعداد ونمط التعليمات البرمجية وقائمة مراجعة العلاقات العامة الكاملة.

يتم تصنيف القضايا الأولى الجيدة [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). من خلال فتح العلاقات العامة، فإنك توافق على [CLA](CLA.md).

## الرعاة والشركاء

تم إنشاء Rockxy وصيانته بواسطة مطورين مستقلين. تمول الرعاية التطوير المستمر وعمليات التدقيق الأمني ​​والميزات الجديدة.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

| الطبقة | الفوائد |
|------|----------|
| **الراعي الذهبي** | الشعار على موقع README + docs، وطلبات الميزات ذات الأولوية، وقناة الدعم المباشر |
| **الراعي الفضي** | الشعار الموجود على ملف README، مُسمى بالإقرار في ملاحظات الإصدار |
| **الراعي البرونزي** | الإقرار المسمى في README والمستندات |
| **شريك** | التطوير المشترك ودعم التكامل والوصول المبكر إلى الميزات القادمة |

**استفسارات الشراكة** — شركات أدوات المطورين وشركات الأمان وفرق المؤسسات التي تبحث عن عمليات تكامل مخصصة أو حلول ذات علامة بيضاء: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## الدعم

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) - دعم تطوير Rockxy
- [قضايا جيثب](https://github.com/RockxyApp/Rockxy/issues) - تقارير الأخطاء وطلبات الميزات
- [مناقشات جيثب](https://github.com/RockxyApp/Rockxy/discussions) - الأسئلة والدردشة المجتمعية
- **البريد الإلكتروني** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **القضايا الأمنية** - انظر [الأمن.md](SECURITY.md) للإفصاح المسؤول

## الترخيص

[رخصة جنو أفيرو العامة v3.0](LICENSE) — حقوق الطبع والنشر 2024–2026 مملوكة لشركة Rockxy Contributors.

## تاريخ النجوم

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>صنع بواسطة <a href="https://github.com/LocNguyenHuu">ستيفن</a>. تم تصميمه باستخدام Swift وSwiftNIO وSwiftUI وAppKit.</sub>
</p>

</div>
