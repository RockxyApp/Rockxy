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
  ლოკალური პირველი, AGPL-3.0 ალტერნატივა <a href="#rockxy-vs-alternatives">პროქსიმენი და ჩარლზ პროქსი</a>.
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

## მიმდინარე ფილიალის მაჩვენებლები

- Upstream Proxy ახლა მოიცავს უფასო/ძირითადი ავტომატური პროქსის კონფიგურაციას PAC URL-ის მარშრუტით `DIRECT`, HTTP და HTTPS მარშრუტები არსებული SOCKS5 და ავთენტიფიკაციის პოლიტიკის საზღვრების შენარჩუნებით.
- ექსპორტის სამუშაო ნაკადები ახლა მოიცავს OpenAPI YAML/HTML და შერჩეული ტრაფიკის Gist გამოქვეყნებას რედაქციით გაცნობიერებული დატვირთვის შენობით.
- ინსპექტორის ხელსაწყოები ახლა მოიცავს JSONPath/გასაღების/მნიშვნელობის ფილტრაციას და სწრაფ გადახედვას შერჩეული დატვირთვის ტექსტისთვის, როგორიცაა JWT.
- Node.js Developer Setup ახლა ასახავს არჩეულ კლიენტს ვალიდაციის დროს და აქვს ლოკალური ჰოსტის უფრო სრულყოფილი ნიმუშის სახელმძღვანელო.
- Developer Setup Hub ახლა მოიცავს გაშვების დროებს, ბრაუზერებს, კლიენტებს, მოწყობილობებს, ჩარჩოებსა და გარემოს სამიზნე სპეციფიკური ფრაგმენტებით, ვალიდაციის დამკვირვებლებით და პატიოსანი სახელმძღვანელო კონტენტით.
- WebSocket Protobuf მუშაობა გრძელდება Rockxy-ის უფრო მდიდარი პროტოკოლის შემოწმების მიმართულების ნაწილი.
- საჯარო საგზაო რუქის დაგეგმვა ახლა მოიცავს AI ტრაფიკის პროტოკოლის გამართვას, Web3/RPC ნაკადებს, x402-ის სტილის გადახდის ნაკადებს და უსაფრთხოდ დამუშავებული მტკიცებულებების გაზიარებას.

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

### MCP სერვერი AI ასისტენტებისთვის

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

ნება მიეცით Claude Desktop-ს ან Cursor-ს წაიკითხოს თქვენი გადაღებული ტრაფიკი ადგილობრივი MCP სერვერის მეშვეობით. ჰკითხეთ "რატომ გააკეთა ეს 500?" ჩატში სათაურების ჩასმის ნაცვლად. ლოკალური, რედაქციით გაცნობიერებული და ღია წყარო.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

სათაურების უგულებელყოფა თითო ჰოსტზე სრული კონტროლით ორივე ფაზაზე. შეიტანეთ ავტორიზაციის ჟეტონები გამავალ მოთხოვნებზე, ამოიღეთ Set-Cookie პასუხებზე, ან დაამაგრეთ მორგებული მომხმარებლის აგენტი - შენახული დასახელებული წესების სახით, რომელთა გადართვა შეგიძლიათ ნებისმიერ დროს.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### ქსელის პირობები

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

დროებით 3G, EDGE, LTE, WiFi ან მორგებული დაყოვნება. თქვენი ლეპტოპი არის ბოჭკოზე; თქვენი მომხმარებლები არ არიან — იხილეთ UX 400 ms RTT-ზე, სანამ ამას გააკეთებენ.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### შედგენა - რედაქტირება და გამეორება

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

აღადგინეთ ნებისმიერი დაჭერილი HTTP მოთხოვნა - შეცვალეთ მეთოდი, URL, სათაურები, მოთხოვნის პარამეტრები ან ტექსტი - და ხელახლა გაგზავნეთ Rockxy-ის დატოვების გარეშე. არ არის ფოსტალიონი, უძილობა, ან კოპირება-პასტის ციკლი. გაიმეორეთ LLM მოთხოვნებზე, გააფუჭეთ ავტორიზაციის საზღვრები ან შეცვალეთ OpenAI, Anthropic და Cohere ბოლო წერტილების წარუმატებელი შემთხვევა წამებში.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### შეადარე

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

დააწყვეთ ორი გადაღებული პასუხი გვერდიგვერდ და დააფიქსირეთ ყველა ველი, რომელიც გადატრიალდა - სტატუსი, სათაურები, JSON კლავიშები, ძირითადი ბაიტები. დაიჭირეთ ჩუმი API რეგრესია, არადეტერმინისტული LLM გამომავალი და სწრაფი დრიფტი მესამე მხარის განსხვავებულ ინსტრუმენტში რაიმეს მიწოდების გარეშე. გვერდიგვერდ განსხვავება ხაზს უსვამს იმას, რაც შეიცვალა; ღრმა JSON შედარება უგულებელყოფს გასაღების შეკვეთას.

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

