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
  <strong>ღია კოდის, აუდიტორული გამართვის პროქსი macOS-ისთვის.</strong>
</p>

<p align="center">
  გადახედეთ, შეამოწმეთ და შეცვალეთ HTTP/HTTPS/WebSocket/GraphQL ტრაფიკი მშობლიური Swift აპლიკაციით, რომელსაც შეგიძლიათ შეამოწმოთ, შექმნათ და ენდოთ.<br>
  შექმნილია API, მობილური, MCP-ის დახმარებით, AI და ბლოკჩეინის ეპოქის გამართვის სამუშაო ნაკადებისთვის Rockxy-ის განვითარებასთან ერთად.<br>
  local-first, AGPL-3.0 ალტერნატივა <a href="#rockxy-ალტერნატივების-წინააღმდეგ">Proxyman-ისა და Charles Proxy-ის</a>.
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

## მიმდინარე ფილიალის მაჩვენებლები

- AI Assistant ახლა იკვლევს ერთ ან რამდენიმე არჩეულ request-ს ჩაშენებული ლოკალური ანალიზით ან სურვილისამებრ კონფიგურირებული Ollama/provider model-ით, მკაფიო Review Data დადასტურებით, შეზღუდული redaction-ით, streaming პასუხებით, evidence reveal-ითა და მომხმარებლის ინიცირებული handoff-ებით.
- native sidebar ახლა მოიცავს მრავალჯერად Focus Sets-ს app/domain/path scope-ებისთვის, ასევე workspace-დონის Noise Control-ს, რომელიც მალავს შესაბამის domain-ებს ან path-ებს capture-ის შეჩერების გარეშე.
- მთავარი workspace ახლა იყენებს native ვერტიკალურ და ჰორიზონტალურ split view-ს Context Dock-ისა და ქვედა inspector-ისთვის, ინარჩუნებს სრული სიმაღლის გამყოფებს, კოორდინირებულ toolbar/footer separator-ებსა და ლეიაუტის ავტომატურ ზომის ცვლილებას.
- Upstream Proxy ახლა მოიცავს უფასო/ძირითადი ავტომატური პროქსის კონფიგურაციას PAC URL-ის მარშრუტით `DIRECT`, HTTP და HTTPS მარშრუტები არსებული SOCKS5 და ავთენტიფიკაციის პოლიტიკის საზღვრების შენარჩუნებით.
- ექსპორტის სამუშაო ნაკადები ახლა მოიცავს OpenAPI YAML/HTML და შერჩეული ტრაფიკის Gist გამოქვეყნებას რედაქციით გაცნობიერებული დატვირთვის შენობით.
- ინსპექტორის ხელსაწყოები ახლა მოიცავს JSONPath/გასაღების/მნიშვნელობის ფილტრაციას და სწრაფ გადახედვას შერჩეული დატვირთვის ტექსტისთვის, როგორიცაა JWT.
- AI და Web3 ტრაფიკის ინსპექტირება ახლა ამატებს პროტოკოლის ლეიბლებს, inspector ჩანართებსა და გამართვის შეჯამებებს ამოცნობილი მოდელის ზარებისთვის, JSON-RPC ტრაფიკისა და x402-სტილის გადახდის მინიშნებებისთვის.
- Node.js Developer Setup ახლა ასახავს არჩეულ კლიენტს ვალიდაციის დროს და აქვს ლოკალური ჰოსტის უფრო სრულყოფილი ნიმუშის სახელმძღვანელო.
- Developer Setup Hub ახლა მოიცავს გაშვების დროებს, ბრაუზერებს, კლიენტებს, მოწყობილობებს, ჩარჩოებსა და გარემოს სამიზნე სპეციფიკური ფრაგმენტებით, ვალიდაციის დამკვირვებლებით და პატიოსანი სახელმძღვანელო კონტენტით.
- WebSocket binary-frame inspection ახლა მოიცავს შეზღუდულ, მოთხოვნით Protobuf wire-format heuristic-ს capture hot path-ში decoder work-ის დამატების გარეშე.
- საჯარო roadmap ახლა ფოკუსირებულია უფრო ღრმა protocol-aware rules-ზე, replay-ზე, comparison-ზე და უსაფრთხო redacted evidence sharing-ზე.

## მახასიათებლები

ინსტრუმენტები, რომლებსაც წვდებით, როდესაც ბრაუზერის DevTools არ არის საკმარისი. ძირითადი ტრაფიკის გამართვა Mac-ისთვის და iOS-ისთვის - მუშაობს macOS-ზე, საჯარო გამოშვებებით და ადგილობრივი პირველი სამუშაო ნაკადით.

### Traffic Capture

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

შეამოწმეთ HTTP, HTTPS, WebSocket და GraphQL ტრაფიკი ნებისმიერი Mac აპიდან, CLI ან iOS მოწყობილობიდან. ბრაუზერის DevTools მთავრდება ბრაუზერთან — Rockxy ხედავს თქვენს დასტას.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### გაფართოებული ფილტრი და ძიება

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

