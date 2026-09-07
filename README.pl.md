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
  Lokalna (local-first), oparta na AGPL-3.0 alternatywa dla <a href="#rockxy-kontra-alternatywy">Proxyman i Charles Proxy</a>.
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

## Aktualne najważniejsze wydarzenia w branży

- AI Assistant bada teraz jeden lub więcej wybranych requestów za pomocą wbudowanej analizy lokalnej lub opcjonalnego skonfigurowanego modelu Ollama/provider, z wyraźnym potwierdzeniem Review Data, ograniczoną redakcją, odpowiedziami strumieniowymi, evidence reveal i handoffami inicjowanymi przez użytkownika.
- Natywny sidebar zawiera teraz wielokrotnego użytku Focus Sets dla scope app/domain/path oraz Noise Control w zakresie workspace, który ukrywa pasujące domeny lub ścieżki bez zatrzymywania capture.
- Główny workspace używa teraz natywnych pionowych i poziomych split view dla Context Dock i dolnego inspektora, zachowując pełnowysokościowe dividery, spójne separatory toolbar/footer i automatyczną zmianę rozmiaru układu.
- Upstream Proxy zawiera teraz bezpłatną/rdzeniową automatyczną konfigurację serwera proxy z routingiem adresów URL PAC dla `DIRECT`, HTTP i HTTPS, zachowując istniejące granice SOCKS5 i zasad uwierzytelniania.
- Przepływy pracy eksportu obejmują teraz OpenAPI YAML/HTML i publikowanie Gist dla wybranego ruchu z tworzeniem ładunku uwzględniającego redakcję.
- Narzędzia inspektora obejmują teraz filtrowanie ścieżki/klucza/wartości JSONPath i szybki podgląd wybranego tekstu ładunku, takiego jak JWT.
- Inspekcja ruchu AI i Web3 dodaje teraz etykiety protokołu, karty inspektora i podsumowania debugowania dla rozpoznanych wywołań modeli, ruchu JSON-RPC i wskazówek płatności w stylu x402.
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

Pozwól Claude Desktop lub Cursorowi sprawdzić przechwycony ruch za pomocą dziesięciu narzędzi tylko do odczytu w lokalnym serwerze MCP Rockxy. Zapytaj „dlaczego to zwróciło 500?” zamiast wklejać nagłówki na czacie. Implementacja jest open source, uwierzytelniana tokenem i domyślnie utrzymuje redakcję danych wrażliwych włączoną.

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

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header columns with a saved X-Trace-ID response column" width="820" />

Awansuj dowolny nagłówek żądania lub odpowiedzi do kolumny pierwszej klasy w tabeli ruchu. Trzymaj źródła żądań i odpowiedzi osobno, zapisz nagłówki, na których Ci zależy, a następnie przeglądaj request ID, trace ID, stan pamięci podręcznej lub własne metadane bez otwierania każdego inspektora.

`Request Headers` · `Response Headers` · `Saved Columns` · `Trace IDs` · `Case-Insensitive Match` · `Live Table Update`

### Warunki sieciowe

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

Przejdź do 3G, EDGE, LTE, WiFi lub niestandardowego opóźnienia. Twój laptop jest podłączony do światłowodu; Twoi użytkownicy nie są — zobacz UX przy 400 ms RTT, zanim to zrobią.

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Utwórz — edytuj i odtwarzaj ponownie

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

Odbuduj dowolne przechwycone żądanie HTTP — zmień metodę, adres URL, nagłówki, parametry zapytania lub treść — i wyślij ponownie bez opuszczania Rockxy. Bez pętli kopiuj-wklej do Postman, Insomnia czy curl. Iteruj prompty LLM, fuzzuj granice uwierzytelniania lub odtwórz przypadek niepowodzenia dla punktów końcowych OpenAI, Anthropic i Cohere w ciągu kilku sekund.

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### Porównaj

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two synthetic JSON payloads side-by-side in the local read-only diff workspace" width="820" />

Ułóż dwie przechwycone transakcje lub wklejone payloady obok siebie i zlokalizuj każde pole, które się zmieniło — status, nagłówki, klucze JSON lub bajty treści. Wychwytuj ciche regresje API, niedeterministyczne wyniki LLM i prompt drift bez przesyłania czegokolwiek do narzędzia różnicowego innej firmy.

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

Trzymaj obok siebie niezależne widoki dochodzenia dla tego samego przechwytywania na żywo — jedna karta dla ruchu staging, jedna dla produkcji i jedna dla przepływu urządzenia iOS. Każda karta zachowuje własne filtry, sortowanie, wybór, zakres sidebara i stan inspektora, współdzieląc proxy i przechwycone transakcje.

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### Skrypty JavaScript

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

