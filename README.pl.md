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
  <strong>Serwer proxy debugowania typu open source z możliwością audytu dla systemu macOS.</strong>
</p>

<p align="center">
  Przechwytuj, sprawdzaj i modyfikuj ruch HTTP/HTTPS/WebSocket/GraphQL za pomocą natywnej aplikacji Swift, którą możesz sprawdzać, budować i której możesz ufać.<br>
  Stworzony z myślą o przepływach pracy związanych z API, urządzeniami mobilnymi, wspomaganymi MCP, sztuczną inteligencją i erą blockchain w miarę ewolucji Rockxy.<br>
  Pierwsza lokalna alternatywa AGPL-3.0 dla <a href="#rockxy-vs-alternatives">Proxyman i Charles Proxy</a>.
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

**v0.29.0** — 2026-07-12

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

## Aktualne najważniejsze wydarzenia w branży

- AI Assistant oferuje local analysis lub model Ollama/provider po Review Data; sidebar zawiera Focus Sets i Noise Control; workspace używa natywnych split view; a inspekcja AI/Web3/x402 jest obecnym zachowaniem.
- Upstream Proxy zawiera teraz bezpłatną/rdzeniową automatyczną konfigurację serwera proxy z routingiem adresów URL PAC dla `DIRECT`, HTTP i HTTPS, zachowując istniejące granice SOCKS5 i zasad uwierzytelniania.
- Przepływy pracy eksportu obejmują teraz OpenAPI YAML/HTML i publikowanie Gist dla wybranego ruchu z tworzeniem ładunku uwzględniającego redakcję.
- Narzędzia inspektora obejmują teraz filtrowanie ścieżki/klucza/wartości JSONPath i szybki podgląd wybranego tekstu ładunku, takiego jak JWT.
- Konfiguracja programisty Node.js odzwierciedla teraz wybranego klienta podczas sprawdzania poprawności i zawiera pełniejszy przykładowy przewodnik po serwerze lokalnym.
- Developer Setup Hub obejmuje teraz środowiska wykonawcze, przeglądarki, klientów, urządzenia, frameworki i środowiska z fragmentami specyficznymi dla celów docelowych, obserwatorami sprawdzającymi poprawność i rzetelną zawartością przewodników.
- Inspekcja binarnych frame WebSocket obejmuje teraz ograniczone, uruchamiane na żądanie heuristic Protobuf wire-format bez dodawania decoder work do capture hot path.
- Publiczna roadmap skupia się teraz na głębszych protocol-aware rules, replay, comparison i bezpieczniejszym udostępnianiu zredagowanych dowodów.

## Funkcje

Narzędzia, po które sięgasz, gdy przeglądarki DevTools nie wystarczą. Podstawowe debugowanie ruchu na komputerach Mac i iOS działa — natywnie w systemie macOS, z wersjami publicznymi i przepływem pracy zorientowanym na lokalnie.

### Przechwytywanie ruchu

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

Sprawdzaj ruch HTTP, HTTPS, WebSocket i GraphQL z dowolnej aplikacji Mac, interfejsu CLI lub urządzenia z systemem iOS. Przeglądarki DevTools kończą się na przeglądarce — Rockxy widzi resztę Twojego stosu.

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### Zaawansowane filtrowanie i wyszukiwanie

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

W ciągu kilku sekund zawęź tysiące przechwyconych żądań. Połącz filtry metody, hosta, stanu, nagłówka, treści i procesu — lub przeprowadź wyszukiwanie pełnotekstowe w całej sesji.

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets i Noise Control

Zamień powtarzające się dochodzenia w wielokrotnego użytku zakresy sidebara. Focus Sets łączy include aplikacji, domeny i ścieżki z exclude domeny/ścieżki, zachowuje się między uruchomieniami i jest dostępny w każdym workspace. Noise Control nadal przechwytuje telemetrię i ruch o niskiej wartości, ale ukrywa go w bieżącym workspace.

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="Rockxy AI Assistant wyjaśnia wybrany ruch obok natywnej tabeli requestów i sidebara" width="820" />

Wybierz jeden lub więcej przechwyconych requestów i zapytaj, co się stało, co zawiodło, co się zmieniło lub co sprawdzić dalej. Rockxy zaczyna od analizy opartej na dowodach na tym Macu; skonfigurowany model Ollama lub provider działa dopiero po pokazaniu przez Review Data dokładnego, ograniczonego i zredagowanego kontekstu. Odpowiedzi mogą ujawnić source request i przygotować natywne workflow follow-up, ale nigdy automatycznie nie modyfikują ruchu ani nie wykonują akcji.

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[Przeczytaj przewodnik AI Assistant](docs/features/ai-assistant.mdx).