ჩაატარეთ დამოუკიდებელი გადაღების სესიები გვერდიგვერდ - ერთი ჩანართი დადგმისთვის, ერთი პროდისთვის, ერთი iOS მოწყობილობის შესაქმნელად. თითოეულ ჩანართს აქვს საკუთარი ფილტრები, შერჩევა და ინსპექტორის მდგომარეობა, ამიტომ კონტექსტის შეცვლა არ ღირს.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript სკრიპტირება

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS აკავშირებს მოთხოვნებსა და პასუხებს იმ შემთხვევებზე, რომლებსაც სტატიკური წესი არ შეუძლია დაფაროს - PII-ის რედაქტირება, ნიშნების ხელმოწერა, დატვირთვის გადაწერა. შეცდომები ჩნდება ხაზში, ტრაფიკის გაფუჭების ნაცვლად.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## მეტი ფუნქციები მალე

მომავალი ფუნქციების თვალყურის დევნება ხდება საჯაროდ და იგზავნება მხოლოდ მაშინ, როდესაც დანერგვა, ტესტები, კონფიდენციალურობის ქცევა და დოკუმენტაცია მზად არის.

### AI Traffic Inspection `მალე`

გააადვილეთ მოდელის ტრაფიკის გამართვა ნორმალური გადაღების სამუშაო ნაკადში. გამოავლინეთ AI მოთხოვნები, შეამოწმეთ არჩეული მოდელის ზარები, დაადგინეთ სტრიმინგის პასუხები, შეადარეთ მოთხოვნის/გამომავალი ქცევა და გაიგეთ ხელსაწყო-ზარის ჯაჭვები მგრძნობიარე დატვირთვის სხვა სერვისში ჩასმის გარეშე.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Web3/RPC ინსპექტირება `მალე`

გადააქციეთ ბლოკჩეინის ეპოქის ქსელის ზარები წაკითხვადი გამართვის მტკიცებულებად. შეამოწმეთ JSON-RPC და Solana RPC ტრაფიკი, დააჯგუფეთ დაკავშირებული ზარები ნაკადებში, აუხსენით საერთო RPC შეცდომებს და განაახლეთ არჩეული მოთხოვნები ისე, რომ არ გახდეთ საფულე ან ბლოკის მკვლევარი.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### x402 გადახდის ნაკადის გამართვა `მალე`

გაიგეთ გადახდის დახურული HTTP ნაკადები ქსელის ფენიდან. მონიშნეთ გადახდისთვის საჭირო პასუხები, მიჰყევით ხელახლა ცდის გზას და შეინახეთ გამართვის მტკიცებულება ლოკალური და რედაქტირების შესახებ.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### რედაქტირებული მტკიცებულებების პაკეტები `მალე`

გააზიარეთ ფაქტები, რომლებიც საჭიროა შეცდომების გასამრავლებლად საიდუმლოების გაჟონვის გარეშე. შეფუთეთ არჩეული ტრაფიკი პროტოკოლის შეჯამებებით, რედაქციის წინასწარი გადახედვით და წყაროზე მხარდაჭერილი კონტექსტით, რომელსაც თანაგუნდელს შეუძლია შეამოწმოს.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Protocol-Aware ფილტრები და წესები `მალე`

გამოიყენეთ AI და Web3 მეტამონაცემები, სადაც Rockxy უკვე მუშაობს: ფილტრები, სამკერდე ნიშნები, სურვილისამებრ სვეტები, შედარება, წესები, დეველოპერის დაყენება და ადგილობრივი MCP შეჯამებები.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### გუნდის გაზიარება და თანამშრომლობა `მალე`

