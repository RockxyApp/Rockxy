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
  بديل local-first بترخيص AGPL-3.0 لـ <a href="#rockxy-مقابل-البدائل">Proxyman و Charles Proxy</a>.
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

## أبرز الفروع الحالية

- يحقق AI Assistant الآن في طلب واحد أو أكثر من الطلبات المحددة باستخدام تحليل محلي مدمج أو نموذج Ollama/provider مُعد اختياريًا، مع تأكيد Review Data صريح، وتنقيح محدود، واستجابات بث، وكشف الأدلة، وعمليات handoff يبدأها المستخدم.
- يتضمن الشريط الجانبي الأصلي الآن Focus Sets قابلة لإعادة الاستخدام لنطاقات app/domain/path بالإضافة إلى Noise Control على مستوى مساحة العمل يخفي النطاقات أو المسارات المطابقة دون إيقاف الالتقاط.
- تستخدم مساحة العمل الرئيسية الآن split views أصلية عمودية وأفقية لـ Context Dock والمفتش السفلي، مع الحفاظ على فواصل بكامل الارتفاع، وفواصل toolbar/footer منسقة، وإعادة تحجيم تلقائية للتخطيط.
- يشتمل Upstream Proxy الآن على تكوين الوكيل التلقائي المجاني/الأساسي مع توجيه عنوان URL لـ PAC `DIRECT` وHTTP وHTTPS مع الحفاظ على SOCKS5 وحدود سياسة المصادقة الحالية.
- تغطي مسارات عمل التصدير الآن OpenAPI YAML/HTML ونشر Gist لحركة المرور المحددة مع إنشاء حمولة قابلة للتنقيح.
- تتضمن أدوات المفتش الآن تصفية JSONPath/المفتاح/القيمة ومعاينات سريعة لنص الحمولة النافعة المحدد مثل JWTs.
- يضيف فحص حركة AI وWeb3 الآن تسميات البروتوكول وعلامات تبويب المفتش وملخصات التصحيح لاستدعاءات النماذج المعترف بها وحركة JSON-RPC وتلميحات الدفع بأسلوب x402.
- يعكس إعداد مطور Node.js الآن العميل المحدد أثناء التحقق من الصحة ويحتوي على نموذج دليل أكمل للمضيف المحلي.
- يغطي Developer Setup Hub الآن أوقات التشغيل والمتصفحات والعملاء والأجهزة والأطر والبيئات باستخدام مقتطفات خاصة بالهدف ومراقبي التحقق من الصحة ومحتوى الدليل الصادق.
- يتضمن فحص WebSocket binary-frame الآن heuristic محدودة وعند الطلب لتنسيق Protobuf wire-format دون إضافة decoder work إلى capture hot path.
- تركز خارطة الطريق العامة الآن على قواعد أعمق مدركة للبروتوكول وإعادة التشغيل والمقارنة ومشاركة أدلة منقحة أكثر أمانًا.

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

### Focus Sets وNoise Control

حوّل التحقيقات المتكررة إلى نطاقات قابلة لإعادة الاستخدام في الشريط الجانبي. تجمع Focus Sets بين تضمينات التطبيق والنطاق والمسار واستبعادات النطاق/المسار، وتستمر بين عمليات التشغيل، وتتوفر في كل مساحة عمل. يستمر Noise Control في التقاط القياس عن بعد وحركة المرور منخفضة القيمة، لكنه يخفيها من مساحة العمل الحالية.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="يشرح Rockxy AI Assistant حركة المرور المحددة بجوار جدول الطلبات والشريط الجانبي الأصليين" width="820" />

حدد طلبًا واحدًا أو أكثر من الطلبات الملتقطة واسأل عما حدث أو فشل أو تغير أو ما يجب التحقق منه بعد ذلك. يبدأ Rockxy بتحليل يستند إلى الأدلة على هذا الـ Mac؛ ولا يعمل نموذج Ollama أو provider المُعد إلا بعد أن يعرض Review Data السياق الدقيق والمحدود والمنقح. يمكن للردود كشف طلب المصدر وإعداد مهام متابعة أصلية، لكنها لا تعدّل حركة المرور أو تنفذ الإجراءات تلقائيًا.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[اقرأ دليل AI Assistant](docs/features/ai-assistant.mdx).