შეზღუდეთ ათასობით დაფიქსირებული მოთხოვნა წამებში. შეუთავსეთ მეთოდი, ჰოსტი, სტატუსი, სათაური, ძირითადი და პროცესის ფილტრები — ან განახორციელეთ სრული ტექსტის ძიება მთელი სესიის განმავლობაში.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets და Noise Control

განმეორებადი კვლევები sidebar-ის მრავალჯერად scope-ებად აქციეთ. Focus Sets აერთიანებს app/domain/path include-ებს domain/path exclude-ებთან, ინახება გაშვებებს შორის და ხელმისაწვდომია ყველა workspace-ში. Noise Control აგრძელებს telemetry-სა და დაბალი ღირებულების traffic-ის capture-ს, მაგრამ მიმდინარე workspace-ში მალავს.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant ხსნის არჩეულ traffic-ს native request table-ისა და sidebar-ის გვერდით" width="820" />

აირჩიეთ ერთი ან რამდენიმე capture request და ჰკითხეთ რა მოხდა, რა ჩავარდა, რა შეიცვალა ან შემდეგ რა უნდა შემოწმდეს. Rockxy ჯერ ამ Mac-ზე evidence-based analysis-ს ასრულებს; კონფიგურირებული Ollama/provider model მხოლოდ მას შემდეგ ეშვება, რაც Review Data ზუსტ, შეზღუდულ და redacted context-ს აჩვენებს. პასუხებს შეუძლია source request-ის reveal და native follow-up workflow-ის მომზადება, მაგრამ traffic-ს არ ცვლის და action-ებს ავტომატურად არ ასრულებს.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[წაიკითხეთ AI Assistant-ის სახელმძღვანელო](docs/features/ai-assistant.mdx).

### MCP სერვერი გარე AI კლიენტებისთვის

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

ნება მიეცით Claude Desktop-ს ან Cursor-ს შეამოწმოს თქვენი გადაღებული ტრაფიკი Rockxy-ის ლოკალური MCP სერვერის ათი მხოლოდ-წაკითხვადი ხელსაწყოს მეშვეობით. ჩატში სათაურების ჩასმის ნაცვლად ჰკითხეთ "რატომ დააბრუნა ამან 500?". იმპლემენტაცია ღია კოდისაა, დამოწმებულია token-ით და ინახავს მგრძნობიარე მონაცემების redaction-ს ნაგულისხმევად ჩართულს.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### დეველოპერის დაყენების ცენტრი

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

დააკოპირეთ ჩასვით პროქსის ფრაგმენტები Python, Node.js, Go, Rust, cURL, Docker და ბრაუზერებისთვის, შემდეგ დააწკაპუნეთ Run Test, რათა დაადასტუროთ ტრაფიკი რეალურად მიედინება.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### სერთიფიკატის მენეჯმენტი HTTPS გამართვისთვის

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

P-256 ECDSA root CA, გენერირებული პირველი გაშვებისას, დალუქული თქვენს Keychain-ში. HTTPS-ის გაშიფვრა პირველივე ცდაზე; ჩამაგრებული მასპინძლები ავტომატურად გადიან.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL პროქსი და HTTPS გაშიფვრა

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

აირჩიეთ, რომელი მასპინძლები მიიღებენ TLS გაშიფვრას. გაშიფრული ტრაფიკი აჩვენებს რეალურ სათაურებს და JSON-ს; ყველაფერი დანარჩენი გადის დაშიფრული გზით. Wildcard-ის წესები საშუალებას გაძლევთ დაფაროთ დომენის მიხედვით ერთი დაწკაპუნებით.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### პროქსის გვერდის ავლით

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

გამოტოვეთ კონკრეტული ჰოსტები, რათა სერთიფიცირებული აპები, შიდა სერვისები ან ხმაურიანი ტელემეტრია არასოდეს შევიდეს გადაღებაში. Wildcards ინახავს სიას მოკლედ და თქვენი მოთხოვნის ჟურნალი ორიენტირებულია იმაზე, რაც რეალურად გაინტერესებთ.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### ბლოკების სია

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

ნებისმიერი მასპინძლის წარუმატებლობა. გააუქმეთ სარეკლამო ქსელები, მესამე მხარის ტრეკერები ან მყიფე დამოკიდებულება, რათა ნახოთ, როგორ მცირდება თქვენი აპი, როცა ის გაქრება — კოდის ხაზის შეცვლის გარეშე.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### ლოკალური რუკა

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

მიირთვით შენახული ფაილი ან დირექტორიის ხე ცოცხალი პასუხის ნაცვლად. შეცვალეთ JSON დატვირთვა, ხელახლა დაუკრათ სნეპშოტი ან ჩაამაგრეთ მესამე მხარის გაფუჭებული API ლოკალურ ასლზე, ​​სანამ გამართავთ.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### რუკის დისტანციური

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

