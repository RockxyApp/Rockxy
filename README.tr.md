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
  <strong>MacOS için açık kaynaklı, denetlenebilir hata ayıklama proxy'si.</strong>
</p>

<p align="center">
  Denetleyebileceğiniz, oluşturabileceğiniz ve güvenebileceğiniz yerel bir Swift uygulamasıyla HTTP/HTTPS/WebSocket/GraphQL trafiğini engelleyin, inceleyin ve değiştirin.<br>
  Rockxy geliştikçe API, mobil, MCP destekli, yapay zeka ve blockchain çağı hata ayıklama iş akışları için tasarlandı.<br>
  <a href="#rockxy-ve-alternatifler">Proxyman ve Charles Proxy</a>'ye yerel öncelikli, AGPL-3.0 bir alternatif.
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

## Güncel Şubenin Öne Çıkan Noktaları

- AI Assistant artık seçilen bir veya daha fazla request'i yerleşik yerel analiz veya isteğe bağlı yapılandırılmış Ollama/provider model ile inceler; açık Review Data onayı, sınırlı redaction, streaming yanıtlar, evidence reveal ve kullanıcı tarafından başlatılan handoff sunar.
- Yerel sidebar artık app/domain/path scope için yeniden kullanılabilir Focus Sets ile capture'ı durdurmadan eşleşen domain veya path'leri gizleyen workspace kapsamlı Noise Control içerir.
- Ana workspace artık Context Dock ve alt inspector için yerel dikey ve yatay split view kullanır; tam yükseklikte ayırıcıları, uyumlu toolbar/footer separator'larını ve otomatik düzen yeniden boyutlandırmayı korur.
- Upstream Proxy artık PAC URL yönlendirmeli ücretsiz/çekirdek Otomatik Proxy Yapılandırmasını içeriyor `DIRECT` Mevcut SOCKS5 ve kimlik doğrulama ilkesi sınırlarını korurken , HTTP ve HTTPS yönlendirmelerini destekler.
- Dışa aktarma iş akışları artık OpenAPI YAML/HTML'yi ve redaksiyona duyarlı yük oluşturma özelliğiyle seçili trafik Gist yayınlamayı kapsıyor.
- Denetçi araçları artık JSONPath/anahtar/değer filtrelemeyi ve JWT'ler gibi seçilen yük metni için hızlı önizlemeleri içeriyor.
- AI ve Web3 trafik incelemesi artık tanınan model çağrıları, JSON-RPC trafiği ve x402 tarzı ödeme ipuçları için protokol etiketleri, inspector sekmeleri ve hata ayıklama özetleri ekliyor.
- Node.js Geliştirici Kurulumu artık doğrulama sırasında seçilen istemciyi yansıtıyor ve daha kapsamlı bir localhost örnek kılavuzuna sahip.
- Geliştirici Kurulum Merkezi artık hedefe özel snippet'ler, doğrulama izleyicileri ve dürüst kılavuz içeriğiyle çalışma zamanlarını, tarayıcıları, istemcileri, cihazları, çerçeveleri ve ortamları kapsıyor.
- WebSocket binary-frame inspection artık capture hot path'e decoder work eklemeden sınırlı, on-demand Protobuf wire-format heuristic sunuyor.
- Public roadmap artık daha derin protocol-aware rules, replay, comparison ve daha güvenli redacted evidence sharing'e odaklanıyor.

## Özellikler

Tarayıcı DevTools'un yeterli olmadığı durumlarda ulaşacağınız araçlar. Mac ve iOS için temel trafik hata ayıklaması; genel yayınlar ve yerel öncelikli iş akışıyla macOS'ta yerel olarak çalışır.

### Trafik Yakalama

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Herhangi bir Mac uygulamasından, CLI'den veya iOS cihazından HTTP, HTTPS, WebSocket ve GraphQL trafiğini inceleyin. Tarayıcı DevTools'u tarayıcıda biter; Rockxy yığınınızın geri kalanını görür.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Gelişmiş Filtre ve Arama

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

