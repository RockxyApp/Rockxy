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
  <strong>ওপেন সোর্স, macOS-এর জন্য অডিটযোগ্য ডিবাগিং প্রক্সি।</strong>
</p>

<p align="center">
  একটি নেটিভ সুইফট অ্যাপের মাধ্যমে HTTP/HTTPS/WebSocket/GraphQL ট্র্যাফিককে আটকান, পরিদর্শন করুন এবং সংশোধন করুন আপনি পরিদর্শন, নির্মাণ এবং বিশ্বাস করতে পারেন।<br>
  এপিআই, মোবাইল, এমসিপি-সহায়তা, এআই, এবং ব্লকচেইন-যুগের ডিবাগিং ওয়ার্কফ্লোগুলির জন্য তৈরি করা হয়েছে রকক্সি বিকশিত হওয়ার সাথে সাথে।<br>
  <a href="#rockxy-বনাম-বিকল্প">Proxyman এবং Charles Proxy</a>-এর একটি local-first, AGPL-3.0 বিকল্প।
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

## বর্তমান শাখা হাইলাইট

- AI Assistant এখন এক বা একাধিক নির্বাচিত request-কে বিল্ট-ইন লোকাল অ্যানালাইসিস বা ঐচ্ছিক কনফিগার করা Ollama/provider model দিয়ে তদন্ত করে, স্পষ্ট Review Data নিশ্চিতকরণ, সীমিত redaction, streaming response, evidence reveal এবং ব্যবহারকারী-সূচিত handoff সহ।
- নেটিভ sidebar-এ এখন app/domain/path scope-এর জন্য পুনঃব্যবহারযোগ্য Focus Sets এবং workspace-স্তরের Noise Control আছে যা capture না থামিয়ে মিলে যাওয়া domain বা path লুকিয়ে রাখে।
- প্রধান workspace এখন Context Dock ও নিচের inspector-এর জন্য নেটিভ উল্লম্ব ও অনুভূমিক split view ব্যবহার করে, পূর্ণ-উচ্চতার divider, সমন্বিত toolbar/footer separator এবং স্বয়ংক্রিয় লেআউট রিসাইজিং বজায় রেখে।
- আপস্ট্রিম প্রক্সিতে এখন PAC URL রাউটিং সহ বিনামূল্যে/কোর স্বয়ংক্রিয় প্রক্সি কনফিগারেশন অন্তর্ভুক্ত রয়েছে `DIRECT`, HTTP, এবং HTTPS রুট বিদ্যমান SOCKS5 এবং প্রমাণীকরণ নীতি সীমানা সংরক্ষণ করার সময়।
- রপ্তানি কর্মপ্রবাহ এখন OpenAPI YAML/HTML এবং নির্বাচিত-ট্র্যাফিক সংক্ষিপ্ত প্রকাশনাকে রিডাকশন-সচেতন পেলোড বিল্ডিং সহ কভার করে।
- পরিদর্শক সরঞ্জামগুলিতে এখন JSONPath/কী/মান ফিল্টারিং এবং JWT-এর মতো নির্বাচিত পেলোড পাঠ্যের জন্য দ্রুত পূর্বরূপ অন্তর্ভুক্ত রয়েছে।
- AI ও Web3 ট্র্যাফিক পরিদর্শন এখন স্বীকৃত মডেল কল, JSON-RPC ট্র্যাফিক এবং x402-স্টাইল পেমেন্ট হিন্টের জন্য প্রোটোকল লেবেল, inspector ট্যাব এবং ডিবাগ সারাংশ যোগ করে।
- Node.js বিকাশকারী সেটআপ এখন বৈধকরণের সময় নির্বাচিত ক্লায়েন্টকে মিরর করে এবং একটি পূর্ণাঙ্গ লোকালহোস্ট নমুনা গাইড রয়েছে।
- ডেভেলপার সেটআপ হাব এখন রানটাইম, ব্রাউজার, ক্লায়েন্ট, ডিভাইস, ফ্রেমওয়ার্ক এবং টার্গেট-নির্দিষ্ট স্নিপেট, বৈধতা পর্যবেক্ষক এবং সৎ গাইড সামগ্রী সহ পরিবেশ কভার করে।
- WebSocket binary-frame inspection এখন capture hot path-এ decoder work না যোগ করে সীমিত, on-demand Protobuf wire-format heuristic দেয়।
- পাবলিক রোডম্যাপ এখন গভীর protocol-aware rules, replay, comparison এবং নিরাপদ redacted evidence sharing-এ কেন্দ্রীভূত।

## বৈশিষ্ট্য

যখন ব্রাউজার DevTools পর্যাপ্ত নয় তখন আপনি যে টুলগুলির জন্য পৌঁছান। Mac এবং iOS কাজের জন্য মূল ট্রাফিক ডিবাগিং — macOS-এ নেটিভ, পাবলিক রিলিজ এবং স্থানীয়-প্রথম ওয়ার্কফ্লো সহ।

### ট্রাফিক ক্যাপচার

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

যেকোন ম্যাক অ্যাপ, সিএলআই বা iOS ডিভাইস থেকে HTTP, HTTPS, WebSocket এবং GraphQL ট্র্যাফিক পরিদর্শন করুন। ব্রাউজার DevTools ব্রাউজারে শেষ হয় — Rockxy আপনার বাকি স্ট্যাক দেখে।

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### উন্নত ফিল্টার এবং অনুসন্ধান

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