გადაწერეთ გადაღებული მოთხოვნის დანიშნულება აპის კოდზე ან /etc/host-ების შეხების გარეშე. მიუთითეთ წარმოების ტრაფიკი დადგმის დროს, თქვენი დეველოპერის სერვერი ან კოლეგის აპარატი რეპროდუცირებადი ხარვეზების გამეორებისთვის.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### შესვენების წერტილები და წესები

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

შეაჩერეთ მოთხოვნა ან პასუხი, რედაქტირების მეთოდი, სათაურები, ტექსტი ან სტატუსი, შემდეგ გააგრძელეთ. "რა მოხდება, თუ API დააბრუნებს 401?" უკანა მხარეს შეხების გარეშე.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### ჰედერების შეცვლა

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

დაამატეთ, წაშალეთ ან შეცვალეთ სათაურები ნებისმიერ ჰოსტზე გადანერგვის გარეშე. შეამოწმეთ CORS, ავტორიზაცია ან ქეში ცვლილებები წამებში ჩაშენებული წინასწარ დაყენებით.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### მორგებული მოთხოვნისა და პასუხის სათაურები

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

აამაღლეთ ნებისმიერი request ან response სათაური ტრაფიკის ცხრილში პირველი კლასის სვეტამდე. request-ისა და response-ის წყაროები ცალკე შეინახეთ, შეინახეთ თქვენთვის მნიშვნელოვანი სათაურები, შემდეგ დაათვალიერეთ request ID-ები, trace ID-ები, cache-ის მდგომარეობა ან საკუთარი მეტამონაცემები ყოველი inspector-ის გახსნის გარეშე.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### ქსელის პირობები

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

დროებით 3G, EDGE, LTE, WiFi ან მორგებული დაყოვნება. თქვენი ლეპტოპი არის ბოჭკოზე; თქვენი მომხმარებლები არ არიან — იხილეთ UX 400 ms RTT-ზე, სანამ ამას გააკეთებენ.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### შედგენა - რედაქტირება და გამეორება

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

აღადგინეთ ნებისმიერი დაჭერილი HTTP მოთხოვნა - შეცვალეთ მეთოდი, URL, სათაურები, მოთხოვნის პარამეტრები ან ტექსტი - და ხელახლა გაგზავნეთ Rockxy-ის დატოვების გარეშე. Postman-ის, Insomnia-ს ან curl-ის კოპირება-ჩასმის ციკლი აღარ არის. გაიმეორეთ LLM მოთხოვნებზე, გააფაზზეთ ავტორიზაციის საზღვრები ან შეცვალეთ OpenAI, Anthropic და Cohere ბოლო წერტილების წარუმატებელი შემთხვევა წამებში.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### შეადარე

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

დააწყვეთ ორი გადაღებული ტრანზაქცია ან ჩასმული payload გვერდიგვერდ და დააფიქსირეთ ყველა ველი, რომელიც შეიცვალა - სტატუსი, სათაურები, JSON კლავიშები ან ძირითადი ბაიტები. დაიჭირეთ ჩუმი API რეგრესია, არადეტერმინისტული LLM გამომავალი და prompt drift მესამე მხარის diff ინსტრუმენტში რაიმეს გაგზავნის გარეშე.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### მორგებული Previewer ჩანართები

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

გამოაცხადეთ მოთხოვნისა და რეაგირების ორგანოები ისე, როგორც გსურთ. ჩაამაგრეთ დამატებითი ჩანართები ინსპექტორს JSON, GraphQL, JWT, გამოსახულების ან თქვენი საკუთარი ფორმატისთვის — ხელახლა გამოყენებადი ყველა გადაღებულ მოთხოვნაზე.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### სესიები და ექსპორტი

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

სესიების შენახვა, HAR-ის იმპორტი/ექსპორტი ხელსაწყოების გადაცემისთვის, დააკოპირეთ ნებისმიერი მოთხოვნა cURL ან JSON. გაზიარებამდე დაარედაქტირეთ ავტორიზაციის სათაურები, ქუქი-ფაილები და მომწოდებლის ნიშნები - გადასცეთ თანაგუნდელს სამუშაო შეცდომების რეპროექტი საიდუმლოების გაჟონვის გარეშე.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### მრავალ ჩანართის სამუშაო სივრცეები

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy-ის მრავალჩანართიანი სამუშაო სივრცეები ერთი live capture-ის დამოუკიდებლად გაფილტრული ხედებით" width="820" />

ერთი live capture-ის დამოუკიდებელი კვლევის ხედები გვერდიგვერდ შეინახეთ — ერთი ჩანართი staging ტრაფიკისთვის, ერთი production-ისთვის და ერთი iOS მოწყობილობის ნაკადისთვის. თითოეულ ჩანართს აქვს საკუთარი ფილტრი, დალაგება, არჩევანი, sidebar scope და inspector state, ხოლო proxy და capture transaction-ები საერთოა.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript სკრიპტირება

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS აკავშირებს მოთხოვნებსა და პასუხებს იმ შემთხვევებზე, რომლებსაც სტატიკური წესი არ შეუძლია დაფაროს - PII-ის რედაქტირება, ნიშნების ხელმოწერა, დატვირთვის გადაწერა. შეცდომები ჩნდება ხაზში, ტრაფიკის გაფუჭების ნაცვლად.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Protocol-Aware ინსპექტირება