### خادم MCP لعملاء الذكاء الاصطناعي الخارجيين

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

اسمح لـ Claude Desktop أو Cursor بفحص حركة المرور التي تم التقاطها عبر عشر أدوات للقراءة فقط في خادم MCP المحلي لـ Rockxy. اسأل "لماذا فعل هذا 500؟" بدلاً من لصق الرؤوس في الدردشة. التنفيذ مفتوح المصدر، ومصادق عليه بالرمز المميز، ويحافظ على تنقيح البيانات الحساسة مفعّلًا افتراضيًا.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

قم بترقية أي رأس طلب أو استجابة إلى عمود من الدرجة الأولى في جدول حركة المرور. أبقِ مصادر الطلب والاستجابة منفصلة، واحفظ الرؤوس التي تهمك، ثم تصفح request IDs وtrace IDs وحالة ذاكرة التخزين المؤقت أو البيانات الوصفية المخصصة دون فتح كل مفتش.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### ظروف الشبكة

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

يمكنك التبديل إلى شبكات 3G أو EDGE أو LTE أو WiFi أو تأخير مخصص. الكمبيوتر المحمول الخاص بك متصل بالألياف. المستخدمون لديك ليسوا كذلك - شاهد تجربة المستخدم عند 400 مللي ثانية RTT قبل أن يفعلوا ذلك.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### يؤلف - تحرير وإعادة التشغيل

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

أعد بناء أي طلب HTTP تم التقاطه - قم بتغيير الطريقة أو عنوان URL أو الرؤوس أو معلمات الاستعلام أو النص - وأعد الإرسال دون مغادرة Rockxy. لا حلقة نسخ ولصق إلى Postman أو Insomnia أو curl. قم بالتكرار على مطالبات LLM أو تشويش حدود المصادقة أو إعادة إنتاج حالة فاشلة لنقاط نهاية OpenAI وAnthropic وCohere في ثوانٍ.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### قارن

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

قم بتجميع معاملتين تم التقاطهما أو حمولتين ملصقتين جنبًا إلى جنب وحدد كل حقل تغير - الحالة والرؤوس ومفاتيح JSON أو وحدات بايت النص. احصل على انحدارات واجهة برمجة التطبيقات الصامتة، ومخرجات LLM غير الحتمية، وانحراف المطالبات (prompt drift) دون توصيل أي شيء إلى أداة فرق تابعة لجهة خارجية.

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="تعرض مساحات عمل Rockxy متعددة علامات التبويب طرق عرض تمت تصفيتها بشكل مستقل لنفس الالتقاط المباشر" width="820" />

احتفظ بعروض تحقيق مستقلة جنبًا إلى جنب لنفس الالتقاط المباشر — علامة تبويب لحركة staging، وواحدة للإنتاج، وواحدة لتدفق جهاز iOS. لكل علامة تبويب عوامل التصفية والفرز والتحديد ونطاق الشريط الجانبي وحالة المفتش الخاصة بها، مع مشاركة الوكيل والمعاملات الملتقطة.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### البرمجة النصية جافا سكريبت

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

ترتبط JS بالطلبات والاستجابات للحالات التي لا يمكن أن تغطيها القاعدة الثابتة - قم بتنقيح معلومات تحديد الهوية الشخصية (PII)، وتوقيع الرموز المميزة، وإعادة كتابة الحمولات. تظهر الأخطاء في السطر بدلاً من إتلاف حركة المرور.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## الفحص المدرك للبروتوكول

يوفر Rockxy فحصًا مدركًا للبروتوكول لحركة AI وWeb3 RPC وx402 ضمن سير عمل تصحيح HTTP المعتاد.

### فحص حركة الذكاء الاصطناعي