কয়েক সেকেন্ডের মধ্যে ক্যাপচার করা অনুরোধগুলিকে সংকুচিত করুন। মেথড, হোস্ট, স্ট্যাটাস, হেডার, বডি এবং প্রসেস ফিল্টার একত্রিত করুন — অথবা পুরো সেশন জুড়ে একটি পূর্ণ-পাঠ্য অনুসন্ধান চালান।

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets ও Noise Control

পুনরাবৃত্ত তদন্তকে সাইডবারের পুনঃব্যবহারযোগ্য scope-এ পরিণত করুন। Focus Sets app, domain ও path include-এর সঙ্গে domain/path exclude একত্র করে, পুনরায় চালুর পরও থাকে এবং প্রতিটি workspace-এ পাওয়া যায়। Noise Control telemetry ও কম-মূল্যের traffic capture করতে থাকে, কিন্তু বর্তমান workspace-এ লুকিয়ে রাখে।

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant native request table ও sidebar-এর পাশে নির্বাচিত traffic ব্যাখ্যা করছে" width="820" />

এক বা একাধিক capture করা request নির্বাচন করে জিজ্ঞাসা করুন কী ঘটেছে, কী ব্যর্থ হয়েছে, কী বদলেছে বা পরবর্তী কী যাচাই করা উচিত। Rockxy প্রথমে এই Mac-এ evidence-based analysis চালায়; কনফিগার করা Ollama বা provider model শুধু Review Data সুনির্দিষ্ট, সীমিত ও redacted context দেখানোর পরে চলে। response source request প্রকাশ ও native follow-up workflow প্রস্তুত করতে পারে, কিন্তু traffic পরিবর্তন বা action স্বয়ংক্রিয়ভাবে চালায় না।

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[AI Assistant গাইড পড়ুন](docs/features/ai-assistant.mdx)।

### বাহ্যিক AI ক্লায়েন্টের জন্য MCP সার্ভার

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Claude Desktop বা Cursor-কে Rockxy-এর লোকাল MCP সার্ভারের দশটি রিড-অনলি টুলের মাধ্যমে আপনার ক্যাপচার করা ট্র্যাফিক পরিদর্শন করতে দিন। চ্যাটে হেডার পেস্ট করার পরিবর্তে জিজ্ঞাসা করুন "কেন এই 500?"। বাস্তবায়নটি ওপেন সোর্স, token-প্রমাণিত এবং সংবেদনশীল ডেটা redaction ডিফল্টভাবে চালু রাখে।

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### বিকাশকারী সেটআপ হাব

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Python, Node.js, Go, Rust, cURL, Docker এবং ব্রাউজারগুলির জন্য প্রক্সি স্নিপেট কপি-পেস্ট করুন, তারপরে ট্র্যাফিক আসলে প্রবাহিত হচ্ছে তা নিশ্চিত করতে Run Test-এ ক্লিক করুন।

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### HTTPS ডিবাগিংয়ের জন্য শংসাপত্র ব্যবস্থাপনা

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

একটি P-256 ECDSA রুট CA প্রথম লঞ্চের সময় উত্পন্ন, আপনার কীচেইনে সিল করা হয়েছে৷ প্রথম চেষ্টায় HTTPS ডিক্রিপ্ট করুন; পিন করা হোস্ট স্বয়ংক্রিয়ভাবে পাস.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL প্রক্সি এবং HTTPS ডিক্রিপশন

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

কোন হোস্ট টিএলএস ডিক্রিপশন পাবেন তা বেছে নিন। ডিক্রিপ্ট করা ট্রাফিক বাস্তব হেডার এবং JSON দেখায়; বাকি সবকিছু এনক্রিপ্টেড মাধ্যমে পাস. ওয়াইল্ডকার্ড নিয়ম আপনাকে এক ক্লিকে ডোমেনের মাধ্যমে সুযোগ দিতে দেয়।

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### বাইপাস প্রক্সি

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

নির্দিষ্ট হোস্টগুলি এড়িয়ে যান যাতে শংসাপত্র-পিন করা অ্যাপ, অভ্যন্তরীণ পরিষেবা, বা শোরগোলপূর্ণ টেলিমেট্রি কখনই ক্যাপচারে প্রবেশ না করে। ওয়াইল্ডকার্ড তালিকাটি সংক্ষিপ্ত রাখে এবং আপনার অনুরোধের লগ আপনি আসলে কী বিষয়ে যত্নশীল তার উপর ফোকাস করে।

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### ব্লক তালিকা

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

কোনো হোস্ট ব্যর্থ করুন. বিজ্ঞাপন নেটওয়ার্ক, থার্ড-পার্টি ট্র্যাকার বা ফ্ল্যাকি ডিপেন্ডেন্সি বাদ দিন যে আপনার অ্যাপটি চলে গেলে কীভাবে এটির অবনতি হয় — কোডের একটি লাইন পরিবর্তন না করেই।

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### মানচিত্র স্থানীয়

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

একটি লাইভ প্রতিক্রিয়ার জায়গায় একটি সংরক্ষিত ফাইল বা একটি ডিরেক্টরি গাছ পরিবেশন করুন। আপনি ডিবাগ করার সময় একটি JSON পেলোড অদলবদল করুন, একটি স্ন্যাপশট পুনরায় চালান, বা একটি ফ্ল্যাকি তৃতীয় পক্ষের API পিন করুন স্থানীয় অনুলিপিতে।

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### ম্যাপ রিমোট

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

