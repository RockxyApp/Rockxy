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
  Yerel öncelikli AGPL-3.0 alternatifi <a href="#rockxy-vs-alternatives">Vekil ve Charles Vekil</a>.
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
## En Son Etiketlenen Sürüm

**v0.27.2** — 2026-06-18

### Değiştirildi

- Meta veri gizlilik kontrollerini geliştirin
- Meta veri açıklama düzenini hassaslaştırın

Bkz. [CHANGELOG.md](CHANGELOG.md) tam sürüm geçmişi için.
<!-- END GENERATED: latest-release -->

## Güncel Şubenin Öne Çıkan Noktaları

- Upstream Proxy artık PAC URL yönlendirmeli ücretsiz/çekirdek Otomatik Proxy Yapılandırmasını içeriyor `DIRECT` Mevcut SOCKS5 ve kimlik doğrulama ilkesi sınırlarını korurken , HTTP ve HTTPS yönlendirmelerini destekler.
- Dışa aktarma iş akışları artık OpenAPI YAML/HTML'yi ve redaksiyona duyarlı yük oluşturma özelliğiyle seçili trafik Gist yayınlamayı kapsıyor.
- Denetçi araçları artık JSONPath/anahtar/değer filtrelemeyi ve JWT'ler gibi seçilen yük metni için hızlı önizlemeleri içeriyor.
- Node.js Geliştirici Kurulumu artık doğrulama sırasında seçilen istemciyi yansıtıyor ve daha kapsamlı bir localhost örnek kılavuzuna sahip.
- Geliştirici Kurulum Merkezi artık hedefe özel snippet'ler, doğrulama izleyicileri ve dürüst kılavuz içeriğiyle çalışma zamanlarını, tarayıcıları, istemcileri, cihazları, çerçeveleri ve ortamları kapsıyor.
- WebSocket Protobuf çalışması, Rockxy'nin daha zengin protokol inceleme yönünün bir parçası olarak devam ediyor.
- Genel yol haritası planlaması artık yapay zeka trafiği için protokole duyarlı hata ayıklamayı, Web3/RPC akışlarını, x402 tarzı ödeme akışlarını ve daha güvenli, düzeltilmiş kanıt paylaşımını içeriyor.

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

### Yapay Zeka Asistanları için MCP Sunucusu

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Claude Desktop veya Cursor'un yakalanan trafiğinizi yerel bir MCP sunucusu üzerinden okumasına izin verin. "Bunu neden 500 yaptı?" diye sorun. başlıkları sohbete yapıştırmak yerine. Yerel, redaksiyona duyarlı ve açık kaynak.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Her iki aşama üzerinde de tam kontrole sahip olarak ana bilgisayar başına başlıkları geçersiz kılın. Giden isteklere kimlik doğrulama belirteçleri ekleyin, yanıtlardaki Set-Cookie'yi kaldırın veya özel bir Kullanıcı Aracısını sabitleyin; istediğiniz zaman değiştirebileceğiniz adlandırılmış kurallar olarak kaydedilir.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Ağ Koşulları

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