### Serwer MCP dla zewnętrznych klientów AI

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Pozwól Claude Desktop lub Cursorowi odczytać przechwycony ruch przez lokalny serwer MCP. Zapytaj „dlaczego ta 500?” zamiast wklejać nagłówki na czacie. Lokalne, uwzględniające redakcje i open source.

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Centrum konfiguracji programisty

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Skopiuj i wklej fragmenty proxy dla Pythona, Node.js, Go, Rust, cURL, Docker i przeglądarek, a następnie kliknij Uruchom test, aby potwierdzić, że ruch rzeczywiście przepływa.

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### Zarządzanie certyfikatami na potrzeby debugowania HTTPS

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

Główny urząd certyfikacji ECDSA P-256 wygenerowany przy pierwszym uruchomieniu i zapieczętowany w pęku kluczy. Odszyfruj HTTPS przy pierwszej próbie; przypięte hosty przechodzą automatycznie.

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### Deszyfrowanie SSL Proxy i HTTPS

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

Wybierz, którzy hosty mają uzyskać odszyfrowanie TLS. Odszyfrowany ruch pokazuje prawdziwe nagłówki i JSON; wszystko inne przechodzi przez szyfrowanie. Reguły wieloznaczne umożliwiają określenie zakresu według domeny jednym kliknięciem.

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Omiń serwer proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

Pomiń określone hosty, aby aplikacje z przypiętymi certyfikatami, usługi wewnętrzne lub zaszumiona telemetria nigdy nie zostały przechwycone. Dzięki symbolom wieloznacznym lista jest krótka, a dziennik żądań koncentruje się na tym, na czym naprawdę Ci zależy.

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Lista zablokowanych

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

Spraw, aby dowolny host zawiódł. Porzuć sieci reklamowe, zewnętrzne moduły śledzące lub niestabilną zależność, aby zobaczyć, jak Twoja aplikacja pogarsza się po jej zniknięciu – bez zmiany linijki kodu.

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Mapa lokalna

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

Zamiast odpowiedzi na żywo udostępniaj zapisany plik lub drzewo katalogów. Zamień ładunek JSON, odtwórz migawkę lub przypnij wadliwy interfejs API innej firmy do kopii lokalnej podczas debugowania.

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Mapa zdalna

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

Przepisz miejsce docelowe przechwyconego żądania bez dotykania kodu aplikacji lub pliku /etc/hosts. Skieruj ruch produkcyjny na platformę, serwer deweloperski lub maszynę kolegi, aby uzyskać powtarzalne odwzorowanie błędów.

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### Punkty przerwania i reguły

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

Wstrzymaj żądanie lub odpowiedź, edytuj metodę, nagłówki, treść lub stan, a następnie kontynuuj. Najszybszy sposób przetestowania „co się stanie, jeśli API zwróci 401?” bez dotykania backendu.

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### Modyfikuj nagłówki

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

Dodaj, usuń lub zamień nagłówki na dowolnym hoście bez ponownego wdrażania. Testuj zmiany CORS, uwierzytelniania lub pamięci podręcznej w ciągu kilku sekund dzięki wbudowanym ustawieniom wstępnym.

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### Niestandardowe nagłówki żądań i odpowiedzi

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

Zastąp nagłówki na hosta z pełną kontrolą nad obiema fazami. Wstrzykuj tokeny uwierzytelniające do żądań wychodzących, usuwaj pliki cookie z odpowiedzi lub przypinaj niestandardowego klienta użytkownika — zapisanego jako nazwane reguły, które możesz przełączać w dowolnym momencie.

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### Warunki sieciowe

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Przejdź do 3G, EDGE, LTE, WiFi lub niestandardowego opóźnienia. Twój laptop jest podłączony do światłowodu; Twoi użytkownicy nie są — zobacz UX przy 400 ms RTT, zanim to zrobią.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Utwórz — edytuj i odtwarzaj ponownie

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Odbuduj dowolne przechwycone żądanie HTTP — zmień metodę, adres URL, nagłówki, parametry zapytania lub treść — i wyślij ponownie bez opuszczania Rockxy. Żadnego listonosza, bezsenności ani pętli kopiuj-wklej. Wykonuj iteracje zgodnie z monitami LLM, rozmyj granice uwierzytelniania lub odtwórz przypadek niepowodzenia dla punktów końcowych OpenAI, Anthropic i Cohere w ciągu kilku sekund.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Porównaj

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