অ্যাপ কোড বা /etc/hosts স্পর্শ না করে একটি ক্যাপচার করা অনুরোধের গন্তব্য পুনরায় লিখুন। একটি পুনরুত্পাদনযোগ্য বাগ রিপ্রোর জন্য স্টেজিং, আপনার ডেভ সার্ভার বা সহকর্মীর মেশিনে প্রোডাকশন ট্র্যাফিক পয়েন্ট করুন।

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### ব্রেকপয়েন্ট এবং নিয়ম

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

একটি অনুরোধ বা প্রতিক্রিয়া, সম্পাদনা পদ্ধতি, শিরোনাম, বডি, বা স্থিতি বিরতি দিন, তারপর চালিয়ে যান। পরীক্ষা করার দ্রুততম উপায় "যদি API 401 ফেরত দেয়?" ব্যাকএন্ড স্পর্শ না করে।

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### হেডার পরিবর্তন করুন

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

পুনঃনিয়োগ না করে যেকোনো হোস্টে শিরোনাম যোগ করুন, সরান বা প্রতিস্থাপন করুন। বিল্ট-ইন প্রিসেটগুলির সাথে কয়েক সেকেন্ডে CORS, প্রমাণীকরণ বা ক্যাশে পরিবর্তনগুলি পরীক্ষা করুন৷

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### কাস্টম অনুরোধ এবং প্রতিক্রিয়া শিরোনাম

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

যেকোনো request বা response হেডারকে ট্র্যাফিক টেবিলের একটি প্রথম-শ্রেণির কলামে উন্নীত করুন। request ও response উৎস আলাদা রাখুন, আপনার পছন্দের হেডার সংরক্ষণ করুন, তারপর প্রতিটি inspector না খুলেই request ID, trace ID, cache অবস্থা বা কাস্টম মেটাডেটা স্ক্যান করুন।

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### নেটওয়ার্ক শর্তাবলী

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

থ্রটল 3G, EDGE, LTE, WiFi, বা একটি কাস্টম বিলম্ব। আপনার ল্যাপটপ ফাইবার আছে; আপনার ব্যবহারকারীরা নন — তারা করার আগে 400 ms RTT এ UX দেখুন।

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### রচনা করুন — সম্পাদনা করুন এবং পুনরায় চালান

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

কোনো ক্যাপচার করা HTTP অনুরোধ পুনর্নির্মাণ করুন — পদ্ধতি, URL, শিরোনাম, ক্যোয়ারী প্যারাম, বা বডি পরিবর্তন করুন — এবং Rockxy না রেখেই পুনরায় পাঠান। Postman, Insomnia বা curl-এর কপি-পেস্ট লুপ নেই। LLM প্রম্পটে পুনরাবৃত্তি করুন, প্রমাণীকরণের সীমানা fuzz করুন বা OpenAI, Anthropic এবং Cohere এন্ডপয়েন্টের জন্য সেকেন্ডের মধ্যে একটি ব্যর্থ কেস পুনরুত্পাদন করুন।

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### তুলনা করুন

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

দুটি ক্যাপচার করা লেনদেন বা পেস্ট করা payload পাশাপাশি স্ট্যাক করুন এবং পরিবর্তিত প্রতিটি ক্ষেত্র চিহ্নিত করুন — স্ট্যাটাস, হেডার, JSON কী বা বডি বাইট। তৃতীয় পক্ষের diff টুলে কিছু না পাঠিয়ে নীরব API রিগ্রেশন, নন-ডিটারমিনিস্টিক LLM আউটপুট এবং prompt drift ধরুন।

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### কাস্টম প্রিভিউয়ার ট্যাব

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

আপনি যেভাবে চান অনুরোধ এবং প্রতিক্রিয়া সংস্থাগুলিকে রেন্ডার করুন। JSON, GraphQL, JWT, ইমেজ বা আপনার নিজস্ব ফর্ম্যাটের জন্য পরিদর্শকের কাছে অতিরিক্ত ট্যাবগুলি পিন করুন — প্রতিটি ক্যাপচার করা অনুরোধ জুড়ে পুনরায় ব্যবহারযোগ্য।

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### অধিবেশন এবং রপ্তানি

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

সেশন সংরক্ষণ করুন, ক্রস-টুল হ্যান্ডঅফের জন্য HAR আমদানি/রপ্তানি করুন, CURL বা JSON হিসাবে যেকোনো অনুরোধ অনুলিপি করুন। শেয়ার করার আগে অনুমোদনের শিরোনাম, কুকিজ, এবং বাহক টোকেনগুলি সংশোধন করুন — গোপনীয়তা ফাঁস না করে একজন সতীর্থকে একটি কার্যকরী বাগ রিপ্রো হস্তান্তর করুন৷

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### মাল্টি-ট্যাব ওয়ার্কস্পেস

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy মাল্টি-ট্যাব ওয়ার্কস্পেস একই লাইভ ক্যাপচারের স্বাধীনভাবে ফিল্টার করা ভিউ দেখাচ্ছে" width="820" />

একই লাইভ ক্যাপচারের স্বাধীন তদন্ত ভিউ পাশাপাশি রাখুন — একটি ট্যাব staging ট্র্যাফিকের জন্য, একটি production-এর জন্য এবং একটি iOS ডিভাইস ফ্লোর জন্য। প্রতিটি ট্যাবের নিজস্ব ফিল্টার, সাজানো, নির্বাচন, সাইডবার স্কোপ এবং পরিদর্শক অবস্থা থাকে, কিন্তু প্রক্সি ও ক্যাপচার করা লেনদেন শেয়ার করে।

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### জাভাস্ক্রিপ্ট স্ক্রিপ্টিং

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