3G, EDGE, LTE, WiFi veya özel bir gecikmeye geçin. Dizüstü bilgisayarınız fiber üzerindedir; kullanıcılarınız öyle değil; UX'i onlardan önce 400 ms RTT'de görün.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Oluştur – Düzenle ve Tekrar Oynat

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Yakalanan herhangi bir HTTP isteğini yeniden oluşturun (yöntemi, URL'yi, başlıkları, sorgu parametrelerini veya gövdeyi değiştirin) ve Rockxy'den ayrılmadan yeniden gönderin. Postacı, Uykusuzluk veya kıvırma kopyala-yapıştır döngüsü yok. LLM istemlerini yineleyin, kimlik doğrulama sınırlarını kesin veya OpenAI, Anthropic ve Cohere uç noktaları için saniyeler içinde başarısız bir durumu yeniden oluşturun.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Karşılaştır

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Yakalanan iki yanıtı yan yana yığınlayın ve ters çevrilen her alanı (durum, başlıklar, JSON anahtarları, gövde baytları) tespit edin. Sessiz API regresyonlarını, deterministik olmayan LLM çıktılarını yakalayın ve üçüncü taraf bir fark aracına herhangi bir şey aktarmadan anında sapmayı yakalayın. Yan yana farklar nelerin değiştiğini vurguluyor; derin JSON karşılaştırması anahtar sıralamasını yok sayar.

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

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Rockxy multi-tab workspaces running independent capture sessions side-by-side" width="820" />

Bağımsız yakalama oturumlarını yan yana çalıştırın; hazırlama için bir sekme, ürün için bir sekme, iOS cihaz yapısı için bir sekme. Her sekmenin kendi filtreleri, seçimi ve denetçi durumu vardır; dolayısıyla içerik değiştirmenin hiçbir maliyeti yoktur.

`Independent Sessions` · `Per-Tab Filters` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript Komut Dosyası Oluşturma

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS, statik bir kuralın kapsayamayacağı durumlar için istek ve yanıtlara bağlanır; PII'yi düzenleyin, belirteçleri imzalayın, yükleri yeniden yazın. Hatalar trafiği bozmak yerine satır içi olarak ortaya çıkar.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Daha Fazla Özellik Yakında Gelecek

Gelecekteki özellikler herkese açık olarak takip edilir ve yalnızca uygulama, testler, gizlilik davranışı ve belgeler hazır olduğunda gönderilir.

### Yapay Zeka Trafik Denetimi `Yakında`

Normal yakalama iş akışında model trafiğinde hata ayıklamayı kolaylaştırın. Hassas verileri başka bir hizmete yapıştırmadan yapay zeka isteklerini tespit edin, seçilen model çağrılarını inceleyin, akış yanıtlarını teşhis edin, bilgi istemi/çıktı davranışını karşılaştırın ve araç çağrısı zincirlerini anlayın.

`AI Requests` · `Model Inspector` · `Streaming Diagnostics` · `Tool Calls` · `Prompt Safety` · `Usage Signals`

### Web3/RPC Denetimi `Yakında`

Blockchain çağındaki ağ çağrılarını okunabilir hata ayıklama kanıtlarına dönüştürün. JSON-RPC ve Solana RPC trafiğini inceleyin, ilgili çağrıları akışlar halinde gruplandırın, yaygın RPC hatalarını açıklayın ve bir cüzdan veya blok gezgini olmadan seçilen istekleri yeniden yürütün.

`JSON-RPC` · `Solana RPC` · `Wallet Flows` · `RPC Errors` · `Replay Helpers` · `Network Evidence`

### x402 Ödeme Akışı Hata Ayıklama `Yakında`

Ağ katmanından ödeme kapılı HTTP akışlarını anlayın. Ödemenin gerekli olduğu yanıtları vurgulayın, yeniden deneme yolunu izleyin ve hata ayıklama kanıtlarını yerel ve redaksiyona uygun halde tutun.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

### Düzeltilmiş Kanıt Paketleri `Yakında`

Sırları sızdırmadan bir hatayı yeniden oluşturmak için gereken gerçekleri paylaşın. Seçilen trafiği protokol özetleri, redaksiyon önizlemeleri ve bir ekip arkadaşının denetleyebileceği kaynak destekli bağlamla paketleyin.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Protokole Duyarlı Filtreler ve Kurallar `Yakında`

Rockxy'nin halihazırda çalıştığı yerlerde AI ve Web3 meta verilerini kullanın: filtreler, rozetler, isteğe bağlı sütunlar, karşılaştırma, kurallar, Geliştirici Kurulumu ve yerel MCP özetleri.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Ekip Paylaşımı ve İşbirliği `Yakında`

Yakalanan bir oturumu tek tıklamayla bir ekip arkadaşınıza gönderin. Başarısız isteklere satır içi açıklama ekleyin, gerçek zamanlı olarak kimin neye baktığını görün ve ekran paylaşımına gerek kalmadan HTTPS trafiğinde çift hata ayıklama yapın. Gelecekteki bir sürüm için hedeflendi.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> %100 yerel macOS. Elektron yok. Web görünümü yok. SwiftUI + AppKit + SwiftNIO.

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

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Proje modeli** | AGPL-3.0 açık kaynak projesi | Tescilli ticari uygulama | Tescilli ticari uygulama |
| **Kaynak kodu** | Herkese açık, denetlenebilir, çatallanabilir | Kapalı kaynak | Kapalı kaynak |
| **Kaynaktan derle** | Bu depodan Xcode ile ücretsiz | Herkese açık kaynakta mevcut değil | Herkese açık kaynakta mevcut değil |
| **Yerel macOS temeli** | Swift + SwiftNIO + SwiftUI/AppKit | Yerel macOS ticari uygulaması | Platformlar arası ticari uygulama |
| **Yerel öncelikli yakalama** | Yerel proxy, sertifikalar, yardımcı ve yakalama verileri Mac'inizde kalır | Masaüstü proxy uygulaması | Masaüstü proxy uygulaması |
| **Geliştirici kurulumu iş akışı** | Çalışma zamanları, istemciler, cihazlar, çerçeveler ve ortamlar için yerleşik Geliştirici Kurulum Merkezi | Ürüne özel kurulum kılavuzu | Ürüne özel kurulum kılavuzu |
| **Harici proxy + PAC yönlendirme** | HTTP/HTTPS yukarı akış proxy'si, PAC otomatik yapılandırması ve kuralları atlama | Olgun ticari proxy araçları | Olgun ticari proxy araçları |
| **MCP/yerel otomasyon köprüsü** | Yerleşik, belirteç kimlik doğrulamalı, varsayılan olarak redaksiyon | İncelenen herkese açık belgelerde hak talebinde bulunulmadı | İncelenen herkese açık belgelerde hak talebinde bulunulmadı |
| **Katkı yolunu aç** | Kamuya açık konular, tartışmalar, yol haritası ve halkla ilişkiler | Satıcı kontrollü ürün | Satıcı kontrollü ürün |

Yol haritasında: daha derin yeniden oynatma/diff/kurallar/komut dosyası oluşturma iş akışları, iyileştirilmiş WebSocket ve GraphQL denetimi, protokole duyarlı yapay zeka ve Web3/RPC hata ayıklama, x402 tarzı ödeme akışı görünürlüğü ve gRPC/Protobuf artı HTTP/2 ve HTTP/3 desteğinin araştırılması.

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

Rockxy bağımsız geliştiriciler tarafından oluşturulmuş ve bakımı yapılmıştır. Sponsorluklar sürekli geliştirmeyi, güvenlik denetimlerini ve yeni özellikleri finanse eder.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

| Seviye | Faydaları |
|------|----------|
| **Altın Sponsor** | README+ docs sitesinde logo, öncelikli özellik istekleri, doğrudan destek kanalı |
| **Gümüş Sponsor** | README'de logo, sürüm notlarında adı geçen onay |
| **Bronz Sponsor** | README ve dokümanlarda adlandırılmış onay |
| **Ortak** | Ortak geliştirme, entegrasyon desteği, gelecek özelliklere erken erişim |

**Ortaklık soruları** — özel entegrasyonlar veya beyaz etiket çözümleri arayan geliştirici aracı şirketleri, güvenlik firmaları ve kurumsal ekipler: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Destek

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — Rockxy'nin gelişimini desteklemek
- [GitHub Sorunları](https://github.com/RockxyApp/Rockxy/issues) — hata raporları ve özellik istekleri
- [GitHub Tartışmaları](https://github.com/RockxyApp/Rockxy/discussions) — sorular ve topluluk sohbeti
- **E-posta** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Güvenlik sorunları** — gör [SECURITY.md](SECURITY.md) Sorumlu açıklama için

## Lisans

[GNU Affero Genel Kamu Lisansı v3.0](LICENSE) — Telif Hakkı 2024–2026 Rockxy Katkıda Bulunanlar.

## Yıldız Tarihi

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Tarafından yapılmıştır <a href="https://github.com/LocNguyenHuu">Stephen</a>. Swift, SwiftNIO, SwiftUI ve AppKit ile oluşturulmuştur.</sub>
</p>