Yakalanan binlerce isteği saniyeler içinde daraltın. Yöntem, ana bilgisayar, durum, başlık, gövde ve süreç filtrelerini birleştirin veya tüm oturum boyunca tam metin araması yapın.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets ve Noise Control

Tekrarlanan incelemeleri sidebar içinde yeniden kullanılabilir scope'lara dönüştürün. Focus Sets app, domain ve path include'larını domain/path exclude'larıyla birleştirir, açılışlar arasında kalır ve her workspace'te kullanılabilir. Noise Control telemetriyi ve düşük değerli trafiği capture etmeye devam eder, ancak mevcut workspace'te gizler.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant native request tablosu ve sidebar yanında seçili trafiği açıklıyor" width="820" />

Bir veya daha fazla capture edilmiş request seçin ve ne olduğunu, neyin başarısız olduğunu, neyin değiştiğini veya sırada neyin doğrulanacağını sorun. Rockxy önce bu Mac'te kanıta dayalı analiz yapar; yapılandırılmış Ollama veya provider model yalnızca Review Data kesin, sınırlı ve redacted context'i gösterdikten sonra çalışır. Yanıtlar source request'i reveal edip native follow-up workflow hazırlayabilir, ancak trafiği değiştirmez veya action'ları otomatik çalıştırmaz.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[AI Assistant rehberini okuyun](docs/features/ai-assistant.mdx).

### Harici AI istemcileri için MCP Sunucusu

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Claude Desktop veya Cursor'un yakalanan trafiğinizi Rockxy'nin yerel MCP sunucusundaki on salt okunur araçla incelemesine izin verin. Başlıkları sohbete yapıştırmak yerine "Bunu neden 500 yaptı?" diye sorun. Uygulama açık kaynaktır, token ile kimlik doğrular ve hassas veri redaction'ını varsayılan olarak açık tutar.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Geliştirici Kurulum Merkezi

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Python, Node.js, Go, Rust, cURL, Docker ve tarayıcılar için proxy parçacıklarını kopyalayıp yapıştırın ve ardından trafiğin gerçekten aktığını doğrulamak için Testi Çalıştır'a tıklayın.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### HTTPS Hata Ayıklama için Sertifika Yönetimi

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

İlk başlatmada oluşturulan ve Anahtar Zincirinizde mühürlenen bir P-256 ECDSA kök CA'sı. İlk denemede HTTPS'nin şifresini çözün; sabitlenmiş ana bilgisayarlar otomatik olarak geçer.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL Proxy ve HTTPS Şifre Çözme

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Hangi ana bilgisayarların TLS şifre çözme alacağını seçin. Şifresi çözülmüş trafik, gerçek başlıkları ve JSON'u gösterir; geri kalan her şey şifrelenmiş olarak geçer. Joker karakter kuralları, tek tıklamayla etki alanına göre kapsam belirlemenize olanak tanır.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Proxy'yi Atla

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Sertifikayla sabitlenmiş uygulamaların, dahili hizmetlerin veya gürültülü telemetrinin hiçbir zaman yakalamaya girmemesi için belirli ana bilgisayarları atlayın. Joker karakterler listeyi kısa tutar ve istek günlüğünüz gerçekten önemsediğiniz şeye odaklanır.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Engellenenler Listesi

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Herhangi bir ana bilgisayarın başarısız olmasına neden olun. Tek bir kod satırını bile değiştirmeden, uygulamanız bittiğinde nasıl kötüleştiğini görmek için reklam ağlarını, üçüncü taraf izleyicileri veya düzensiz bir bağımlılığı bırakın.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Yerel Harita

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Canlı yanıt yerine kayıtlı bir dosyayı veya dizin ağacını sunun. Hata ayıklarken bir JSON verisini değiştirin, bir anlık görüntüyü yeniden oynatın veya hatalı bir üçüncü taraf API'yi yerel bir kopyaya sabitleyin.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Uzaktan Harita

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Yakalanan bir isteğin hedefini, uygulama koduna veya /etc/hosts dosyasına dokunmadan yeniden yazın. Tekrarlanabilir bir hata çoğaltması için üretim trafiğini aşamalandırmaya, geliştirme sunucunuza veya bir iş arkadaşınızın makinesine yönlendirin.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Kesme Noktaları ve Kurallar

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Bir isteği veya yanıtı duraklatın, yöntemi, başlıkları, gövdeyi veya durumu düzenleyin ve ardından devam edin. "Ya API 401 döndürürse?" testini yapmanın en hızlı yolu arka uca dokunmadan.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Başlıkları Değiştir

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Yeniden konuşlandırmaya gerek kalmadan herhangi bir ana makinedeki başlıkları ekleyin, kaldırın veya değiştirin. Yerleşik ön ayarlarla CORS, kimlik doğrulama veya önbellek değişikliklerini saniyeler içinde test edin.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Özel İstek ve Yanıt Başlıkları

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Herhangi bir istek veya yanıt başlığını trafik tablosunda birinci sınıf bir sütuna yükseltin. İstek ve yanıt kaynaklarını ayrı tutun, önemsediğiniz başlıkları kaydedin, ardından her inspector'ı açmadan request ID'leri, trace ID'leri, önbellek durumunu veya özel meta verileri tarayın.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Ağ Koşulları

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