একটি স্ট্যাটিক নিয়ম কভার করতে পারে না এমন ক্ষেত্রে অনুরোধ এবং প্রতিক্রিয়াগুলির উপর JS হুক করে — PII সংশোধন করুন, টোকেন সাইন করুন, পেলোডগুলি পুনরায় লিখুন। ট্র্যাফিককে দূষিত করার পরিবর্তে ত্রুটিগুলি সারফেস ইনলাইন।

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## প্রোটোকল-সচেতন পরিদর্শন

Rockxy সাধারণ HTTP debugging workflow-এর মধ্যে protocol-aware AI, Web3 RPC ও x402 inspection দেয়।

### এআই ট্রাফিক পরিদর্শন

Rockxy সাধারণ ক্যাপচার ওয়ার্কফ্লোর মধ্যে স্বীকৃত AI অনুরোধ সনাক্ত করে। নির্বাচিত মডেল কল, streaming অবস্থা, উপস্থিত থাকলে usage ফিল্ড, সতর্কতা, retrieval hints এবং tool-call সারাংশ সংবেদনশীল payload অন্য পরিষেবাতে পেস্ট না করে পরিদর্শন করুন।

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC পরিদর্শন

Rockxy ব্লকচেইন-যুগের নেটওয়ার্ক কলকে পাঠযোগ্য ডিবাগিং প্রমাণে রূপান্তরিত করে। EVM ও Solana-style HTTP JSON-RPC traffic provider host, request ID, method, batch summary, error, chain, transaction, payload ও debug-intent detailসহ inspect করুন, Rockxy-কে wallet বা block explorer না বানিয়ে।

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 পেমেন্ট ফ্লো হিন্ট

Rockxy payment-required ও retry-ভিত্তিক হিন্ট হাইলাইট করে যাতে payment-gated HTTP ফ্লো নেটওয়ার্ক লেয়ার থেকে বোঝা যায়, যখন ডিবাগিং প্রমাণ লোকাল ও redaction-aware থাকে।

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## ভবিষ্যৎ কাজ

পরবর্তী বিভাগগুলো বর্তমান আচরণ নয়, প্রকাশ্য দিকনির্দেশ বর্ণনা করে।

### প্রোটোকল-সচেতন নিয়ম

Rockxy আজ AI ও Web3 ট্র্যাফিক লেবেল ও পরিদর্শন করতে পারে। model, tool call, JSON-RPC method, chain, transaction hash বা batch subcall অনুসারে গভীর নিয়ম মিলানো এখনও ভবিষ্যতের কাজ; বর্তমান ট্র্যাফিক পরিবর্তন টুলগুলো এখনও URL, HTTP method ও হেডার মিলায়।

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### রিডাক্টেড এভিডেন্স বান্ডেল `শীঘ্রই আসছে`

গোপনীয়তা ফাঁস না করে একটি বাগ পুনরুত্পাদন করার জন্য প্রয়োজনীয় তথ্যগুলি ভাগ করুন৷ প্রোটোকল সারাংশ, রিডাকশন প্রিভিউ এবং সোর্স-ব্যাকড কনটেক্সট সহ নির্বাচিত ট্র্যাফিক প্যাকেজ করুন একজন সতীর্থ অডিট করতে পারে।

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### টিম শেয়ারিং এবং সহযোগিতা `শীঘ্রই আসছে`

এক ক্লিকে সতীর্থকে একটি ক্যাপচার করা সেশন পাঠান। ইনলাইনে ব্যর্থ হওয়া অনুরোধগুলি টীকা করুন, রিয়েল টাইমে কে কী দেখছে তা দেখুন এবং স্ক্রিন-শেয়ারিং ছাড়াই HTTPS ট্র্যাফিক জোড়া-ডিবাগ করুন৷ ভবিষ্যতের মুক্তির লক্ষ্যে।

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> নেটিভ macOS অ্যাপ শেল — কোনো Electron নেই। SwiftUI + AppKit + SwiftNIO, HTML বডি প্রিভিউয়ের জন্য শুধু WebKit ব্যবহৃত হয়।

## দ্রুত শুরু

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

এক্সকোডে তৈরি করুন এবং চালান। স্বাগতম উইন্ডো আপনাকে রুট CA সেটআপ, হেল্পার ইনস্টলেশন এবং প্রক্সি অ্যাক্টিভেশনের মাধ্যমে গাইড করে।

**প্রয়োজনীয়তা:** macOS 14.0+, Xcode 16+, Swift 5.9

আপনি যদি ইনস্টলেশনের পরে স্থানীয় MCP ক্লায়েন্টের সাথে Rockxy সংযোগ করতে চান, দেখুন [MCP ইন্টিগ্রেশন গাইড](docs/features/mcp.mdx).

## Rockxy বনাম বিকল্প

প্রধান ম্যাট্রিক্স সাধারণ-উদ্দেশ্য ওয়েব-ডিবাগিং প্রক্সি কভার করে। নিরাপত্তা-পরীক্ষা
স্যুট এবং ব্রাউজার/API-ভিত্তিক ইন্টারসেপ্টর যথেষ্ট ওয়ার্কফ্লো ওভারল্যাপ সহ
আলাদাভাবে তালিকাভুক্ত করা হয়েছে তাই পণ্যের বিপরীতে বিনিময়যোগ্য হিসাবে উপস্থাপিত হয় না।
প্যাকেট বিশ্লেষক এবং API-শুধুমাত্র ক্লায়েন্টরা এই তুলনার বাইরে।