يكتشف Rockxy طلبات AI المعترف بها ضمن سير عمل الالتقاط العادي. افحص استدعاءات النماذج المحددة، وحالة البث، وحقول usage عند توفرها، والتحذيرات، وretrieval hints، وملخصات tool-call دون لصق حمولات حساسة في خدمة أخرى.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### فحص Web3/RPC

يحوّل Rockxy مكالمات الشبكة في عصر blockchain إلى أدلة تصحيح قابلة للقراءة. افحص حركة HTTP JSON-RPC بأسلوب EVM وSolana مع provider host وrequest ID وmethod وbatch summary وerror وchain وtransaction وpayload وdebug-intent، دون تحويل Rockxy إلى محفظة أو مستكشف كتل.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### تلميحات تدفق الدفع x402

يبرز Rockxy تلميحات payment-required والموجهة نحو إعادة المحاولة حتى تصبح تدفقات HTTP ذات بوابات الدفع مفهومة من طبقة الشبكة، بينما تبقى أدلة التصحيح محلية وقابلة للتنقيح.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## العمل المستقبلي

تصف الأقسام التالية الاتجاه العام، وليس السلوك الحالي.

### القواعد المدركة للبروتوكول

يمكن لـ Rockxy اليوم بالفعل تسمية وفحص حركة AI وWeb3. تظل مطابقة القواعد الأعمق حسب model أو tool call أو طريقة JSON-RPC أو chain أو transaction hash أو batch subcall عملاً مستقبليًا؛ ولا تزال أدوات تعديل حركة المرور الحالية تطابق URL وطريقة HTTP والرؤوس.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### حزم الأدلة المنقحة `قريبًا`

شارك الحقائق اللازمة لإعادة إنتاج الخلل دون تسريب الأسرار. قم بتعبئة حركة المرور المحددة بملخصات البروتوكول ومعاينات التنقيح والسياق المدعوم بالمصدر الذي يمكن لزميل الفريق تدقيقه.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### مشاركة الفريق والتعاون `قريبًا`

أرسل جلسة تم التقاطها إلى أحد أعضاء الفريق بنقرة واحدة. قم بإضافة تعليقات توضيحية للطلبات الفاشلة بشكل مضمن، ومعرفة من الذي ينظر إلى ماذا في الوقت الفعلي، وتصحيح أخطاء حركة مرور HTTPS بدون مشاركة الشاشة. تستهدف الإصدار المستقبلي.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> غلاف تطبيق macOS أصلي — بلا Electron. SwiftUI + AppKit + SwiftNIO، مع استخدام WebKit فقط لمعاينة جسم HTML.

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

تغطي المصفوفة الرئيسية وكلاء تصحيح أخطاء الويب للأغراض العامة. اختبار الأمان
الأجنحة والمتصفحات/الاعتراضات الموجهة نحو API مع تداخل كبير في سير العمل
يتم سردها بشكل منفصل بحيث لا يتم تقديم المنتجات المختلفة على أنها قابلة للتبديل.
محللو الحزم وعملاء API فقط هم خارج هذه المقارنة.