Rockxy უზრუნველყოფს protocol-aware AI, Web3 RPC და x402 inspection-ს ჩვეულებრივ HTTP debugging workflow-ში.

### AI Traffic Inspection

Rockxy ამოიცნობს ამოცნობილ AI მოთხოვნებს ჩვეულებრივი capture workflow-ის ფარგლებში. შეამოწმეთ არჩეული მოდელის ზარები, streaming მდგომარეობა, usage ველები არსებობის შემთხვევაში, გაფრთხილებები, retrieval hints და tool-call შეჯამებები მგრძნობიარე payload-ის სხვა სერვისში ჩასმის გარეშე.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC ინსპექტირება

Rockxy ბლოკჩეინის ეპოქის ქსელის ზარებს წაკითხვად გამართვის მტკიცებულებად აქცევს. შეამოწმეთ EVM და Solana-სტილის HTTP JSON-RPC ტრაფიკი provider host, request ID, method, batch summary, error, chain, transaction, payload და debug-intent-ით, Rockxy-ის საფულედ ან ბლოკის მკვლევარად ქცევის გარეშე.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 გადახდის ნაკადის მინიშნებები

Rockxy გამოკვეთს payment-required და retry-ზე ორიენტირებულ მინიშნებებს, რათა payment-gated HTTP ნაკადები ქსელის ფენიდან გასაგები იყოს, ხოლო გამართვის მტკიცებულება ლოკალური და redaction-aware რჩება.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## მომავალი სამუშაო

შემდეგი სექციები აღწერს საჯარო მიმართულებას და არა მიმდინარე behavior-ს.

### Protocol-Aware წესები

Rockxy დღეს უკვე შეუძლია AI და Web3 ტრაფიკის ლეიბლირება და ინსპექტირება. წესების უფრო ღრმა შესაბამისობა model-ის, tool call-ის, JSON-RPC method-ის, chain-ის, transaction hash-ის ან batch subcall-ის მიხედვით რჩება მომავალ სამუშაოდ; ტრაფიკის შეცვლის ამჟამინდელი ხელსაწყოები კვლავ ემთხვევა URL-ს, HTTP method-სა და სათაურებს.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### რედაქტირებული მტკიცებულებების პაკეტები `მალე`

გააზიარეთ ფაქტები, რომლებიც საჭიროა შეცდომების გასამრავლებლად საიდუმლოების გაჟონვის გარეშე. შეფუთეთ არჩეული ტრაფიკი პროტოკოლის შეჯამებებით, რედაქციის წინასწარი გადახედვით და წყაროზე მხარდაჭერილი კონტექსტით, რომელსაც თანაგუნდელს შეუძლია შეამოწმოს.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### გუნდის გაზიარება და თანამშრომლობა `მალე`

გაუგზავნეთ გადაღებული სესია თანაგუნდელს ერთი დაწკაპუნებით. ჩაწერეთ წარუმატებელი მოთხოვნები ხაზში, ნახეთ ვინ რას უყურებს რეალურ დროში და დააწყვილეთ HTTPS ტრაფიკი ეკრანის გაზიარების გარეშე. გამიზნულია მომავალი გამოშვებისთვის.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> native macOS აპლიკაციის გარსი — Electron-ის გარეშე. SwiftUI + AppKit + SwiftNIO, WebKit გამოიყენება მხოლოდ HTML body-ის გადახედვისთვის.

## სწრაფი დაწყება

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

შექმენით და გაუშვით Xcode-ში. მისასალმებელი ფანჯარა დაგეხმარებათ root CA-ს დაყენების, დამხმარე ინსტალაციისა და პროქსის გააქტიურების გზით.

**მოთხოვნები:** macOS 14.0+, Xcode 16+, Swift 5.9

თუ გსურთ დააკავშიროთ Rockxy ადგილობრივ MCP კლიენტთან ინსტალაციის შემდეგ, იხილეთ [MCP ინტეგრაციის სახელმძღვანელო](docs/features/mcp.mdx).

## Rockxy ალტერნატივების წინააღმდეგ

ძირითადი მატრიცა მოიცავს ზოგადი დანიშნულების ვებ-გამართვის პროქსიებს. უსაფრთხოების ტესტირება
კომპლექტები და ბრაუზერი/API-ზე ორიენტირებული ჩამჭრელები მნიშვნელოვანი სამუშაო ნაკადის გადახურვით
ჩამოთვლილია ცალკე, ამიტომ პროდუქტებისგან განსხვავებით არ არის წარმოდგენილი, როგორც ურთიერთშემცვლელი.
პაკეტის ანალიზატორები და მხოლოდ API კლიენტები ამ შედარების მიღმაა.