### সরাসরি ওয়েব-ডিবাগিং প্রক্সি

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **পণ্যের আকার** | নেটিভ macOS ডিবাগিং প্রক্সি | নেটিভ macOS অ্যাপ; Electron-ভিত্তিক উইন্ডোজ/লিনাক্স সংস্করণ | ক্রস-প্ল্যাটফর্ম ডেস্কটপ ডিবাগিং প্রক্সি | ক্রস-প্ল্যাটফর্ম CLI/TUI এবং ওয়েব UI প্রক্সি টুলকিট | ক্রস-প্ল্যাটফর্ম Electron ডেস্কটপ প্রক্সি এবং HTTP ক্লায়েন্ট | ক্রস-প্ল্যাটফর্ম ডেস্কটপ ডিবাগিং প্রক্সি |
| **উৎস এবং বিল্ড মডেল** | AGPL-3.0-or-later এর অধীনে পাবলিক Community source; Xcode দিয়ে নির্মাণযোগ্য। অফিসিয়াল DMG-তে অ-পাবলিক downstream component-ও রয়েছে | বন্ধ উৎস; পর্যালোচিত official material-এ কোনো public application source চিহ্নিত করা হয়নি | বন্ধ উৎস; পর্যালোচিত official material-এ কোনো public application source চিহ্নিত করা হয়নি | সর্বজনীন MIT-licensed source; source থেকে নির্মাণযোগ্য | সর্বজনীন AGPL desktop source; source থেকে নির্মাণযোগ্য; প্রকাশিত binary-তে অতিরিক্ত licensing option রয়েছে | বন্ধ উৎস; Fiddler Everywhere EULA-এর অধীনে object code হিসেবে বিতরণ করা হয় |
| **ক্যাপচার এবং সেটআপ** | ম্যাক অ্যাপ, রানটাইম, iOS ডিভাইস এবং সিমুলেটরের জন্য নির্দেশিত সেটআপসহ স্থানীয় সিস্টেম প্রক্সি | ম্যাক অ্যাপ, রানটাইম এবং মোবাইল ডিভাইসের জন্য স্বয়ংক্রিয় সেটআপ | macOS, iOS এবং অন্যান্য প্ল্যাটফর্মের সেটআপ গাইডসহ স্থানীয় প্রক্সি | নিয়মিত, local-process, WireGuard, reverse, transparent এবং অন্যান্য capture mode | ব্রাউজার, রানটাইম, কন্টেইনার এবং মোবাইল ডিভাইসের জন্য targeted ও manual proxy interception | system, network, browser, terminal, explicit এবং remote-device capture mode |
| **পরিবর্তন এবং উপহাস** | ব্রেকপয়েন্ট, Map Local/Remote, হেডার নিয়ম, ব্লকিং, এবং লেটেন্সি নিয়ম | ব্রেকপয়েন্ট, Map Local/Remote, ব্লক তালিকা, নেটওয়ার্ক শর্ত, এবং JavaScript নিয়ম | ব্রেকপয়েন্ট, পুনর্লিখন, Map Local/Remote, ব্লক করা, এবং থ্রটলিং | Map Local/Remote, বডি/হেডার পরিবর্তন, ব্লকিং, এবং সার্ভার রিপ্লে | ব্রেকপয়েন্ট প্লাস নিয়ম-ভিত্তিক পুনর্লিখন, পুনঃনির্দেশ, উপহাস এবং ত্রুটি ইনজেকশন; কিছু অটোমেশন পরিকল্পনা-সীমিত | নিয়ম, ব্রেকপয়েন্ট, পুনঃনির্দেশ, প্রতিক্রিয়া পরিবর্তন, এবং উপহাস |
| **পুনরায় খেলুন এবং তুলনা করুন** | কম্পোজ/রিপ্লে প্লাস স্থানীয় পাশাপাশি অনুরোধ, হেডার, এবং বডি তুলনা | রচনা, পুনরাবৃত্তি, এবং পার্থক্য | অনুরোধগুলি পুনরাবৃত্তি করুন এবং সম্পাদনা করুন | ক্লায়েন্ট-সাইড এবং সার্ভার-সাইড রিপ্লে | কম্পোজ এবং অনুরোধ পাঠানোর জন্য অন্তর্নির্মিত HTTP ক্লায়েন্ট | API কম্পোজার, ট্রাফিক রিপ্লে, এবং ট্রাফিক তুলনা বিটা হিসাবে নথিভুক্ত |
| **WebSocket কর্মপ্রবাহ** | আবদ্ধ Protobuf হিউরিস্টিক সহ পাঠ্য/বাইনারি ফ্রেম পরিদর্শন | WS/WSS পরিদর্শন; স্ক্রিপ্ট হ্যান্ডশেক URL/হেডার পরিবর্তন করতে পারে, বার্তা নয় | WebSocket সমর্থন অফিসিয়াল সংস্করণ ইতিহাসে নথিভুক্ত করা হয়েছে | WebSocket ইন্টারসেপশন এবং স্ক্রিপ্টিং; WebSocket রিপ্লে সমর্থিত নয় | WebSocket পরিদর্শন প্লাস WebSocket-নির্দিষ্ট নিয়ম | WebSocket ক্যাপচার এবং পরিদর্শন |
| **স্ক্রিপ্টিং এবং এক্সটেনসিবিলিটি** | একটি আবদ্ধ API সহ স্যান্ডবক্সযুক্ত JavaScriptCore হুক এবং এক্সিকিউশন টাইমআউট | JavaScript অনুরোধ/প্রতিক্রিয়া স্ক্রিপ্টিং | নিয়ম এবং একটি নিয়ন্ত্রণ ওয়েব ইন্টারফেস পুনর্লিখন; কোন সাধারণ JavaScript স্ক্রিপ্টিং বৈশিষ্ট্য নথিভুক্ত নয় | Python অ্যাডঅন এবং কমান্ড-লাইন অটোমেশন | নিয়ম-ভিত্তিক অটোমেশন প্লাস পাবলিক সোর্স এবং প্রক্সি লাইব্রেরি | নিয়ম-ভিত্তিক অটোমেশন; কোন প্রথম পক্ষের সাধারণ স্ক্রিপ্টিং বৈশিষ্ট্য নথিভুক্ত নয় |
| **আপস্ট্রিম রাউটিং** | [HTTP/HTTPS আপস্ট্রিম প্রক্সি এবং PAC URL রাউটিং](docs/features/upstream-proxy.mdx); সম্প্রদায় নীতি প্রক্সি প্রমাণীকরণ নিষ্ক্রিয় করে এবং SOCKS5 এবং বাইপাস নিয়ম তিনটিতে ক্যাপ করে | বাইপাস নিয়ম সহ এক্সটার্নাল HTTP/HTTPS/SOCKS এবং PAC রাউটিং | বহিরাগত HTTP/HTTPS/SOCKS প্রমাণীকরণ এবং বাইপাস নিয়ম সহ প্রক্সি | HTTP/HTTPS আপস্ট্রিম মোড প্লাস বিপরীত এবং SOCKS শ্রোতা মোড | সিস্টেম, HTTP, HTTPS, এবং SOCKS আপস্ট্রিম সেটিংস; পরিকল্পনা সীমা প্রযোজ্য হতে পারে | সিস্টেম প্রক্সিতে স্বয়ংক্রিয় চেইনিং প্লাস রিভার্স-প্রক্সি ক্যাপচার |
| **AI এবং MCP** | [ইন-অ্যাপ AI Assistant](docs/features/ai-assistant.mdx) এবং [বিল্ট-ইন স্থানীয় MCP](docs/features/mcp.mdx): ১০টি read-only tool, token authentication এবং default redaction | বহিরাগত AI client-এর জন্য built-in MCP, যার মধ্যে traffic read ও app/rule control রয়েছে | নথিভুক্ত নয় | নথিভুক্ত নয় | বর্তমান official source-এ bundled local MCP bridge রয়েছে; কোনো in-app assistant নথিভুক্ত নয় | built-in MCP এবং Pro-tier Debugging Assistant; বর্তমান documentation অনুযায়ী captured traffic-এর details chat-এ paste করতে হয় |