### وكلاء تصحيح أخطاء الويب المباشر

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **شكل المنتج** | وكيل تصحيح أخطاء macOS الأصلي | تطبيق macOS الأصلي؛ إصدارات Windows/Linux المستندة إلى Electron | وكيل تصحيح أخطاء سطح المكتب عبر الأنظمة الأساسية | مجموعة أدوات CLI/TUI عبر الأنظمة الأساسية ومجموعة أدوات وكيل واجهة المستخدم على الويب | وكيل سطح المكتب Electron عبر الأنظمة الأساسية وعميل HTTP | وكيل تصحيح أخطاء سطح المكتب عبر الأنظمة الأساسية |
| **نموذج المصدر والبناء** | مصدر المجتمع العام تحت AGPL-3.0-or-later؛ قابلة للبناء باستخدام Xcode. يحتوي DMG الرسمي أيضًا على مكونات المصب غير العامة | مصدر مغلق؛ لم يتم تحديد مصدر التطبيق العام في المواد الرسمية التي تمت مراجعتها | مصدر مغلق؛ لم يتم تحديد مصدر التطبيق العام في المواد الرسمية التي تمت مراجعتها | مصدر مرخص عام MIT؛ قابلة للبناء من المصدر | مصدر سطح المكتب العام AGPL؛ قابلة للبناء من المصدر؛ تحتوي الثنائيات المنشورة على خيارات ترخيص إضافية | مصدر مغلق؛ يتم توزيعها كرمز كائن ضمن Fiddler Everywhere EULA |
| **التقاط وإعداد** | وكيل النظام المحلي مع الإعداد الموجه لتطبيقات Mac وأوقات التشغيل وأجهزة iOS ومحاكي | الإعداد التلقائي لتطبيقات Mac وأوقات التشغيل والأجهزة المحمولة | الوكيل المحلي مع macOS وiOS وأدلة الإعداد عبر الأنظمة الأساسية | العادية، والعملية المحلية، وWireGuard، والعكس، والشفاف، وغيرها من أوضاع الالتقاط | اعتراض الوكيل المستهدف واليدوي للمتصفحات وأوقات التشغيل والحاويات والأجهزة المحمولة | أوضاع التقاط النظام والشبكة والمتصفح والمحطة والصريحة والجهاز البعيد |
| **تعديل واستهزاء** | نقاط التوقف، Map Local/Remote، قواعد الرأس، الحظر، وقواعد الكمون | نقاط التوقف، Map Local/Remote، قوائم الحظر، شروط الشبكة، وقواعد JavaScript | نقاط التوقف، إعادة الكتابة، Map Local/Remote، الحظر، والاختناق | Map Local/Remote، تعديل النص/الرأس، الحظر، وإعادة تشغيل الخادم | نقاط التوقف بالإضافة إلى إعادة الكتابة وإعادة التوجيه والمحاكاة وحقن الأخطاء المستندة إلى القواعد؛ بعض الأتمتة محدودة الخطة | القواعد ونقاط التوقف وعمليات إعادة التوجيه وتعديل الاستجابة والاستهزاء |
| **إعادة ومقارنة** | إنشاء/إعادة تشغيل بالإضافة إلى الطلب المحلي جنبًا إلى جنب والرأس والنص الأساسي | التأليف والتكرار والفرق | تكرار الطلبات وتحريرها | إعادة التشغيل من جانب العميل والخادم | عميل HTTP مدمج لإنشاء الطلبات وإرسالها | تم توثيق الملحن API وإعادة تشغيل حركة المرور ومقارنة حركة المرور كنسخة تجريبية |
| ** سير العمل WebSocket ** | فحص النص/الإطار الثنائي باستخدام استدلالات Protobuf | فحص WS/WSS؛ يمكن للبرامج النصية تعديل عنوان URL/رؤوس المصافحة، وليس الرسائل | تم توثيق دعم WebSocket في سجل الإصدار الرسمي | اعتراض WebSocket والبرمجة النصية؛ إعادة تشغيل WebSocket غير مدعومة | فحص WebSocket بالإضافة إلى القواعد الخاصة بـ WebSocket | التقاط وتفتيش WebSocket |
| ** البرمجة النصية وقابلية التوسعة ** | خطافات JavaScriptCore ذات وضع الحماية مع API محدودة ومهلة التنفيذ | JavaScript البرمجة النصية للطلب/الاستجابة | إعادة كتابة القواعد وواجهة الويب للتحكم؛ لم يتم توثيق أي ميزة برمجة عامة لـ JavaScript | إضافات Python وأتمتة سطر الأوامر | الأتمتة القائمة على القواعد بالإضافة إلى مكتبات المصادر العامة والوكيل | الأتمتة القائمة على القواعد؛ لم يتم توثيق أي ميزة برمجة عامة للطرف الأول |
| ** التوجيه المنبع ** | [الوكيل الأولي HTTP/HTTPS وتوجيه عنوان URL PAC](docs/features/upstream-proxy.mdx)؛ تقوم سياسة المجتمع بتعطيل مصادقة الوكيل وSOCKS5 وتضع قواعد تجاوز عند ثلاثة | التوجيه الخارجي HTTP/HTTPS/SOCKS وPAC مع قواعد التجاوز | وكلاء HTTP/HTTPS/SOCKS خارجيون مع قواعد المصادقة والتجاوز | وضع المنبع HTTP/HTTPS بالإضافة إلى أوضاع المستمع العكسي وSOCKS | إعدادات النظام وHTTP وHTTPS وSOCKS؛ قد يتم تطبيق حدود الخطة | التسلسل التلقائي لوكلاء النظام بالإضافة إلى التقاط الوكيل العكسي |
| **الذكاء الاصطناعي وMCP** | [مساعد الذكاء الاصطناعي داخل التطبيق](docs/features/ai-assistant.mdx) و[MCP المحلي المدمج](docs/features/mcp.mdx) مع 10 أدوات للقراءة فقط، ومصادقة الرمز المميز، والتنقيح بشكل افتراضي | MCP مدمج لعملاء الذكاء الاصطناعي الخارجيين، بما في ذلك قراءات حركة المرور وعناصر التحكم في التطبيق/القاعدة | غير موثقة | غير موثقة | يوجد جسر MCP المحلي المجمع في المصدر الرسمي الحالي؛ لا يوجد مساعد داخل التطبيق موثق | MCP مدمج بالإضافة إلى مساعد تصحيح الأخطاء من المستوى الاحترافي الذي تتطلب وثائقه الحالية لصق تفاصيل حركة المرور الملتقطة في الدردشة |