JS przechwytuje żądania i odpowiedzi w przypadkach, których nie obejmuje reguła statyczna — redaguj informacje umożliwiające identyfikację, podpisz tokeny, przepisz ładunki. Błędy pojawiają się w tekście, zamiast zakłócać ruch.

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## Inspekcja Świadoma Protokołu

Rockxy oferuje protocol-aware inspection dla AI, Web3 RPC i x402 w zwykłym workflow debugowania HTTP.

### Inspekcja ruchu AI

Rockxy wykrywa rozpoznane żądania AI w ramach normalnego przepływu przechwytywania. Sprawdzaj wybrane wywołania modeli, stan streamingu, pola usage gdy są obecne, ostrzeżenia, retrieval hints i podsumowania tool-call bez wklejania wrażliwych payloadów do innej usługi.

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Inspekcja Web3/RPC

Rockxy zamienia wywołania sieciowe ery blockchain w czytelne dowody debugowania. Sprawdzaj ruch HTTP JSON-RPC w stylu EVM i Solana z provider host, request ID, method, batch summary, error, chain, transaction, payload i debug intent, bez zmieniania Rockxy w wallet lub block explorer.

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### Wskazówki przepływu płatności x402

Rockxy wyróżnia wskazówki payment-required i zorientowane na retry, dzięki czemu przepływy HTTP payment-gated są zrozumiałe z warstwy sieciowej, podczas gdy dowody debugowania pozostają lokalne i redaction-aware.

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## Przyszłe Prace

Poniższe sekcje opisują publiczny kierunek, a nie obecne zachowanie.

### Reguły uwzględniające protokoły

Rockxy może już dziś oznaczać i sprawdzać ruch AI i Web3. Głębsze dopasowanie reguł według modelu, tool call, metody JSON-RPC, chain, transaction hash lub batch subcall pozostaje przyszłą pracą; obecne narzędzia modyfikacji ruchu nadal dopasowują URL, metodę HTTP i nagłówki.

`Smart Filters` · `Request Badges` · `Protocol Column` · `Inspector Tabs` · `Future Rule Metadata`

### Zredagowane pakiety dowodów `Wkrótce`

Podziel się faktami niezbędnymi do odtworzenia błędu bez ujawniania tajemnic. Spakuj wybrany ruch za pomocą podsumowań protokołów, podglądów redakcji i kontekstu opartego na źródłach, który członek zespołu może sprawdzić.

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### Udostępnianie i współpraca w zespole `Wkrótce`

Wyślij przechwyconą sesję do członka zespołu jednym kliknięciem. Dodawaj adnotacje do żądań, które zakończyły się niepowodzeniem, sprawdzaj, kto na co patrzy w czasie rzeczywistym i debuguj ruch HTTPS w parach bez udostępniania ekranu. Przeznaczone dla przyszłej wersji.

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> Natywna powłoka aplikacji macOS — bez Electron. SwiftUI + AppKit + SwiftNIO, z WebKit używanym tylko do podglądu treści HTML.

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

Główna macierz obejmuje serwery proxy ogólnego przeznaczenia do debugowania sieci. Testowanie bezpieczeństwa
pakiety i przechwytywacze zorientowane na przeglądarkę/API ze znacznym nakładaniem się przepływów pracy
są wymienione osobno, więc w odróżnieniu od produktów nie są prezentowane jako zamienne.
Analizatory pakietów i klienci wyłącznie API nie podlegają temu porównaniu.

### Bezpośrednie proxy do debugowania sieci