### সংলগ্ন ইন্টারসেপশন টুল

এই পণ্যগুলি Rockxy এর সাথে অর্থপূর্ণভাবে ওভারল্যাপ করে কিন্তু নিরাপত্তা পরীক্ষার সাথে নেতৃত্ব দেয়,
ব্রাউজারের নিয়ম, বা একই সাধারণ উদ্দেশ্যের পরিবর্তে API-ক্লায়েন্ট ওয়ার্কফ্লো
নেটিভ ডিবাগিং-প্রক্সি ফোকাস।

| **পণ্য** | **কেন এটা সংলগ্ন** | **উৎস এবং বিল্ড মডেল** | **প্রাসঙ্গিক ওভারল্যাপ** | **AI এবং MCP** |
|---|---|---|---|---|
| **Burp Suite** | একটি ইন্টারসেপ্টিং প্রক্সি সহ ওয়েব-সিকিউরিটি টেস্টিং স্যুট | ক্লোজড সোর্স অ্যাপ্লিকেশন; এর EULA বলে যে ব্যবহারকারীদের অ্যাপ্লিকেশন উত্সের কোন অধিকার নেই৷ এক্সটেনশনগুলি পৃথক লাইসেন্স ব্যবহার করতে পারে | প্রক্সি ইন্টারসেপশন এবং ম্যাচ/প্রতিস্থাপন, রিপিটার, WebSockets, আপস্ট্রিম/SOCKS প্রক্সিিং, এবং একটি বড় এক্সটেনশন ইকোসিস্টেম | Burp AI রিপিটারে পাওয়া যায়; PortSwigger বহিরাগত AI ক্লায়েন্টদের জন্য একটি সর্বজনীন MCP সার্ভার এক্সটেনশনও বজায় রাখে |
| **ZAP** | নিরাপত্তা স্ক্যানার এবং ইন্টারসেপ্টিং প্রক্সি | সর্বজনীন Apache-2.0 উৎস; উৎস থেকে নির্মাণযোগ্য | ইন্টারসেপ্ট/সম্পাদনা, ম্যানুয়াল রিসেন্ড, WebSocket ব্রেকপয়েন্ট এবং স্ক্রিপ্ট, বহু-ভাষা স্ক্রিপ্টিং, অ্যাড-অন, এবং অটোমেশন | অফিসিয়াল MCP ইন্টিগ্রেশন এবং ঐচ্ছিক LLM সমর্থন অ্যাড-অন |
| **Requestly HTTP Interceptor** | ব্রাউজার-এক্সটেনশন এবং ক্রস-প্ল্যাটফর্ম ডেস্কটপ ইন্টারসেপ্টর/মক টুল | সর্বজনীন AGPL ডেস্কটপ-ইন্টারসেপ্টর উৎস; পৃথক অনুরোধ API ক্লায়েন্ট তার পাবলিক কমিউনিটি-রিপোজিটরি নোটিশ অনুযায়ী মালিকানাধীন | সিস্টেম-ওয়াইড/ব্রাউজার ক্যাপচার, রিডাইরেক্ট, Map Local/Remote, হেডার/বডি পরিবর্তন, JavaScript রূপান্তর, উপহাস, এবং বিলম্ব/ত্রুটি সিমুলেশন | একটি পৃথক অফিসিয়াল MCP সার্ভার নিয়ম এবং গ্রুপ পরিচালনা করে; কোনো ইন-অ্যাপ ট্রাফিক-বিশ্লেষণ সহকারী নথিভুক্ত নয় |