Ułóż dwie przechwycone odpowiedzi obok siebie i zlokalizuj każde pole, które uległo odwróceniu — status, nagłówki, klucze JSON, bajty treści. Przechwytuj ciche regresje API, niedeterministyczne wyniki LLM i natychmiastowy dryf bez przesyłania czegokolwiek do narzędzia różnicowego innej firmy. Porównanie obok siebie podkreśla to, co się zmieniło; głębokie porównanie JSON ignoruje kolejność kluczy.

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### Niestandardowe karty podglądu

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

Renderuj treść żądań i odpowiedzi tak, jak chcesz. Przypnij do inspektora dodatkowe karty dla JSON, GraphQL, JWT, obrazu lub własnego formatu — można je ponownie wykorzystać w każdym przechwyconym żądaniu.

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### Sesje i eksport

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

Zapisuj sesje, importuj/eksportuj pliki HAR w celu przekazywania między narzędziami, kopiuj dowolne żądania jako cURL lub JSON. Przed udostępnieniem zredaguj nagłówki autoryzacji, pliki cookie i tokeny okaziciela — przekaż członkowi zespołu działającą kopię błędu bez ujawniania tajemnic.

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### Obszary robocze z wieloma kartami

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="Wielokartowe obszary robocze Rockxy z niezależnie filtrowanymi widokami tego samego przechwytywania na żywo" width="820" />

Trzymaj obok siebie niezależne widoki dochodzenia dla tego samego przechwytywania na żywo. Każda karta zachowuje własne filtry, sortowanie, wybór, zakres sidebara i stan inspektora, współdzieląc proxy i przechwycone transakcje.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Skrypty JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS przechwytuje żądania i odpowiedzi w przypadkach, których nie obejmuje reguła statyczna — redaguj informacje umożliwiające identyfikację, podpisz tokeny, przepisz ładunki. Błędy pojawiają się w tekście, zamiast zakłócać ruch.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Inspekcja Świadoma Protokołu

Rockxy oferuje protocol-aware inspection dla AI, Web3 RPC i x402 w zwykłym workflow debugowania HTTP.

### Inspekcja ruchu AI

Ułatw debugowanie ruchu modelowego w ramach normalnego przepływu pracy przechwytywania. Wykrywaj żądania AI, sprawdzaj wywołania wybranych modeli, diagnozuj odpowiedzi przesyłane strumieniowo, porównuj zachowanie podpowiedzi/wyjść i zrozum łańcuchy wywołań narzędzi bez wklejania wrażliwych ładunków do innej usługi.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Inspekcja Web3/RPC

Sprawdzaj ruch HTTP JSON-RPC w stylu EVM i Solana z provider host, request ID, method, batch summary, error, chain, transaction, payload i debug intent, bez zmieniania Rockxy w wallet lub block explorer.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### Wskazówki przepływu płatności x402

Zrozumienie przepływów HTTP bramkowanych płatnościami z warstwy sieciowej. Zaznacz odpowiedzi wymagające płatności, postępuj zgodnie ze ścieżką ponawiania próby i przechowuj dowody debugowania na poziomie lokalnym i uwzględniającym możliwość redakcji.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Przyszłe Prace

Poniższe sekcje opisują publiczny kierunek, a nie obecne zachowanie.

### Zredagowane pakiety dowodów `Wkrótce`

Podziel się faktami niezbędnymi do odtworzenia błędu bez ujawniania tajemnic. Spakuj wybrany ruch za pomocą podsumowań protokołów, podglądów redakcji i kontekstu opartego na źródłach, który członek zespołu może sprawdzić.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Reguły uwzględniające protokoły

Korzystaj z metadanych AI i Web3 tam, gdzie Rockxy już działa: filtrów, odznak, opcjonalnych kolumn, porównań, reguł, konfiguracji programisty i lokalnych podsumowań MCP.

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Udostępnianie i współpraca w zespole `Wkrótce`

Wyślij przechwyconą sesję do członka zespołu jednym kliknięciem. Dodawaj adnotacje do żądań, które zakończyły się niepowodzeniem, sprawdzaj, kto na co patrzy w czasie rzeczywistym i debuguj ruch HTTPS w parach bez udostępniania ekranu. Przeznaczone dla przyszłej wersji.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% natywny system MacOS. Żadnego elektronu. Brak widoków internetowych. SwiftUI + AppKit + SwiftNIO.