### أدوات الاعتراض المجاورة

تتداخل هذه المنتجات بشكل مفيد مع Rockxy ولكنها تؤدي إلى اختبارات الأمان،
قواعد المتصفح، أو سير عمل عميل API بدلاً من نفس الأغراض العامة
التركيز الأصلي على وكيل التصحيح.

| **المنتج** | ** لماذا هو مجاور ** | **نموذج المصدر والبناء** | **التداخل ذو الصلة** | **الذكاء الاصطناعي وMCP** |
|---|---|---|---|---|
| **Burp Suite** | مجموعة اختبارات أمان الويب مع وكيل اعتراض | تطبيق مغلق المصدر؛ تنص EULA على أن المستخدمين ليس لديهم الحق في الوصول إلى مصدر التطبيق. يمكن للملحقات استخدام تراخيص منفصلة | اعتراض الوكيل والمطابقة/الاستبدال، المكرر، WebSockets، الوكيل الأولي/SOCKS، ونظام بيئي كبير الامتداد | Burp AI متاح في Repeater؛ يحتفظ PortSwigger أيضًا بامتداد خادم MCP العام لعملاء الذكاء الاصطناعي الخارجيين |
| **ZAP** | الماسح الضوئي الأمني ​​واعتراض الوكيل | مصدر Apache-2.0 العام؛ قابلة للبناء من المصدر | الاعتراض/التحرير، وإعادة الإرسال اليدوي، ونقاط التوقف والبرامج النصية WebSocket، والبرمجة النصية متعددة اللغات، والوظائف الإضافية، والأتمتة | تكامل MCP الرسمي وإضافات دعم LLM الاختيارية |
| **Requestly HTTP Interceptor** | أداة اعتراض/محاكاة لامتداد المتصفح وسطح المكتب عبر الأنظمة الأساسية | مصدر اعتراض سطح المكتب العام AGPL؛ يعتبر عميل Requestly API المنفصل ملكية وفقًا لإشعار مستودع المجتمع العام الخاص به | التقاط على مستوى النظام/المتصفح، وإعادة التوجيه، وMap Local/Remote، وتعديل الرأس/الجسم، وتحويلات JavaScript، والمحاكاة، ومحاكاة التأخير/الخطأ | يدير خادم MCP الرسمي المنفصل القواعد والمجموعات؛ لا يوجد مساعد موثق لتحليل حركة المرور داخل التطبيق |