বৈশিষ্ট্যের প্রাপ্যতা সংস্করণ, পরিকল্পনা, প্ল্যাটফর্ম বা অ্যাড-অন অনুসারে পরিবর্তিত হতে পারে।
"নথিভুক্ত নয়" এর মানে হল যে একটি ক্ষমতা অফিসিয়াল প্রথম পক্ষের মধ্যে পাওয়া যায়নি
2026-08-22 উপর পর্যালোচনা করা উৎস; এটা প্রমাণ নয় যে ক্ষমতা অনুপস্থিত।
উপরে পণ্য এবং বৈশিষ্ট্য বিবৃতি বিক্রেতা ডকুমেন্টেশনের বিরুদ্ধে পরীক্ষা করা হয়েছে,
বিক্রেতা-রক্ষণাবেক্ষণ করা উৎস সংগ্রহস্থল, বা সেই তারিখে বিক্রেতার লাইসেন্সের শর্তাবলী এবং
পরিবর্তন হতে পারে পণ্যের নাম এবং ট্রেডমার্ক তাদের নিজ নিজ মালিকদের অন্তর্গত;
Rockxy তাদের সাথে অনুমোদিত বা তাদের দ্বারা অনুমোদিত নয়৷ সংশোধন স্বাগত জানাই
Rockxy ইস্যু ট্র্যাকারের মাধ্যমে।

রোডম্যাপে: গভীর প্রোটোকল-সচেতন নিয়ম, নিরাপদ সংশোধন করা প্রমাণ বান্ডিল, শক্তিশালী রিপ্লে এবং তুলনামূলক কর্মপ্রবাহ, বিস্তৃত বিকাশকারী সেটআপ নির্দেশিকা এবং অব্যাহত HTTP/2 এবং HTTP/3 গবেষণা।

## নিরাপত্তা

Rockxy নেটওয়ার্ক ট্র্যাফিক বাধা দেয় — নিরাপত্তা মৌলিক, ঐচ্ছিক নয়।

- XPC সাহায্যকারীর মাধ্যমে কলকারীদের যাচাই করে **শংসাপত্র-চেইন তুলনা**, শুধু বান্ডিল আইডি নয়
- প্লাগইন চালু হয় **স্যান্ডবক্সযুক্ত জাভাস্ক্রিপ্টকোর** 5-সেকেন্ড টাইমআউট সহ, কোনো ফাইল সিস্টেম/নেটওয়ার্ক অ্যাক্সেস নেই
- **ইনপুট বৈধতা** সমস্ত সীমানায় — শরীরের আকারের ক্যাপ, URI সীমা, regex DoS সুরক্ষা, পাথ ট্রাভার্সাল প্রতিরোধ
- শংসাপত্র **স্বয়ংক্রিয়ভাবে সংশোধন করা হয়েছে** বন্দী লগ ইন
- সংবেদনশীল ফাইল সংরক্ষিত **0o600 অনুমতি**

মাধ্যমে দুর্বলতা রিপোর্ট করুন [SECURITY.md](SECURITY.md). দেখুন [সম্পূর্ণ নিরাপত্তা আর্কিটেকচার](docs/development/security.mdx) বিস্তারিত জানার জন্য

## রোডম্যাপ

Rockxy এর পাবলিক রোডম্যাপ ওয়ার্কফ্লো-ভিত্তিক এবং তারিখ-মুক্ত। এটি নির্ভরযোগ্যতা, নেটিভ macOS UX, ডিবাগিং ওয়ার্কফ্লো, প্রোটোকল সমর্থন, AI/Web3-era ট্র্যাফিক দৃশ্যমানতা, ডকুমেন্টেশন এবং অবদানকারী অনবোর্ডিং এর উপর ফোকাস করে।