## Szybki start

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Kompiluj i uruchamiaj w Xcode. Okno Witamy prowadzi Cię przez konfigurację głównego urzędu certyfikacji, instalację pomocniczą i aktywację serwera proxy.

**Wymagania:** macOS 14.0+, Xcode 16+, Swift 5.9

Jeśli po instalacji chcesz połączyć Rockxy z lokalnym klientem MCP, zapoznaj się z sekcją [Przewodnik po integracji MCP](docs/features/mcp.mdx).

## Rockxy kontra alternatywy

|    | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Model projektu** | Projekt open source AGPL-3.0 | Zastrzeżona aplikacja komercyjna | Zastrzeżona aplikacja komercyjna |
| **Kod źródłowy** | Publiczne, podlegające audytowi, możliwe do rozwidlenia | Zamknięte źródło | Zamknięte źródło |
| **Kompiluj ze źródła** | Bezpłatnie z Xcode z tego repozytorium | Niedostępne ze źródła publicznego | Niedostępne ze źródła publicznego |
| **Natywna podstawa systemu MacOS** | Swift + SwiftNIO + SwiftUI/AppKit | Natywna aplikacja komercyjna dla systemu macOS | Wieloplatformowa aplikacja komercyjna |
| **Przechwytywanie lokalne** | Lokalny serwer proxy, certyfikaty, pomocnik i dane przechwytywania pozostają na komputerze Mac | Aplikacja proxy na komputer stacjonarny | Aplikacja proxy na komputer stacjonarny |
| **Proces konfiguracji programisty** | Wbudowane centrum konfiguracji programisty dla środowisk wykonawczych, klientów, urządzeń, frameworków i środowisk | Wskazówki dotyczące konfiguracji specyficzne dla produktu | Wskazówki dotyczące konfiguracji specyficzne dla produktu |
| **Zewnętrzny serwer proxy + routing PAC** | Serwer proxy HTTP/HTTPS, automatyczna konfiguracja PAC i reguły omijania | Dojrzałe komercyjne narzędzia proxy | Dojrzałe komercyjne narzędzia proxy |
| **Most MCP/lokalna automatyka** | Wbudowane, uwierzytelniane tokenem, domyślnie redakcja | Nie zgłoszono roszczeń w dokumentach publicznych, które zostały sprawdzone | Nie zgłoszono roszczeń w dokumentach publicznych, które zostały sprawdzone |
| **Otwarta ścieżka wkładu** | Kwestie publiczne, dyskusje, plan działania i PR | Produkt kontrolowany przez sprzedawcę | Produkt kontrolowany przez sprzedawcę |

Plan działania: głębsze protocol-aware rules, bezpieczniejsze redacted evidence bundles, mocniejsze workflow replay i comparison, szersze przewodniki Developer Setup oraz dalsze badania HTTP/2 i HTTP/3.

## Bezpieczeństwo

Rockxy przechwytuje ruch sieciowy — bezpieczeństwo to podstawa, a nie opcja.

- Pomocnik XPC sprawdza osoby dzwoniące za pośrednictwem **porównanie łańcucha certyfikatów**, a nie tylko identyfikator pakietu
- Wtyczki się uruchamiają **JavaScriptCore w piaskownicy** z 5-sekundowym limitem czasu, brak dostępu do systemu plików/sieci
- **Walidacja danych wejściowych** na wszystkich granicach — ograniczenia rozmiaru treści, limity URI, ochrona przed DoS wyrażeń regularnych, zapobieganie przechodzeniu ścieżek
- Poświadczenia **automatycznie zredagowane** w przechwyconych dziennikach
- Wrażliwe pliki przechowywane w **0o600 uprawnień**

Zgłoś luki w zabezpieczeniach poprzez [SECURITY.md](SECURITY.md). Zobacz [pełna architektura bezpieczeństwa](docs/development/security.mdx) po szczegóły.

## Plan działania

Publiczny plan działania Rockxy jest zorientowany na przepływ pracy i nie zawiera dat. Koncentruje się na niezawodności, natywnym UX systemu macOS, przepływach pracy debugowania, obsłudze protokołów, widoczności ruchu w erze AI/Web3, dokumentacji i wdrażaniu współpracowników.