|  | **Rockxy** | **Proxyman** | **Charles Proxy** | **mitmproxy** | **HTTP Toolkit** | **Fiddler Everywhere** |
|---|---|---|---|---|---|---|
| **Kształt produktu** | Natywny serwer proxy debugowania macOS | Natywna aplikacja na macOS; Wersje Electron oparte na systemie Windows/Linux | Wieloplatformowy serwer proxy debugowania pulpitu | Wieloplatformowy zestaw narzędzi proxy CLI/TUI i interfejsu internetowego | Wieloplatformowy serwer proxy Electron i klient HTTP | Wieloplatformowy serwer proxy debugowania pulpitu |
| **Źródło i model kompilacji** | Źródło społeczności publicznej pod AGPL-3.0-or-later; można zbudować z Xcode. Oficjalny DMG zawiera również niepubliczne komponenty downstream | Zamknięte źródło; w przeglądanych oficjalnych materiałach nie wskazano żadnego źródła aplikacji publicznych | Zamknięte źródło; w przeglądanych oficjalnych materiałach nie wskazano żadnego źródła aplikacji publicznych | Publiczne źródło licencjonowane MIT; możliwość zbudowania ze źródła | Publiczne źródło pulpitu AGPL; możliwość zbudowania ze źródła; opublikowane pliki binarne mają dodatkowe opcje licencjonowania | Zamknięte źródło; dystrybuowany jako kod obiektowy pod nazwą Fiddler Everywhere EULA |
| **Przechwytywanie i konfiguracja** | Lokalny serwer proxy systemu z przewodnikiem dotyczącym konfiguracji aplikacji dla komputerów Mac, środowisk wykonawczych, urządzeń iOS i symulatora | Automatyczna konfiguracja aplikacji Mac, środowisk wykonawczych i urządzeń mobilnych | Lokalny serwer proxy z przewodnikami konfiguracji macOS, iOS i międzyplatformowymi | Zwykły, proces lokalny, WireGuard, tryb odwrotny, przezroczysty i inne tryby przechwytywania | Ukierunkowane i ręczne przechwytywanie proxy dla przeglądarek, środowisk wykonawczych, kontenerów i urządzeń mobilnych | Tryby przechwytywania systemu, sieci, przeglądarki, terminala, jawne i urządzenia zdalnego |
| **Modyfikuj i kpij** | Punkty przerwania, Map Local/Remote, reguły nagłówków, blokowanie i reguły opóźnień | Punkty przerwania, Map Local/Remote, listy bloków, warunki sieciowe i reguły JavaScript | Punkty przerwania, przepisywanie, Map Local/Remote, blokowanie i ograniczanie | Map Local/Remote, modyfikacja treści/nagłówka, blokowanie i odtwarzanie serwera | Punkty przerwania oraz przepisywanie, przekierowywanie, próbowanie i wstrzykiwanie błędów w oparciu o reguły; część automatyzacji jest ograniczona planem | Reguły, punkty przerwania, przekierowania, modyfikacja odpowiedzi i drwiny |
| **Odtwórz i porównaj** | Utwórz/odtwórz ponownie oraz porównanie lokalnych żądań równoległych, nagłówków i treści | Twórz, powtarzaj i różnicuj | Powtarzaj i edytuj żądania | Powtórka po stronie klienta i serwera | Wbudowany klient HTTP do tworzenia i wysyłania żądań | API Kompozytor, odtwarzanie ruchu i porównanie ruchu udokumentowane w wersji beta |
| **Przepływy pracy WebSocket** | Inspekcja ramek tekstowych/binarnych za pomocą ograniczonej heurystyki Protobuf | Kontrola WS/WSS; skrypty mogą modyfikować adresy URL/nagłówki uzgadniania, a nie wiadomości | Obsługa WebSocket jest udokumentowana w oficjalnej historii wersji | Przechwytywanie i wykonywanie skryptów WebSocket; Powtórka WebSocket nie jest obsługiwana | Kontrola WebSocket plus zasady specyficzne dla WebSocket | WebSocket przechwytywanie i inspekcja |
| **Skrypty i rozszerzalność** | Haki JavaScriptCore w trybie piaskownicy z ograniczonym API i przekroczeniem limitu czasu wykonania | JavaScript skrypt żądania/odpowiedzi | Przepisz reguły i kontroluj interfejs sieciowy; brak udokumentowanej ogólnej funkcji skryptowej JavaScript | Dodatki Python i automatyzacja wiersza poleceń | Automatyzacja oparta na regułach oraz publiczne biblioteki źródłowe i proxy | Automatyzacja oparta na regułach; nie udokumentowano żadnej ogólnej funkcji tworzenia skryptów |
| **Routing upstream** | [HTTP/HTTPS upstream proxy i PAC routing URL](docs/features/upstream-proxy.mdx); Polityka społeczności wyłącza uwierzytelnianie proxy i SOCKS5 oraz ogranicza reguły obejścia do trzech | Zewnętrzne routing HTTP/HTTPS/SOCKS i PAC z regułami obejścia | Zewnętrzne proxy HTTP/HTTPS/SOCKS z regułami uwierzytelniania i obejścia | HTTP/HTTPS tryb przesyłania danych plus tryby odtwarzania wstecznego i SOCKS | Ustawienia przesyłania danych systemowych, HTTP, HTTPS i SOCKS; mogą obowiązywać limity planu | Automatyczne łączenie z systemowymi serwerami proxy oraz przechwytywanie zwrotnego proxy |
| **AI i MCP** | [Asystent AI w aplikacji](docs/features/ai-assistant.mdx) i [wbudowany lokalny MCP](docs/features/mcp.mdx) z 10 narzędziami tylko do odczytu, domyślnie włączonym uwierzytelnianiem tokenem i redakcją | Wbudowany MCP dla zewnętrznych klientów AI, w tym odczyty ruchu i kontrola aplikacji/reguł | Nieudokumentowane | Nieudokumentowane | Aktualne oficjalne źródła zawierają dołączony lokalny most MCP; brak udokumentowanego asystenta w aplikacji | Wbudowany MCP plus profesjonalny asystent debugowania, którego aktualna dokumentacja wymaga wklejenia przechwyconych szczegółów ruchu do czatu |