### პირდაპირი ვებ-გამართვის მარიონეტები

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **პროდუქტის ფორმა** | მშობლიური macOS გამართვის პროქსი | მშობლიური macOS აპლიკაცია; Electron-ზე დაფუძნებული Windows/Linux გამოცემები | Cross-platform desktop debugging proxy | Cross-platform CLI/TUI და web UI proxy toolkit | Cross-platform Electron დესკტოპის პროქსი და HTTP კლიენტი | Cross-platform desktop debugging proxy |
| **წყარო და აშენების მოდელი** | საზოგადოებრივი საზოგადოების წყარო AGPL-3.0-or-later-ში; ასაგებად Xcode. ოფიციალური DMG ასევე შეიცავს არასაჯარო ქვედა დინების კომპონენტებს | დახურული წყარო; განხილულ ოფიციალურ მასალებში საჯარო განაცხადის წყარო არ არის გამოვლენილი | დახურული წყარო; განხილულ ოფიციალურ მასალებში საჯარო განაცხადის წყარო არ არის გამოვლენილი | საჯარო MIT ლიცენზირებული წყარო; ასაგებად წყაროდან | საჯარო AGPL დესკტოპის წყარო; აშენებადი წყაროდან; გამოქვეყნებულ ბინარებს აქვთ დამატებითი ლიცენზირების ვარიანტები | დახურული წყარო; განაწილებულია როგორც ობიექტის კოდი Fiddler Everywhere EULA |
| ** გადაღება და დაყენება ** | ლოკალური სისტემის პროქსი მართებული დაყენებით Mac აპებისთვის, გაშვების დროით, iOS მოწყობილობებისთვის და სიმულატორისთვის | ავტომატური დაყენება Mac აპებისთვის, მუშაობის დროისა და მობილური მოწყობილობებისთვის | ლოკალური პროქსი macOS-ის, iOS-ის და პლატფორმის ჯვარედინი დაყენების სახელმძღვანელოებით | რეგულარული, ლოკალური პროცესის, WireGuard, საპირისპირო, გამჭვირვალე და სხვა გადაღების რეჟიმები | მიზნობრივი და ხელით მარიონეტული ჩარევა ბრაუზერებისთვის, გაშვების დროის, კონტეინერებისა და მობილური მოწყობილობებისთვის | სისტემის, ქსელის, ბრაუზერის, ტერმინალის, აშკარა და დისტანციური მოწყობილობის გადაღების რეჟიმები |
| ** შეცვლა და დაცინვა ** | წყვეტის წერტილები, Map Local/Remote, სათაურის წესები, დაბლოკვის და შეყოვნების წესები | წყვეტის წერტილები, Map Local/Remote, ბლოკების სიები, ქსელის პირობები და JavaScript წესები | წყვეტის წერტილები, ხელახლა ჩაწერა, Map Local/Remote, დაბლოკვა და ჩახშობა | Map Local/Remote, სხეულის/თაურის მოდიფიკაცია, დაბლოკვა და სერვერის გამეორება | წყვეტის წერტილები პლუს წესებზე დაფუძნებული გადაწერა, გადამისამართება, დაცინვა და შეცდომის ინექცია; ზოგიერთი ავტომატიზაცია გეგმით შეზღუდულია | წესები, წყვეტების წერტილები, გადამისამართებები, პასუხის მოდიფიკაცია და დაცინვა |
| **გამეორება და შედარება ** | შედგენა/გამეორება პლუს ლოკალური გვერდიგვერდ მოთხოვნა, სათაური და სხეულის შედარება | შედგენა, გამეორება და განსხვავება | გაიმეორეთ და შეცვალეთ მოთხოვნები | კლიენტის და სერვერის მხრიდან გამეორება | ჩაშენებული HTTP კლიენტი მოთხოვნების შედგენისა და გაგზავნისთვის | API კომპოზიტორი, ტრაფიკის განმეორება და ტრაფიკის შედარება დოკუმენტირებულია როგორც ბეტა |
| **WebSocket სამუშაო ნაკადები** | ტექსტის/ორობითი ჩარჩოს შემოწმება შეზღუდული Protobuf ევრისტიკით | WS/WSS შემოწმება; სკრიპტებს შეუძლიათ შეცვალონ ხელის ჩამორთმევის URL/სათაურები და არა შეტყობინებები | WebSocket მხარდაჭერა დოკუმენტირებულია ოფიციალური ვერსიის ისტორიაში | WebSocket ჩაჭრა და სკრიპტირება; WebSocket გამეორება არ არის მხარდაჭერილი | WebSocket ინსპექტირება პლუს WebSocket სპეციფიკური წესები | WebSocket დაჭერა და შემოწმება |
| ** სკრიპტირება და გაფართოება ** | Sandboxed JavaScriptCore კაკვები შეზღუდული API და შესრულების ვადა | JavaScript მოთხოვნის/პასუხის სკრიპტირება | წესების გადაწერა და საკონტროლო ვებ ინტერფეისი; არ არის დოკუმენტირებული JavaScript სკრიპტირების ზოგადი ფუნქცია | Python დამატებები და ბრძანების ხაზის ავტომატიზაცია | წესებზე დაფუძნებული ავტომატიზაცია პლუს საჯარო წყარო და პროქსი ბიბლიოთეკები | წესებზე დაფუძნებული ავტომატიზაცია; არ არის დოკუმენტირებული პირველი მხარის ზოგადი სკრიპტირების ფუნქცია |
| ** ზევით მარშრუტიზაცია ** | [HTTP/HTTPS ზემორე პროქსი და PAC URL-ის მარშრუტიზაცია](docs/features/upstream-proxy.mdx); საზოგადოების პოლიტიკა თიშავს პროქსის ავთენტიფიკაციას და SOCKS5 და იკავებს გვერდის ავლით წესებს სამზე | გარე HTTP/HTTPS/SOCKS და PAC მარშრუტიზაცია შემოვლითი წესებით | გარე HTTP/HTTPS/SOCKS პროქსი ავთენტიფიკაციისა და შემოვლითი წესებით | HTTP/HTTPS ზედა დინების რეჟიმი პლუს უკუ და SOCKS მსმენელის რეჟიმები | სისტემის, HTTP, HTTPS და SOCKS ზედა ნაკადის პარამეტრები; შესაძლოა მოქმედებდეს გეგმის ლიმიტები | ავტომატური მიჯაჭვულობა სისტემის მარიონეტებთან პლუს საპირისპირო პროქსის დაჭერა |
| **AI და MCP** | [აპლიკაციის AI ასისტენტი](docs/features/ai-assistant.mdx) და [ჩაშენებული ადგილობრივი MCP](docs/features/mcp.mdx) 10 მხოლოდ წასაკითხი ხელსაწყოთი, ჟეტონების ავთენტიფიკაცია და რედაქცია ნაგულისხმევად ჩართული | ჩაშენებული MCP გარე AI კლიენტებისთვის, ტრეფიკის წაკითხვისა და აპლიკაციის/წესების კონტროლის ჩათვლით | არ არის დოკუმენტირებული | არ არის დოკუმენტირებული | შეფუთული ადგილობრივი MCP ხიდი წარმოდგენილია მიმდინარე ოფიციალურ წყაროში; არ არის დოკუმენტირებული აპსშიდა ასისტენტი | ჩაშენებული MCP პლუს Pro-tier გამართვის ასისტენტი, რომლის ამჟამინდელი დოკუმენტაცია მოითხოვს გადაღებული ტრაფიკის დეტალების ჩატმას |