يمكن أن يختلف توفر الميزات حسب الإصدار أو الخطة أو النظام الأساسي أو الوظيفة الإضافية.
"غير موثقة" تعني أنه لم يتم العثور على القدرة في الطرف الأول الرسمي
المصادر التي تمت مراجعتها على 2026-08-22؛ وليس دليلاً على غياب القدرة.
تم فحص بيانات المنتج والميزات المذكورة أعلاه مقابل وثائق البائع،
مستودعات المصدر التي يحتفظ بها البائع، أو شروط ترخيص البائع في ذلك التاريخ و
قد يتغير. أسماء المنتجات والعلامات التجارية مملوكة لأصحابها؛
Rockxy ليس تابعًا لهم أو معتمدًا منهم. التصحيحات هي موضع ترحيب
من خلال أداة تعقب المشكلات Rockxy.

على خريطة الطريق: قواعد أعمق للبروتوكول، وحزم أدلة منقحة أكثر أمانًا، وإعادة تشغيل وسير عمل أقوى، وإرشادات إعداد المطور الأوسع، والبحث المستمر عن HTTP/2 وHTTP/3.

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
- [AI Assistant](docs/features/ai-assistant.mdx) — افحص حركة المرور المحددة محليًا أو باستخدام نموذج مُعد بعد Review Data
- [عوامل التصفية والبحث](docs/core-features/filters-and-search.mdx) — نطاقات الشريط الجانبي وFocus Sets وNoise Control وعوامل تصفية toolbar والبحث
- [فحص AI وWeb3](docs/features/ai-web3-inspection.mdx) — افحص حركة model API وJSON-RPC وx402 المعترف بها
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

تتم صيانة Rockxy بشكل مستقل. تساعد الرعاية في تمويل التطوير المستمر، وبنية الإصدارات التحتية، والتوثيق، وأعمال الأمان.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

تستضيف [Open Source Collective](https://docs.oscollective.org/) مشروع Rockxy ماليًا. تُسجَّل المساهمات ونفقات المشروع في [صفحة Rockxy العامة على Open Collective](https://opencollective.com/rockxy)، مما يمنح الداعمين رؤية شفافة لكيفية استلام الأموال واستخدامها.

| الفئة | المساهمة | ما الذي تدعمه |
|------|----------|----------------|
| **Backer** | ابتداءً من 5 دولارات شهريًا | صيانة المشروع مفتوح المصدر، والتوثيق، والاختبارات، والإصدارات |
| **Builder** | ابتداءً من 25 دولارًا شهريًا | اختبارات الانحدار، وتحسينات الأداء، ومسارات عمل تصحيح الأخطاء اليومية |
| **Sponsor** | 100 دولار شهريًا | الصيانة طويلة الأمد لأداة تركز على الخصوصية وتظل متاحة مجانًا للمطورين |
| **Sustaining Sponsor** | 500 دولار شهريًا | صيانة وتطوير مركزان، بما في ذلك أتمتة الإصدارات ودعم البروتوكولات |

**استفسارات الشراكة** — شركات أدوات المطورين وشركات الأمان وفرق المؤسسات التي تبحث عن عمليات تكامل مخصصة أو حلول ذات علامة بيضاء: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## الدعم

- [Open Collective](https://opencollective.com/rockxy/donate) - المساهمة في Rockxy من خلال ميزانية المشروع الشفافة
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) - دعم تطوير Rockxy
- [قضايا جيثب](https://github.com/RockxyApp/Rockxy/issues) - تقارير الأخطاء وطلبات الميزات
- [مناقشات جيثب](https://github.com/RockxyApp/Rockxy/discussions) - الأسئلة والدردشة المجتمعية
- **البريد الإلكتروني** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **القضايا الأمنية** - انظر [الأمن.md](SECURITY.md) للإفصاح المسؤول

## الترخيص

[رخصة جنو أفيرو العامة v3.0](LICENSE) — حقوق الطبع والنشر 2024–2026 مملوكة لشركة Rockxy Contributors.

## تاريخ النجوم

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>صنع بواسطة <a href="https://github.com/LocNguyenHuu">Stephen</a>. تم تصميمه باستخدام Swift وSwiftNIO وSwiftUI وAppKit.</sub>
</p>

</div>