გაუგზავნეთ გადაღებული სესია თანაგუნდელს ერთი დაწკაპუნებით. ჩაწერეთ წარუმატებელი მოთხოვნები ხაზში, ნახეთ ვინ რას უყურებს რეალურ დროში და დააწყვილეთ HTTPS ტრაფიკი ეკრანის გაზიარების გარეშე. გამიზნულია მომავალი გამოშვებისთვის.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% მშობლიური macOS. არანაირი ელექტრონი. ვებ ნახვები არ არის. SwiftUI + AppKit + SwiftNIO.

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

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **პროექტის მოდელი** | AGPL-3.0 ღია კოდის პროექტი | საკუთრების კომერციული აპლიკაცია | საკუთრების კომერციული აპლიკაცია |
| **წყაროს კოდი** | საჯარო, აუდიტორული, ჩანგალი | დახურული წყარო | დახურული წყარო |
| **აშენება წყაროდან** | უფასოა Xcode-ით ამ რეპოდან | მიუწვდომელია საჯარო წყაროდან | მიუწვდომელია საჯარო წყაროდან |
| **მშობლიური macOS ფონდი** | Swift + SwiftNIO + SwiftUI/AppKit | მშობლიური macOS კომერციული აპლიკაცია | მრავალპლატფორმული კომერციული აპლიკაცია |
| **ადგილობრივი პირველი დაჭერა** | ადგილობრივი პროქსი, სერთიფიკატები, დამხმარე და გადაღების მონაცემები რჩება თქვენს Mac-ზე | დესკტოპის პროქსი აპი | დესკტოპის პროქსი აპი |
| **დეველოპერის დაყენების სამუშაო პროცესი** | ჩაშენებული Developer Setup Hub სამუშაო დროის, კლიენტების, მოწყობილობების, ჩარჩოებისა და გარემოსთვის | პროდუქტის სპეციფიკური დაყენების ინსტრუქცია | პროდუქტის სპეციფიკური დაყენების ინსტრუქცია |
| **გარე პროქსი + PAC მარშრუტიზაცია** | HTTP/HTTPS ზემორე პროქსი, PAC ავტომატური კონფიგურაცია და შემოვლითი წესები | სექსუალური კომერციული მარიონეტული ხელსაწყოები | სექსუალური კომერციული მარიონეტული ხელსაწყოები |
| **MCP/ლოკალური ავტომატიზაციის ხიდი** | ჩაშენებული, ჟეტონებით დამოწმებული, რედაქცია ნაგულისხმევად | არ არის მოთხოვნილი განხილულ საჯარო დოკუმენტებში | არ არის მოთხოვნილი განხილულ საჯარო დოკუმენტებში |
| **გახსენით კონტრიბუციის გზა** | საჯარო საკითხები, დისკუსიები, საგზაო რუკა და PR-ები | გამყიდველის მიერ კონტროლირებადი პროდუქტი | გამყიდველის მიერ კონტროლირებადი პროდუქტი |

საგზაო რუკაზე: უფრო ღრმა გამეორება/განსხვავებები/წესები/სკრიპტირების სამუშაო ნაკადები, გაუმჯობესებული WebSocket და GraphQL ინსპექტირება, პროტოკოლის ცოდნა AI და Web3/RPC გამართვა, x402 სტილის გადახდის ნაკადის ხილვადობა და gRPC/Protobuf პლუს HTTP/2 და HTTP/3 მხარდაჭერა.

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

Rockxy აშენებულია და შენარჩუნებულია დამოუკიდებელი დეველოპერების მიერ. სპონსორობის ფონდი განაგრძობს განვითარებას, უსაფრთხოების აუდიტს და ახალ ფუნქციებს.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

| იარუსი | სარგებელი |
|------|----------|
| **ოქროს სპონსორი** | ლოგო README + docs საიტზე, პრიორიტეტული ფუნქციების მოთხოვნები, პირდაპირი მხარდაჭერის არხი |
| **ვერცხლის სპონსორი** | ლოგო README-ზე, სახელწოდებით აღიარება გამოშვების შენიშვნებში |
| **ბრინჯაოს სპონსორი** | დასახელებული აღიარება README-სა და დოკუმენტებში |
| **პარტნიორი** | ერთობლივი განვითარება, ინტეგრაციის მხარდაჭერა, ადრეული წვდომა მომავალ ფუნქციებზე |

**პარტნიორობის მოთხოვნები** - დეველოპერის ხელსაწყოების კომპანიები, უსაფრთხოების ფირმები და საწარმოთა გუნდები, რომლებიც ეძებენ პერსონალურ ინტეგრაციას ან თეთრი ეტიკეტის გადაწყვეტილებებს: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## მხარდაჭერა

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) - მხარი დაუჭირეთ Rockxy-ს განვითარებას
- [GitHub საკითხები](https://github.com/RockxyApp/Rockxy/issues) - შეცდომების შესახებ მოხსენებები და ფუნქციების მოთხოვნები
- [GitHub დისკუსიები](https://github.com/RockxyApp/Rockxy/discussions) - კითხვები და საზოგადოების ჩატი
- **ელფოსტა** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **უსაფრთხოების საკითხები** - იხილეთ [SECURITY.მდ](SECURITY.md) პასუხისმგებელი გამჟღავნებისთვის

## ლიცენზია

[GNU Affero General Public License v3.0](LICENSE) — საავტორო უფლება 2024–2026 Rockxy Contributors.

## ვარსკვლავის ისტორია

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>დამზადებულია <a href="https://github.com/LocNguyenHuu">სტეფანე</a>. აგებულია Swift, SwiftNIO, SwiftUI და AppKit-ით.</sub>
</p>