### მიმდებარე ჩარევის ხელსაწყოები

ეს პროდუქტები მნიშვნელოვნად ემთხვევა Rockxy-ს, მაგრამ ლიდერობს უსაფრთხოების ტესტირებასთან,
ბრაუზერის წესები, ან API-კლიენტის სამუშაო ნაკადები და არა იგივე ზოგადი დანიშნულება
მშობლიური გამართვა-პროქსი ფოკუსი.

| **პროდუქტი** | ** რატომ არის მიმდებარე ** | **წყარო და აშენების მოდელი** | **შესაბამისი გადახურვა** | **AI და MCP** |
|---|---|---|---|---|
| **Burp Suite** | ვებ-უსაფრთხოების ტესტირების კომპლექტი დამჭერი პროქსით | დახურული კოდის აპლიკაცია; მისი EULA აცხადებს, რომ მომხმარებლებს არ აქვთ უფლება აპლიკაციის წყაროზე. გაფართოებებს შეუძლიათ გამოიყენონ ცალკე ლიცენზიები | პროქსის ჩარევა და შესატყვისი/ჩანაცვლება, Repeater, WebSockets, upstream/SOCKS proxying და დიდი გაფართოების ეკოსისტემა | Burp AI ხელმისაწვდომია Repeater-ში; PortSwigger ასევე ინარჩუნებს საჯარო MCP სერვერის გაფართოებას გარე AI კლიენტებისთვის |
| **ZAP** | უსაფრთხოების სკანერი და დამჭერი პროქსი | საჯარო Apache-2.0 წყარო; ასაგებად წყაროდან | ჩაჭრა/რედაქტირება, ხელით ხელახლა გაგზავნა, WebSocket წყვეტის წერტილები და სკრიპტები, მრავალენოვანი სკრიპტირება, დანამატები და ავტომატიზაცია | ოფიციალური MCP ინტეგრაცია და სურვილისამებრ LLM მხარდაჭერის დანამატები |
| **Requestly HTTP Interceptor** | ბრაუზერის გაფართოება და ჯვარედინი პლატფორმა დესკტოპის ჩამჭრელი/იმიტირებული ინსტრუმენტი | საჯარო AGPL დესკტოპ-გამჭრელი წყარო; ცალკე მოთხოვნა API კლიენტი არის საკუთრებაში არსებული მისი საჯარო საზოგადოების საცავის შეტყობინების მიხედვით | სისტემის მასშტაბით/ბრაუზერის გადაღება, გადამისამართება, Map Local/Remote, ჰედერის/სხეულის მოდიფიკაცია, JavaScript ტრანსფორმაციები, დაცინვა და დაყოვნება/შეცდომის სიმულაცია | ცალკე ოფიციალური MCP სერვერი მართავს წესებსა და ჯგუფებს; არ არის დოკუმენტირებული აპსშიდა ტრაფიკის ანალიზის ასისტენტი |