- [ROADMAP.md](ROADMAP.md): উচ্চ-স্তরের পাবলিক ইঞ্জিনিয়ারিং দিকনির্দেশ
- [রকক্সি পাবলিক রোডম্যাপ](https://github.com/orgs/RockxyApp/projects/1): রোডম্যাপ-ট্র্যাক করা সমস্যাগুলির জন্য কার্যক্ষম দৃশ্যমানতা

## ডকুমেন্টেশন

সম্পূর্ণ ডকুমেন্টেশন উপলব্ধ [রকক্সি ডক্স](docs/index.mdx):

- [কুইকস্টার্ট গাইড](docs/quickstart.mdx) - কয়েক মিনিটের মধ্যে উঠুন এবং দৌড়ান
- [বিকাশকারী সেটআপ হাব](docs/features/developer-setup-hub.mdx) — রানটাইম স্নিপেট, ডিভাইস গাইড, যাচাইকরণ প্রোব, এবং সমর্থন ম্যাট্রিক্স
- [AI Assistant](docs/features/ai-assistant.mdx) — local analysis বা Review Data-র পর configured model দিয়ে নির্বাচিত traffic তদন্ত করুন
- [ফিল্টার ও অনুসন্ধান](docs/core-features/filters-and-search.mdx) — sidebar scope, Focus Sets, Noise Control, toolbar filter ও search
- [AI ও Web3 পরিদর্শন](docs/features/ai-web3-inspection.mdx) — স্বীকৃত model API, JSON-RPC ও x402 traffic inspect করুন
- [MCP ইন্টিগ্রেশন](docs/features/mcp.mdx) — স্থানীয় MCP ক্লায়েন্টদের সাথে Rockxy সংযোগ করুন
- [স্থাপত্য](docs/development/architecture.mdx) — প্রক্সি ইঞ্জিন, অভিনেতা মডেল, ডেটা প্রবাহ
- [নিরাপত্তা মডেল](docs/development/security.mdx) — বিশ্বাসের সীমানা, XPC বৈধতা, শংসাপত্র ব্যবস্থাপনা
- [নকশা সিদ্ধান্ত](docs/development/design-decisions.mdx) — কেন SwiftNIO, NSTableView, অভিনেতা
- [উৎস থেকে বিল্ডিং](docs/development/building.mdx) — বিল্ড, টেস্ট, লিন্ট এবং ডিবাগ
- [কোড স্টাইল](docs/development/code-style.mdx) — সুইফ্টলিন্ট, সুইফটফরম্যাট এবং নিয়মাবলী
- [চেঞ্জলগ](CHANGELOG.md) — অপ্রকাশিত কাজ এবং ট্যাগ করা রিলিজ

## অবদান

অবদান স্বাগত জানাই — কোড, পরীক্ষা, ডক্স, বাগ রিপোর্ট, এবং UX প্রতিক্রিয়া।

দেখুন **[CONTRIBUTING.md](CONTRIBUTING.md)** সেটআপ নির্দেশাবলী, কোড শৈলী এবং সম্পূর্ণ PR চেকলিস্টের জন্য।

ভাল প্রথম সমস্যা লেবেল করা হয় [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). একটি PR খোলার দ্বারা, আপনি সম্মত হন [সিএলএ](CLA.md).

## স্পনসর এবং অংশীদার

Rockxy স্বাধীনভাবে রক্ষণাবেক্ষণ করা হয়। স্পনসরশিপ অব্যাহত উন্নয়ন, রিলিজ অবকাঠামো, ডকুমেন্টেশন এবং নিরাপত্তা কাজের অর্থায়নে সহায়তা করে।

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy আর্থিকভাবে [Open Source Collective](https://docs.oscollective.org/) দ্বারা হোস্ট করা হয়। অবদান এবং প্রকল্পের ব্যয় [Rockxy-এর সর্বজনীন Open Collective পৃষ্ঠায়](https://opencollective.com/rockxy) নথিভুক্ত থাকে, যাতে সমর্থকেরা তহবিল গ্রহণ ও ব্যবহারের স্বচ্ছ চিত্র দেখতে পারেন।

| স্তর | অবদান | যা সমর্থন করে |
|------|--------|----------------|
| **Backer** | মাসে $5 থেকে | ওপেন-সোর্স রক্ষণাবেক্ষণ, ডকুমেন্টেশন, পরীক্ষা এবং রিলিজ |
| **Builder** | মাসে $25 থেকে | রিগ্রেশন টেস্টিং, পারফরম্যান্স উন্নতি এবং দৈনন্দিন ডিবাগিং ওয়ার্কফ্লো |
| **Sponsor** | মাসে $100 | ডেভেলপারদের জন্য বিনামূল্যে থাকা গোপনীয়তা-কেন্দ্রিক টুলের দীর্ঘমেয়াদি রক্ষণাবেক্ষণ |
| **Sustaining Sponsor** | মাসে $500 | রিলিজ অটোমেশন ও প্রোটোকল সমর্থনসহ কেন্দ্রীভূত রক্ষণাবেক্ষণ এবং পণ্য উন্নয়ন |

**অংশীদারিত্ব অনুসন্ধান** — ডেভেলপার টুল কোম্পানি, নিরাপত্তা সংস্থা, এবং এন্টারপ্রাইজ দলগুলি কাস্টম ইন্টিগ্রেশন বা হোয়াইট-লেবেল সমাধান খুঁজছে: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## সমর্থন

- [Open Collective](https://opencollective.com/rockxy/donate) — স্বচ্ছ প্রকল্প বাজেটের মাধ্যমে Rockxy-তে অবদান রাখুন
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — Rockxy এর উন্নয়ন সমর্থন করুন
- [গিটহাব সমস্যা](https://github.com/RockxyApp/Rockxy/issues) — বাগ রিপোর্ট এবং বৈশিষ্ট্য অনুরোধ
- [GitHub আলোচনা](https://github.com/RockxyApp/Rockxy/discussions) — প্রশ্ন এবং সম্প্রদায় চ্যাট
- **ইমেইল** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **নিরাপত্তা সমস্যা** — দেখুন [SECURITY.md](SECURITY.md) দায়িত্বশীল প্রকাশের জন্য

## লাইসেন্স

[GNU Affero জেনারেল পাবলিক লাইসেন্স v3.0](LICENSE) — কপিরাইট 2024–2026 Rockxy Contributors.

## তারকা ইতিহাস

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>দ্বারা তৈরি <a href="https://github.com/LocNguyenHuu">Stephen</a>. Swift, SwiftNIO, SwiftUI, এবং AppKit দিয়ে তৈরি।</sub>
</p>