- [ROADMAP.md](ROADMAP.md): kierunek inżynierii publicznej wysokiego szczebla
- [Publiczny plan działania Rockxy](https://github.com/orgs/RockxyApp/projects/1): widoczność operacyjna problemów objętych planem działania

## Dokumentacja

Pełna dokumentacja dostępna na stronie [Dokumenty Rockxy'ego](docs/index.mdx):

- [Przewodnik szybkiego startu](docs/quickstart.mdx) — wstań i działaj w ciągu kilku minut
- [Centrum konfiguracji programisty](docs/features/developer-setup-hub.mdx) — fragmenty środowiska wykonawczego, przewodniki po urządzeniach, sondy sprawdzające i macierz wsparcia
- [AI Assistant](docs/features/ai-assistant.mdx) — badaj wybrany ruch lokalnie lub z configured model po Review Data
- [Filtry i wyszukiwanie](docs/core-features/filters-and-search.mdx) — scope sidebara, Focus Sets, Noise Control, filtry toolbar i wyszukiwanie
- [Inspekcja AI i Web3](docs/features/ai-web3-inspection.mdx) — sprawdzaj rozpoznany ruch model API, JSON-RPC i x402
- [Integracja MPK](docs/features/mcp.mdx) — połącz Rockxy z lokalnymi klientami MCP
- [Architektura](docs/development/architecture.mdx) — silnik proxy, model aktora, przepływ danych
- [Model bezpieczeństwa](docs/development/security.mdx) — granice zaufania, walidacja XPC, zarządzanie certyfikatami
- [Decyzje projektowe](docs/development/design-decisions.mdx) — dlaczego SwiftNIO, NSTableView, aktorzy
- [Budowanie ze źródła](docs/development/building.mdx) — buduj, testuj, lintuj i debuguj
- [Styl kodu](docs/development/code-style.mdx) — SwiftLint, SwiftFormat i konwencje
- [Dziennik zmian](CHANGELOG.md) — niepublikowane prace i oznaczone wydania

## Wkład

Mile widziany wkład — kod, testy, dokumenty, raporty o błędach i opinie na temat UX.

Zobacz **[CONTRIBUTING.md](CONTRIBUTING.md)** aby uzyskać instrukcje konfiguracji, styl kodu i pełną listę kontrolną PR.

Dobre pierwsze wydania są oznaczone [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). Otwierając PR, wyrażasz zgodę na [CLA](CLA.md).

## Sponsorzy i partnerzy

Rockxy jest tworzony i utrzymywany przez niezależnych programistów. Fundusze sponsorskie zapewniają ciągły rozwój, audyty bezpieczeństwa i nowe funkcje.

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

Rockxy jest objęty obsługą fiskalną przez [Open Source Collective](https://docs.oscollective.org/). Wpłaty i wydatki projektu są rejestrowane na [publicznej stronie Rockxy w Open Collective](https://opencollective.com/rockxy), co zapewnia przejrzysty wgląd w sposób otrzymywania i wykorzystywania środków.

| Poziom | Wkład | Co wspiera |
|--------|-------|------------|
| **Backer** | Od $5/miesiąc | Utrzymanie open source, dokumentację, testy i wydania |
| **Builder** | Od $25/miesiąc | Testy regresji, poprawę wydajności i codzienne procesy debugowania |
| **Sponsor** | $100/miesiąc | Długoterminowe utrzymanie narzędzia chroniącego prywatność i bezpłatnego dla programistów |
| **Sustaining Sponsor** | $500/miesiąc | Skoncentrowane utrzymanie i rozwój produktu, w tym automatyzację wydań i obsługę protokołów |

**Zapytania o partnerstwo** — firmy zajmujące się narzędziami dla programistów, firmy zajmujące się bezpieczeństwem i zespoły korporacyjne poszukujące niestandardowych integracji lub rozwiązań typu white-label: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Wsparcie

- [Open Collective](https://opencollective.com/rockxy/donate) — wesprzyj Rockxy poprzez przejrzysty budżet projektu
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — wspieraj rozwój Rockxy
- [Problemy z GitHubem](https://github.com/RockxyApp/Rockxy/issues) — raporty o błędach i prośby o nowe funkcje
- [Dyskusje na GitHubie](https://github.com/RockxyApp/Rockxy/discussions) — pytania i czat społecznościowy
- **E-mail** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Kwestie bezpieczeństwa** — zobacz [SECURITY.md](SECURITY.md) odpowiedzialnego ujawnienia

## Licencja

[Powszechna Licencja Publiczna GNU Affero v3.0](LICENSE) — Prawa autorskie 2024–2026 Współtwórcy Rockxy.

## Historia gwiazd

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Wykonane przez <a href="https://github.com/LocNguyenHuu">Stefana</a>. Zbudowany z Swift, SwiftNIO, SwiftUI i AppKit.</sub>
</p>