ფუნქციების ხელმისაწვდომობა შეიძლება განსხვავდებოდეს გამოცემის, გეგმის, პლატფორმის ან დანამატის მიხედვით.
"არ არის დოკუმენტირებული" ნიშნავს, რომ შესაძლებლობა არ იქნა ნაპოვნი ოფიციალურ პირველ პარტიაში
2026-08-22-ზე განხილული წყაროები; ეს არ არის იმის მტკიცებულება, რომ ეს შესაძლებლობა არ არის.
ზემოთ მოყვანილი პროდუქტისა და მახასიათებლების განცხადებები შემოწმდა გამყიდველის დოკუმენტაციასთან,
მომწოდებლის მიერ შენახული წყაროს საცავი, ან გამყიდველის ლიცენზიის პირობები იმ თარიღზე და
შეიძლება შეიცვალოს. პროდუქტის სახელები და სავაჭრო ნიშნები ეკუთვნის მათ შესაბამის მფლობელებს;
Rockxy არ არის ასოცირებული ან დამტკიცებული მათ მიერ. შესწორებები მისასალმებელია
Rockxy საკითხის ტრეკერის საშუალებით.

საგზაო რუკაზე: უფრო ღრმა პროტოკოლის მცოდნე წესები, უსაფრთხო რედაქტირებული მტკიცებულებების პაკეტები, უფრო ძლიერი განმეორებითი და შედარების სამუშაო ნაკადები, უფრო ფართო დეველოპერის დაყენების მითითებები და უწყვეტი HTTP/2 და HTTP/3 კვლევა.

## უსაფრთხოება

Rockxy წყვეტს ქსელურ ტრაფიკს - უსაფრთხოება ფუნდამენტურია და არა სურვილისამებრ.

- XPC დამხმარე ამოწმებს აბონენტებს მეშვეობით **სერტიფიკატი-ჯაჭვის შედარება**, არა მხოლოდ პაკეტის ID
- დანამატები მუშაობს **sandboxed JavaScriptCore** 5 წამიანი დროის ამოწურვით, ფაილურ სისტემაზე/ქსელზე წვდომის გარეშე
- **შეყვანის ვალიდაცია** ყველა საზღვრებზე - სხეულის ზომის ქუდები, URI ლიმიტები, regex DoS დაცვა, ბილიკის გავლის პრევენცია
- რწმუნებათა სიგელები **ავტომატურად რედაქტირებულია** დაჭერილ ჟურნალებში
- სენსიტიური ფაილები ინახება **0o600 ნებართვები**

შეატყობინეთ დაუცველობის შესახებ [SECURITY.მდ](SECURITY.md). იხილეთ [სრული უსაფრთხოების არქიტექტურა](docs/development/security.mdx) დეტალებისთვის.

## საგზაო რუკა

Rockxy-ის საჯარო საგზაო რუკა არის სამუშაო პროცესზე ორიენტირებული და თარიღების გარეშე. ის ყურადღებას ამახვილებს საიმედოობაზე, მშობლიურ macOS UX-ზე, გამართვის სამუშაო ნაკადებზე, პროტოკოლის მხარდაჭერაზე, AI/Web3-ის ეპოქის ტრაფიკის ხილვადობაზე, დოკუმენტაციასა და კონტრიბუტორის ჩართვაზე.