3G, EDGE, LTE, WiFi veya özel bir gecikmeye geçin. Dizüstü bilgisayarınız fiber üzerindedir; kullanıcılarınız öyle değil; UX'i onlardan önce 400 ms RTT'de görün.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Oluştur – Düzenle ve Tekrar Oynat

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Yakalanan herhangi bir HTTP isteğini yeniden oluşturun (yöntemi, URL'yi, başlıkları, sorgu parametrelerini veya gövdeyi değiştirin) ve Rockxy'den ayrılmadan yeniden gönderin. Postman, Insomnia veya curl kopyala-yapıştır döngüsü yok. LLM istemlerini yineleyin, kimlik doğrulama sınırlarını fuzz'layın veya OpenAI, Anthropic ve Cohere uç noktaları için saniyeler içinde başarısız bir durumu yeniden oluşturun.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Karşılaştır

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Yakalanan iki transaction'ı veya yapıştırılan payload'ı yan yana yığın ve değişen her alanı (durum, başlıklar, JSON anahtarları veya gövde baytları) tespit edin. Üçüncü taraf bir fark aracına hiçbir şey aktarmadan sessiz API regresyonlarını, deterministik olmayan LLM çıktılarını ve prompt drift'i yakalayın.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Özel Önizleyici Sekmeleri

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

İstek ve yanıt gövdelerini istediğiniz şekilde işleyin. JSON, GraphQL, JWT, görsel veya kendi formatınız için denetçiye ekstra sekmeler sabitleyin; yakalanan her istekte yeniden kullanılabilir.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Oturumlar ve Dışa Aktarma

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Oturumları kaydedin, araçlar arası geçiş için HAR'ı içe/dışa aktarın, herhangi bir isteği cURL veya JSON olarak kopyalayın. Paylaşmadan önce yetkilendirme başlıklarını, çerezleri ve taşıyıcı belirteçlerini düzenleyin; sırları sızdırmadan bir ekip arkadaşınıza çalışan bir hata kopyası verin.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Çok Sekmeli Çalışma Alanları

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Aynı live capture'ın bağımsız filtrelenmiş görünümlerini gösteren Rockxy çok sekmeli çalışma alanları" width="820" />

Aynı live capture'a ait bağımsız inceleme görünümlerini yan yana tutun — bir sekme staging trafiği, biri production, biri iOS cihaz akışı için. Her sekme kendi filtrelerini, sıralamasını, seçimini, sidebar scope'unu ve inspector durumunu korurken proxy ve yakalanan transaction'ları paylaşır.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript Komut Dosyası Oluşturma

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS, statik bir kuralın kapsayamayacağı durumlar için istek ve yanıtlara bağlanır; PII'yi düzenleyin, belirteçleri imzalayın, yükleri yeniden yazın. Hatalar trafiği bozmak yerine satır içi olarak ortaya çıkar.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Protokole Duyarlı İnceleme

Rockxy normal HTTP debugging workflow içinde AI, Web3 RPC ve x402 için protocol-aware inspection sunar.

### Yapay Zeka Trafik Denetimi

Rockxy normal yakalama iş akışı içinde tanınan AI isteklerini algılar. Seçilen model çağrılarını, streaming durumunu, mevcut olduğunda usage alanlarını, uyarıları, retrieval hint'lerini ve tool-call özetlerini hassas payload'ları başka bir hizmete yapıştırmadan inceleyin.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC Denetimi

Rockxy blockchain çağındaki ağ çağrılarını okunabilir hata ayıklama kanıtına dönüştürür. EVM ve Solana tarzı HTTP JSON-RPC trafiğini provider host, request ID, method, batch summary, error, chain, transaction, payload ve debug-intent detayıyla inceleyin; Rockxy'yi bir cüzdana veya blok gezginine dönüştürmeden.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 Ödeme Akışı İpuçları

Rockxy, payment-required ve retry odaklı ipuçlarını vurgular; böylece payment-gated HTTP akışları ağ katmanından anlaşılır olurken hata ayıklama kanıtı yerel ve redaction-aware kalır.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Gelecekteki Çalışmalar

Aşağıdaki bölümler mevcut davranışı değil, kamuya açık yönü açıklar.

### Protokole Duyarlı Kurallar

Rockxy bugün AI ve Web3 trafiğini etiketleyip inceleyebilir. Model, tool call, JSON-RPC method, chain, transaction hash veya batch subcall'a göre daha derin kural eşleştirme gelecekteki bir çalışmadır; mevcut trafik değiştirme araçları hâlâ URL, HTTP method ve header ile eşleşir.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Düzeltilmiş Kanıt Paketleri `Yakında`

Sırları sızdırmadan bir hatayı yeniden oluşturmak için gereken gerçekleri paylaşın. Seçilen trafiği protokol özetleri, redaksiyon önizlemeleri ve bir ekip arkadaşının denetleyebileceği kaynak destekli bağlamla paketleyin.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Ekip Paylaşımı ve İşbirliği `Yakında`

Yakalanan bir oturumu tek tıklamayla bir ekip arkadaşınıza gönderin. Başarısız isteklere satır içi açıklama ekleyin, gerçek zamanlı olarak kimin neye baktığını görün ve ekran paylaşımına gerek kalmadan HTTPS trafiğinde çift hata ayıklama yapın. Gelecekteki bir sürüm için hedeflendi.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Yerel macOS uygulama kabuğu — Electron yok. SwiftUI + AppKit + SwiftNIO, WebKit yalnızca HTML gövde önizlemesi için kullanılır.

## Hızlı Başlangıç

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Xcode'da oluşturun ve çalıştırın. Hoş Geldiniz penceresi kök CA kurulumu, yardımcı kurulumu ve proxy aktivasyonu boyunca size yol gösterir.

**Gereksinimler:** macOS 14.0+, Xcode 16+, Swift 5.9

Rockxy'yi kurulumdan sonra yerel bir MCP istemcisine bağlamak istiyorsanız, bkz. [MCP Entegrasyon kılavuzu](docs/features/mcp.mdx).

## Rockxy ve Alternatifler

Ana matris, genel amaçlı web hata ayıklama proxy'lerini kapsar. Güvenlik testi
önemli iş akışı örtüşmesine sahip paketler ve tarayıcı/API odaklı önleyiciler
Birbirinden farklı ürünler birbirinin yerine kullanılabilir şekilde sunulmadığından ayrı ayrı listelenir.
Paket analizörleri ve yalnızca API istemcileri bu karşılaştırmanın dışındadır.

### Doğrudan web hata ayıklama proxy'leri

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Ürün şekli** | Yerel macOS hata ayıklama proxy'si | Yerel macOS uygulaması; Electron tabanlı Windows/Linux sürümleri | Platformlar arası masaüstü hata ayıklama proxy'si | Platformlar arası CLI/TUI ve web kullanıcı arayüzü proxy araç seti | Platformlar arası Electron masaüstü proxy ve HTTP istemcisi | Platformlar arası masaüstü hata ayıklama proxy'si |
| **Kaynak ve derleme modeli** | AGPL-3.0-or-later kapsamındaki Kamu Topluluğu kaynağı; Xcode ile oluşturulabilir. Resmi DMG ayrıca halka açık olmayan alt bileşenler de içerir | Kapalı kaynak; incelenen resmi materyallerde kamuya açık başvuru kaynağı belirtilmedi | Kapalı kaynak; incelenen resmi materyallerde kamuya açık başvuru kaynağı belirtilmedi | Herkese açık MIT lisanslı kaynak; kaynaktan üretilebilir | Genel AGPL masaüstü kaynağı; kaynaktan üretilebilir; yayınlanan ikili dosyalar ek lisanslama seçeneklerine sahiptir | Kapalı kaynak; Fiddler Everywhere EULA altında nesne kodu olarak dağıtılır |
| **Yakalama ve kurulum** | Mac uygulamaları, çalışma zamanları, iOS aygıtları ve Simülatör için yönlendirmeli kuruluma sahip yerel sistem proxy'si | Mac uygulamaları, çalışma zamanları ve mobil cihazlar için otomatik kurulum | MacOS, iOS ve platformlar arası kurulum kılavuzlarıyla yerel proxy | Normal, yerel süreç, WireGuard, ters, şeffaf ve diğer yakalama modları | Tarayıcılar, çalışma zamanları, kapsayıcılar ve mobil cihazlar için hedefli ve manuel proxy müdahalesi | Sistem, ağ, tarayıcı, terminal, açık ve uzak cihaz yakalama modları |
| **Değiştirin ve taklit edin** | Kesme noktaları, Map Local/Remote, başlık kuralları, engelleme ve gecikme kuralları | Kesme noktaları, Map Local/Remote, engelleme listeleri, ağ koşulları ve JavaScript kuralları | Kesme noktaları, Yeniden Yazma, Map Local/Remote, engelleme ve azaltma | Map Local/Remote, gövde/başlık değişikliği, engelleme ve sunucunun yeniden oynatılması | Kesme noktalarının yanı sıra kural tabanlı yeniden yazma, yönlendirme, taklit ve hata ekleme; bazı otomasyonlar planla sınırlıdır | Kurallar, kesme noktaları, yönlendirmeler, yanıt değişikliği ve taklit |
| **Tekrar oynatın ve karşılaştırın** | Oluşturma/tekrar oynatmanın yanı sıra yerel yan yana istek, başlık ve gövde karşılaştırması | Oluşturun, Tekrarlayın ve Fark Edin | İstekleri tekrarlayın ve düzenleyin | İstemci tarafı ve sunucu tarafı tekrarı | İstek oluşturmak ve göndermek için yerleşik HTTP istemcisi | API Oluşturucu, trafiğin tekrar oynatılması ve trafik karşılaştırması beta olarak belgelendi |
| **WebSocket iş akışları** | Sınırlı Protobuf buluşsal yöntemle metin/ikili çerçeve incelemesi | WS/WSS denetimi; komut dosyaları, mesajları değil, el sıkışma URL'sini/başlıklarını değiştirebilir | WebSocket desteği resmi sürüm geçmişinde belgelenmiştir | WebSocket müdahale ve komut dosyası oluşturma; WebSocket tekrar oynatma desteklenmiyor | WebSocket denetimi artı WebSocket'ye özgü kurallar | WebSocket yakalama ve inceleme |
| **Komut dosyası oluşturma ve genişletilebilirlik** | Sınırlı API ve yürütme zaman aşımına sahip korumalı alan JavaScriptCore kancaları | JavaScript istek/yanıt komut dosyası oluşturma | Kuralları yeniden yazma ve bir kontrol Web Arayüzü; genel JavaScript komut dosyası oluşturma özelliği belgelenmemiştir | Python eklentileri ve komut satırı otomasyonu | Kural tabanlı otomasyonun yanı sıra genel kaynak ve proxy kitaplıkları | Kural tabanlı otomasyon; birinci taraf genel komut dosyası oluşturma özelliği belgelenmemiştir |
| **Yukarı yönde yönlendirme** | [HTTP/HTTPS yukarı akış proxy'si ve PAC URL yönlendirmesi](docs/features/upstream-proxy.mdx); Topluluk ilkesi, proxy kimlik doğrulamasını ve SOCKS5'yi devre dışı bırakır ve atlama kurallarını üç | Baypas kurallarıyla harici HTTP/HTTPS/SOCKS ve PAC yönlendirme | Kimlik doğrulama ve atlama kurallarına sahip harici HTTP/HTTPS/SOCKS proxy'ler | HTTP/HTTPS yukarı akış modu artı ters ve SOCKS dinleyici modları | Sistem, HTTP, HTTPS ve SOCKS yukarı akış ayarları; plan sınırları geçerli olabilir | Sistem proxy'lerine otomatik zincirleme artı ters proxy yakalama |
| **AI ve MCP** | [Uygulama İçi Yapay Zeka Asistanı](docs/features/ai-assistant.mdx) ve [yerleşik yerel MCP](docs/features/mcp.mdx), 10 salt okunur araç, belirteç kimlik doğrulaması ve varsayılan olarak düzeltme açık | Trafik okumaları ve uygulama/kural kontrolleri de dahil olmak üzere harici AI istemcileri için yerleşik MCP | Belgelenmemiş | Belgelenmemiş | Mevcut resmi kaynakta paketlenmiş bir yerel MCP köprüsü mevcuttur; uygulama içi asistan belgelenmedi | Yerleşik MCP artı mevcut belgeleri, yakalanan trafik ayrıntılarının sohbete yapıştırılmasını gerektiren Profesyonel Düzeyde Hata Ayıklama Asistanı |

### Bitişik müdahale araçları

Bu ürünler Rockxy ile anlamlı bir şekilde örtüşmektedir ancak güvenlik testlerine öncülük etmektedir.
aynı genel amaçlı kullanım yerine tarayıcı kuralları veya API istemci iş akışları
yerel hata ayıklama-proxy odağı.

| **Ürün** | **Neden bitişiktir** | **Kaynak ve derleme modeli** | **İlgili örtüşme** | **AI ve MCP** |
|---|---|---|---|---|
| **Burp Suite** | Engelleyici proxy içeren web güvenliği test paketi | Kapalı kaynak uygulaması; EULA, kullanıcıların uygulama kaynağına erişim hakkına sahip olmadığını belirtir. Uzantılar ayrı lisanslar kullanabilir | Proxy müdahalesi ve eşleştirme/değiştirme, Tekrarlayıcı, WebSocket'ler, yukarı akış/SOCKS proxy oluşturma ve geniş bir uzantı ekosistemi | Burp AI Tekrarlayıcı'da mevcuttur; PortSwigger ayrıca harici AI istemcileri için genel bir MCP Sunucu uzantısına sahiptir |
| **ZAP** | Güvenlik tarayıcısı ve engelleyici proxy | Genel Apache-2.0 kaynağı; kaynaktan üretilebilir | Durdurma/düzenleme, manuel yeniden gönderme, WebSocket kesme noktaları ve komut dosyaları, çok dilli komut dosyası oluşturma, eklentiler ve otomasyon | Resmi MCP Entegrasyonu ve isteğe bağlı LLM Destek eklentileri |
| **Requestly HTTP Interceptor** | Tarayıcı uzantısı ve platformlar arası masaüstü önleyici/sahte aracı | Genel AGPL masaüstü önleyici kaynağı; ayrı İstek API İstemcisi, genel topluluk deposu bildirimine göre tescillidir | Sistem genelinde/tarayıcı yakalama, yönlendirme, Map Local/Remote, başlık/gövde değişikliği, JavaScript dönüşümleri, taklitler ve gecikme/hata simülasyonu | Ayrı bir resmi MCP sunucusu, kuralları ve grupları yönetir; uygulama içi trafik analizi asistanı belgelenmedi |

Özellik kullanılabilirliği sürüme, plana, platforma veya eklentiye göre değişebilir.
"Belgelenmemiş", resmi birinci taraf hizmetinde bir yeteneğin bulunmadığı anlamına gelir
2026-08-22'de incelenen kaynaklar; yeteneğin bulunmadığının kanıtı değildir.
Yukarıdaki ürün ve özellik bildirimleri satıcı belgelerine göre kontrol edildi,
satıcı tarafından tutulan kaynak depoları veya o tarihteki satıcı lisans koşulları ve
değişebilir. Ürün adları ve ticari markalar ilgili sahiplerine aittir;
Rockxy onlara bağlı değildir veya onlar tarafından desteklenmemektedir. Düzeltmeler memnuniyetle karşılanır
Rockxy sorun izleyici aracılığıyla.

Yol haritasında: protokole duyarlı daha derin kurallar, daha güvenli düzeltilmiş kanıt paketleri, daha güçlü tekrar ve karşılaştırma iş akışları, daha kapsamlı Geliştirici Kurulumu rehberliği ve devam eden HTTP/2 ve HTTP/3 araştırması.

## Güvenlik

Rockxy ağ trafiğini keser; güvenlik isteğe bağlı değil temeldir.

- XPC yardımcısı arayanları doğrular **sertifika zinciri karşılaştırması**, yalnızca paket kimliği değil
- Eklentiler çalıştırılıyor **korumalı alana alınmış JavaScriptCore** 5 saniyelik zaman aşımı ile, dosya sistemi/ağ erişimi yok
- **Giriş doğrulama** tüm sınırlarda — gövde boyutu sınırları, URI sınırları, regex DoS koruması, yol geçişini önleme
- Kimlik bilgileri **otomatik olarak düzenlendi** yakalanan günlüklerde
- ile saklanan hassas dosyalar **0o600 izinleri**

Güvenlik açıklarını şu yolla bildirin: [SECURITY.md](SECURITY.md). Bkz. [tam güvenlik mimarisi](docs/development/security.mdx) ayrıntılar için.

## Yol Haritası

Rockxy'nin halka açık yol haritası iş akışı odaklıdır ve tarih içermez. Güvenilirlik, yerel macOS UX, hata ayıklama iş akışları, protokol desteği, AI/Web3 dönemi trafik görünürlüğü, belgeler ve katkıda bulunanların katılımına odaklanır.

- [YOL HARİTASI.md](ROADMAP.md): üst düzey kamu mühendisliği yönü
- [Rockxy Kamu Yol Haritası](https://github.com/orgs/RockxyApp/projects/1): yol haritasıyla takip edilen sorunlar için operasyonel görünürlük

## Dokümantasyon

Tüm belgeler şu adreste mevcuttur: [Rockxy Dokümanları](docs/index.mdx):

- [Hızlı Başlangıç Kılavuzu](docs/quickstart.mdx) — birkaç dakika içinde ayağa kalkıp çalışmaya başlayın
- [Geliştirici Kurulum Merkezi](docs/features/developer-setup-hub.mdx) — çalışma zamanı parçacıkları, cihaz kılavuzları, doğrulama araştırmaları ve destek matrisi
- [AI Assistant](docs/features/ai-assistant.mdx) — seçili trafiği yerel analizle veya Review Data sonrası configured model ile inceleyin
- [Filtreler ve arama](docs/core-features/filters-and-search.mdx) — sidebar scope, Focus Sets, Noise Control, toolbar filter ve search
- [AI ve Web3 inceleme](docs/features/ai-web3-inspection.mdx) — tanınan model API, JSON-RPC ve x402 trafiğini inceleyin
- [MCP Entegrasyonu](docs/features/mcp.mdx) — Rockxy'yi yerel MCP istemcilerine bağlayın
- [Mimarlık](docs/development/architecture.mdx) — proxy motoru, aktör modeli, veri akışı
- [Güvenlik Modeli](docs/development/security.mdx) — güven sınırları, XPC doğrulaması, sertifika yönetimi
- [Tasarım Kararları](docs/development/design-decisions.mdx) — neden SwiftNIO, NSTableView, aktörler
- [Kaynaktan İnşa Etmek](docs/development/building.mdx) — derleme, test etme, tüy bırakma ve hata ayıklama
- [Kod Stili](docs/development/code-style.mdx) — SwiftLint, SwiftFormat ve kurallar
- [Değişiklik günlüğü](CHANGELOG.md) — yayınlanmamış çalışmalar ve etiketli yayınlar

## Katkıda Bulunmak

Katkılar memnuniyetle karşılanır - kod, testler, belgeler, hata raporları ve UX geri bildirimi.

Bkz. **[KATKIDA BULUNAN.md](CONTRIBUTING.md)** kurulum talimatları, kod stili ve tam PR kontrol listesi için.

İyi ilk sayılar etiketlenir [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Bir PR açarak şunları kabul etmiş olursunuz: [CLA](CLA.md).

## Sponsorlar ve Ortaklar

Rockxy bağımsız olarak sürdürülmektedir. Sponsorluklar sürekli geliştirmeyi, sürüm altyapısını, dokümantasyonu ve güvenlik çalışmalarını finanse etmeye yardımcı olur.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy, [Open Source Collective](https://docs.oscollective.org/) tarafından mali olarak barındırılır. Katkılar ve proje giderleri [Rockxy'nin herkese açık Open Collective sayfasında](https://opencollective.com/rockxy) kaydedilir; böylece destekçiler fonların nasıl alındığını ve kullanıldığını şeffaf biçimde görebilir.

| Seviye | Katkı | Neyi destekler |
|--------|-------|----------------|
| **Backer** | Aylık $5'ten başlayan | Açık kaynak bakımı, dokümantasyon, testler ve sürümler |
| **Builder** | Aylık $25'ten başlayan | Regresyon testleri, performans iyileştirmeleri ve günlük hata ayıklama iş akışları |
| **Sponsor** | Aylık $100 | Gizlilik odaklı ve geliştiricilere ücretsiz sunulan bir aracın uzun vadeli bakımı |
| **Sustaining Sponsor** | Aylık $500 | Sürüm otomasyonu ve protokol desteği dahil odaklı bakım ve ürün geliştirme |

**Ortaklık soruları** — özel entegrasyonlar veya beyaz etiket çözümleri arayan geliştirici aracı şirketleri, güvenlik firmaları ve kurumsal ekipler: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Destek

- [Open Collective](https://opencollective.com/rockxy/donate) — şeffaf proje bütçesi aracılığıyla Rockxy'ye katkıda bulunun
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — Rockxy'nin gelişimini desteklemek
- [GitHub Sorunları](https://github.com/RockxyApp/Rockxy/issues) — hata raporları ve özellik istekleri
- [GitHub Tartışmaları](https://github.com/RockxyApp/Rockxy/discussions) — sorular ve topluluk sohbeti
- **E-posta** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Güvenlik sorunları** — gör [SECURITY.md](SECURITY.md) Sorumlu açıklama için

## Lisans

[GNU Affero Genel Kamu Lisansı v3.0](LICENSE) — Telif Hakkı 2024–2026 Rockxy Katkıda Bulunanlar.

## Yıldız Tarihi

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Tarafından yapılmıştır <a href="https://github.com/LocNguyenHuu">Stephen</a>. Swift, SwiftNIO, SwiftUI ve AppKit ile oluşturulmuştur.</sub>
</p>