### Sąsiednie narzędzia przechwytujące

Produkty te w znacznym stopniu pokrywają się z Rockxy, ale prowadzą testy bezpieczeństwa,
reguły przeglądarki lub przepływy pracy klienta API, zamiast tego samego ogólnego przeznaczenia
natywny fokus debugowania-proxy.

| **Produkt** | **Dlaczego sąsiaduje** | **Źródło i model kompilacji** | **Odpowiednie nakładanie się** | **AI i MCP** |
|---|---|---|---|---|
| **Burp Suite** | Zestaw do testowania bezpieczeństwa sieciowego z przechwytującym serwerem proxy | Aplikacja o zamkniętym kodzie źródłowym; w EULA stwierdza się, że użytkownicy nie mają prawa do źródła aplikacji. Rozszerzenia mogą korzystać z oddzielnych licencji | Przechwytywanie i dopasowywanie/zamiana proxy proxy, wzmacniak, WebSocket, proxy upstream/SOCKS i ekosystem dużych rozszerzeń | Burp AI jest dostępny w Repeaterze; PortSwigger utrzymuje również publiczne rozszerzenie serwera MCP dla zewnętrznych klientów AI |
| **ZAP** | Skaner bezpieczeństwa i przechwytujący serwer proxy | Publiczne źródło Apache-2.0; możliwość zbudowania ze źródła | Przechwytywanie/edycja, ręczne ponowne wysyłanie, punkty przerwania i skrypty WebSocket, skrypty wielojęzyczne, dodatki i automatyzacja | Oficjalna integracja MCP i opcjonalne dodatki LLM Support |
| **Requestly HTTP Interceptor** | Rozszerzenie przeglądarki i wieloplatformowe narzędzie do przechwytywania/makiet na pulpicie | Publiczne źródło przechwytywacza komputerów stacjonarnych AGPL; oddzielny klient Requestly API jest zastrzeżony zgodnie z zawiadomieniem o repozytorium społeczności publicznej | Przechwytywanie, przekierowywanie w całym systemie/przeglądarce, Map Local/Remote, modyfikacja nagłówka/treści, transformacje JavaScript, kpiny i symulacja opóźnień/błędów | Oddzielny oficjalny serwer MCP zarządza regułami i grupami; brak udokumentowanego asystenta analizy ruchu w aplikacji |

Dostępność funkcji może się różnić w zależności od wersji, planu, platformy lub dodatku.
„Nieudokumentowane” oznacza, że w oficjalnej wersji pierwszej nie znaleziono możliwości
źródła sprawdzone w 2026-08-22; nie jest to dowód na brak takiej zdolności.
Powyższe oświadczenia dotyczące produktów i funkcji zostały sprawdzone z dokumentacją dostawcy,
repozytoria źródłowe prowadzone przez dostawcę lub warunki licencji dostawcy obowiązujące w tym dniu oraz
może się zmienić. Nazwy produktów i znaki towarowe należą do ich odpowiednich właścicieli;
Rockxy nie jest z nimi powiązany ani nie jest przez nich wspierany. Poprawki mile widziane
poprzez narzędzie do śledzenia problemów Rockxy.

Plan działania: głębsze zasady uwzględniające protokoły, bezpieczniejsze zredagowane pakiety dowodów, skuteczniejsze procesy odtwarzania i porównywania, szersze wskazówki dotyczące konfiguracji dla programistów oraz ciągłe badania nad protokołami HTTP/2 i HTTP/3.

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
- [Integracja MCP](docs/features/mcp.mdx) — połącz Rockxy z lokalnymi klientami MCP
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

Rockxy jest utrzymywany niezależnie. Sponsoring pomaga finansować ciągły rozwój, infrastrukturę wydań, dokumentację i prace nad bezpieczeństwem.

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

<a href="https://star-history.dera.page/#RockxyApp/Rockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Wykonane przez <a href="https://github.com/LocNguyenHuu">Stephen</a>. Zbudowany z Swift, SwiftNIO, SwiftUI i AppKit.</sub>
</p>