- [ROADMAP.md](ROADMAP.md): მაღალი დონის საჯარო ინჟინერიის მიმართულება
- [Rockxy საჯარო საგზაო რუკა](https://github.com/orgs/RockxyApp/projects/1): ოპერაციული ხილვადობა საგზაო რუქით მიკვლევილი საკითხებისთვის

## დოკუმენტაცია

სრული დოკუმენტაცია ხელმისაწვდომია მისამართზე [Rockxy Docs](docs/index.mdx):

- [სწრაფი დაწყების სახელმძღვანელო](docs/quickstart.mdx) - ადექი და გაუშვი წუთებში
- [დეველოპერის დაყენების ცენტრი](docs/features/developer-setup-hub.mdx) — გაშვების ფრაგმენტები, მოწყობილობის სახელმძღვანელო, ვალიდაციის ზონდები და დამხმარე მატრიცა
- [AI Assistant](docs/features/ai-assistant.mdx) — შეისწავლეთ არჩეული traffic ადგილობრივად ან Review Data-ს შემდეგ configured model-ით
- [ფილტრები და ძებნა](docs/core-features/filters-and-search.mdx) — sidebar scope, Focus Sets, Noise Control, toolbar filter და search
- [AI და Web3 ინსპექტირება](docs/features/ai-web3-inspection.mdx) — model API, JSON-RPC და x402 traffic-ის ინსპექტირება
- [MCP ინტეგრაცია](docs/features/mcp.mdx) — დაუკავშირეთ Rockxy ადგილობრივ MCP კლიენტებს
- [არქიტექტურა](docs/development/architecture.mdx) — პროქსი ძრავა, მსახიობის მოდელი, მონაცემთა ნაკადი
- [უსაფრთხოების მოდელი](docs/development/security.mdx) — ნდობის საზღვრები, XPC ვალიდაცია, სერტიფიკატის მართვა
- [დიზაინის გადაწყვეტილებები](docs/development/design-decisions.mdx) - რატომ SwiftNIO, NSTableView, მსახიობები
- [შენობა წყაროდან](docs/development/building.mdx) - აშენება, ტესტირება, ლინტი და გამართვა
- [კოდის სტილი](docs/development/code-style.mdx) - SwiftLint, SwiftFormat და კონვენციები
- [ცვლილებების ჟურნალი](CHANGELOG.md) - გამოუქვეყნებელი ნამუშევარი და მონიშნული რელიზები

## წვლილი შეაქვს

მისასალმებელია შენატანები - კოდი, ტესტები, დოკუმენტები, შეცდომების შესახებ ანგარიშები და UX გამოხმაურება.

იხ **[წვლილი შეიტანოს.მდ](CONTRIBUTING.md)** დაყენების ინსტრუქციებისთვის, კოდის სტილისა და სრული PR საკონტროლო სიისთვის.

კარგი პირველი საკითხები ეტიკეტირებულია [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). პიარის გახსნით თქვენ ეთანხმებით [CLA](CLA.md).

## სპონსორები და პარტნიორები

Rockxy შენარჩუნებულია დამოუკიდებლად. სპონსორობა ეხმარება უწყვეტი განვითარების, რელიზების ინფრასტრუქტურის, დოკუმენტაციისა და უსაფრთხოების სამუშაოს დაფინანსებას.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy-ს ფინანსურ მასპინძლობას უზრუნველყოფს [Open Source Collective](https://docs.oscollective.org/). შემოწირულობები და პროექტის ხარჯები აღირიცხება [Rockxy-ს საჯარო Open Collective გვერდზე](https://opencollective.com/rockxy), რაც მხარდამჭერებს აძლევს გამჭვირვალე ხედვას თანხების მიღებასა და გამოყენებაზე.

| დონე | შენატანი | რას უჭერს მხარს |
|------|----------|------------------|
| **Backer** | თვეში $5-დან | ღია კოდის მოვლა, დოკუმენტაცია, ტესტირება და რელიზები |
| **Builder** | თვეში $25-დან | რეგრესიული ტესტირება, წარმადობის გაუმჯობესება და ყოველდღიური გამართვის სამუშაო პროცესები |
| **Sponsor** | თვეში $100 | კონფიდენციალურობაზე ორიენტირებული და დეველოპერებისთვის უფასო ხელსაწყოს გრძელვადიანი მოვლა |
| **Sustaining Sponsor** | თვეში $500 | მიზნობრივი მოვლა და პროდუქტის განვითარება, მათ შორის რელიზების ავტომატიზაცია და პროტოკოლების მხარდაჭერა |

**პარტნიორობის მოთხოვნები** - დეველოპერის ხელსაწყოების კომპანიები, უსაფრთხოების ფირმები და საწარმოთა გუნდები, რომლებიც ეძებენ პერსონალურ ინტეგრაციას ან თეთრი ეტიკეტის გადაწყვეტილებებს: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## მხარდაჭერა

- [Open Collective](https://opencollective.com/rockxy/donate) — შეიტანეთ წვლილი Rockxy-ში მისი გამჭვირვალე პროექტის ბიუჯეტის მეშვეობით
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) - მხარი დაუჭირეთ Rockxy-ს განვითარებას
- [GitHub საკითხები](https://github.com/RockxyApp/Rockxy/issues) - შეცდომების შესახებ მოხსენებები და ფუნქციების მოთხოვნები
- [GitHub დისკუსიები](https://github.com/RockxyApp/Rockxy/discussions) - კითხვები და საზოგადოების ჩატი
- **ელფოსტა** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **უსაფრთხოების საკითხები** - იხილეთ [SECURITY.მდ](SECURITY.md) პასუხისმგებელი გამჟღავნებისთვის

## ლიცენზია

[GNU Affero General Public License v3.0](LICENSE) — საავტორო უფლება 2024–2026 Rockxy Contributors.

## ვარსკვლავის ისტორია

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>დამზადებულია <a href="https://github.com/LocNguyenHuu">Stephen</a>. აგებულია Swift, SwiftNIO, SwiftUI და AppKit-ით.</sub>
</p>
