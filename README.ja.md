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
  <strong>macOS 向けのオープンソースで監査可能なデバッグプロキシ。</strong>
</p>

<p align="center">
  検査・ビルド・信頼できるネイティブ Swift アプリで、HTTP/HTTPS/WebSocket/GraphQL トラフィックを傍受、検査、変更。<br>
  Rockxy の進化に合わせて、API、モバイル、MCP 支援、AI、ブロックチェーン時代のデバッグワークフローに対応していきます。<br>
  <a href="#rockxy-vs-他のツール">Proxyman と Charles Proxy</a> に代わる local-first、AGPL-3.0 の選択肢。
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="リリース" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="プラットフォーム" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="ライセンス" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PR 歓迎" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="スポンサー" /></a>
  <a href="https://opencollective.com/rockxy/donate"><img src="https://img.shields.io/badge/Open%20Collective-support%20Rockxy-7FADF2?logo=opencollective&logoColor=white" alt="Open Collective" /></a>
</p>

<p align="center">
  <a href="https://youtu.be/RvkQuwUjBaQ" title="Watch the Rockxy demo on YouTube">
    <img src="docs/images/Rockxy-Demo-Preview.png" alt="macOS で動作中の Rockxy" width="800" />
  </a>
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.30.0** — 2026-07-16

### Added

- Added a redesigned Focus Navigator with Browse, Focus, and Library modes for moving between all traffic, reusable investigation scopes, saved requests, and pinned requests.
- Added reusable Focus Sets, traffic signals, and noise controls for isolating errors, slow requests, WebSocket or GraphQL activity, rule hits, selected apps, domains, and paths without deleting captured traffic.
- Added a Context Dock that keeps request and response details available while navigating the traffic list.
- Added encrypted nearby iPhone session transfers into a dedicated iOS workspace so current Mac traffic remains available.

### Fixed

- Fixed Quick Tools customization so every part of each dropdown field opens its menu reliably.
- Kept selection state aligned when focus, signal, noise, or filter changes hide previously selected requests.

### Changed

- Refined workspace navigation, inspector layout, selection behavior, and persisted layout preferences for a clearer debugging workflow.
- Kept nearby iPhone transfer discovery available while Rockxy is running, including when macOS restores the app without a main window.
- Improved captured-value filtering so apps, domains, and paths are easier to reuse in focused investigations.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## 現在のブランチのハイライト

- AI Assistant は、内蔵ローカル分析または設定済み Ollama/provider model を使って選択した 1 件以上の request を調査し、明示的な Review Data、限定 redaction、streaming response、evidence reveal、ユーザー主導の handoff を提供します。
- ネイティブ sidebar に、app/domain/path scope を再利用できる Focus Sets と、capture を止めずに一致 domain/path を隠す workspace 単位の Noise Control が加わりました。
- Main workspace は Context Dock と bottom inspector にネイティブな縦横 split view を使用し、全高 divider、揃った toolbar/footer separator、自動 layout resize を保ちます。
- Upstream Proxy は、 `DIRECT` 、HTTP、HTTPS ルート向けの PAC URL ルーティングを含む free/core Automatic Proxy Configuration を備え、既存の SOCKS5 と認証ポリシー境界を保ちます。
- Export ワークフローは OpenAPI YAML/HTML と、redaction-aware な payload 構築による selected-traffic Gist 公開に対応しました。
- Inspector ツールは JSONPath/key/value フィルタリングと、JWT など選択した payload テキストのクイックプレビューに対応しました。
- AI/Web3 traffic inspection は、認識した model call、JSON-RPC traffic、x402-style payment hint に protocol label、inspector tab、debug summary を追加します。
- Node.js Developer Setup は検証中に選択した client を mirror し、localhost サンプルガイドもより充実しました。
- Developer Setup Hub は、ランタイム、ブラウザ、クライアント、デバイス、フレームワーク、環境を対象に、ターゲット別スニペット、検証ウォッチャー、正直なガイド内容をまとめて提供します。
- WebSocket binary-frame inspection は、capture hot path に decoder work を加えない限定・オンデマンドの Protobuf wire-format heuristic に対応しました。
- 公開ロードマップは、より深い protocol-aware rules、replay、comparison、安全な redacted evidence sharing に集中します。

## 機能

ブラウザの DevTools では足りないときに手を伸ばす道具たち。Mac と iOS の作業向けのコアな通信デバッグ — macOS ネイティブ、公開リリース、ローカルファーストのワークフロー。

### トラフィックキャプチャ

<img src="docs/images/features/TrafficCapture.png" alt="Rockxy capturing HTTP, HTTPS, WebSocket, and GraphQL traffic with a timing waterfall" width="820" />

あらゆる Mac アプリ、CLI、iOS デバイスからの HTTP、HTTPS、WebSocket、GraphQL トラフィックを検査します。ブラウザの DevTools はブラウザで終わりですが、Rockxy はスタックの残りも見えます。

`HTTP / HTTPS` · `WebSocket` · `GraphQL` · `iOS Device & Simulator` · `Filter by Process ID` · `Timing Waterfall`

### 高度なフィルタと検索

<img src="docs/images/features/DemoAdvancedFilterSearch.png" alt="Rockxy advanced filtering with multi-field filters and full-text search across a session" width="820" />

数千件のキャプチャ要求を数秒で絞り込みます。method、host、status、header、body、プロセスのフィルタを組み合わせるか、セッション全体に対して全文検索を実行します。

`Multi-Field Filters` · `Full-Text Search` · `Status / Method` · `Header / Body Match` · `Process / Host` · `Saved Filters`

### Focus Sets と Noise Control

繰り返す調査を sidebar の再利用可能な scope にします。Focus Sets は application/domain/path の include と domain/path の exclude を組み合わせ、再起動後も保持され、すべての workspace で使えます。Noise Control は telemetry など低価値な traffic を capture し続けながら、現在の workspace では隠します。

`Reusable Focus Sets` · `App / Domain / Path Scope` · `Include & Exclude` · `Workspace Noise Control` · `Capture Continues`

### AI Assistant

<img src="docs/images/features/DemoAIAssistant-Light.png" alt="ネイティブな request table と sidebar の横で選択 traffic を説明する Rockxy AI Assistant" width="820" />

1 件以上の capture request を選び、何が起きたか、何が失敗したか、何が変わったか、次に何を確認すべきかを質問できます。Rockxy はまずこの Mac 上で evidence-grounded analysis を実行し、設定済み Ollama/provider model は Review Data が限定・redaction 済み context を明示した後だけ動きます。応答は source request を reveal して follow-up workflow を準備できますが、traffic の変更や action の実行は自動では行いません。

`Built-in Local Analysis` · `Multi-Request Context` · `Ollama & Provider Models` · `Review Data` · `Sensitive-Data Redaction` · `Read-only Actions`

[AI Assistant ガイドを読む](docs/features/ai-assistant.mdx)。

### 外部 AI クライアント向け MCP サーバー

<img src="docs/images/features/DemoMCP.png" alt="Rockxy local MCP server exposing captured traffic to Claude Desktop and Cursor" width="820" />

Claude Desktop や Cursor にローカル MCP サーバー経由でキャプチャしたトラフィックを読み込ませます。ヘッダーをチャットに貼る代わりに「なぜこれが 500 になった?」と直接聞けます。ローカル、redaction-aware、そしてオープンソースです。

`Claude Desktop` · `Cursor` · `Local stdio` · `Redaction` · `Open Source`

### Developer Setup Hub

<img src="docs/images/features/DemoDevHub.png" alt="Rockxy Developer Setup Hub with copy-paste proxy snippets and one-click verify" width="820" />

Python、Node.js、Go、Rust、cURL、Docker、ブラウザ向けのプロキシ用スニペットをコピペし、Run Test をクリックして実際にトラフィックが流れていることを確認します。

`Python` · `Node.js` · `Go / Rust / Java` · `cURL / Docker` · `One-Click Verify` · `Trust Diagnostics`

### HTTPS デバッグ用の証明書管理

<img src="docs/images/features/CertManagement.png" alt="Rockxy certificate management with a P-256 ECDSA root CA sealed in the Keychain" width="820" />

初回起動時に生成される P-256 ECDSA ルート CA を Keychain に封印します。HTTPS を一発で復号化し、ピン留めされたホストは自動的にバイパスされます。

`P-256 ECDSA Root CA` · `Keychain-Sealed Key` · `Per-Host Leaf Certs` · `Trust Wizard` · `Pinned-Host Passthrough` · `Rotate / Reset`

### SSL プロキシと HTTPS 復号化

<img src="docs/images/features/DemoSSLProxy.png" alt="Rockxy SSL proxy settings showing per-host TLS decryption rules with wildcard patterns and allow list" width="820" />

どのホストを TLS 復号化するかを選びます。復号化されたトラフィックは生の header と JSON を表示し、それ以外は暗号化されたまま通過します。ワイルドカードルールでワンクリックでドメイン単位にスコープできます。

`Per-Host Decryption` · `Wildcard Rules` · `Allow / Deny List` · `TLS 1.2 / 1.3` · `Pinned Host Passthrough`

### Bypass Proxy

<img src="docs/images/features/DemoByPassProxy.png" alt="Rockxy bypass proxy list skipping cert-pinned apps and noisy telemetry hosts" width="820" />

特定のホストをスキップし、証明書ピン留めアプリ、社内サービス、ノイズの多いテレメトリがキャプチャに混じらないようにします。ワイルドカードでリストを短く保ち、要求ログを本当に気になるものに集中させます。

`Per-Host Bypass` · `Wildcard Patterns` · `Skip Pinned Hosts` · `Mute Telemetry` · `Reduce Noise` · `Toggle Anytime`

### Block List

<img src="docs/images/features/DemoBlockList.png" alt="Rockxy block list dropping ad networks and flaky dependencies to simulate outages" width="820" />

任意のホストを失敗させます。広告ネットワーク、サードパーティトラッカー、不安定な依存関係を落として、それが消えたときにアプリがどう劣化するかを確認できます — コードは一行も変えずに。

`Per-Host Block` · `Wildcard Match` · `Simulate Outage` · `Test Fallbacks` · `Strip Trackers` · `Toggle Anytime`

### Map Local

<img src="docs/images/features/DemoMapLocal.png" alt="Rockxy Map Local serving a saved file or directory tree in place of a live response" width="820" />

ライブ応答の代わりに、保存ファイルやディレクトリツリーを返します。JSON ペイロードを差し替え、スナップショットをリプレイし、デバッグ中だけ不安定なサードパーティ API をローカルコピーに固定できます。

`File or Directory` · `Response Snapshot` · `Regex Patterns`

### Map Remote

<img src="docs/images/features/DemoMapRemote.png" alt="Rockxy Map Remote rewriting a request destination from production to staging" width="820" />

アプリのコードや /etc/hosts に触らずに、キャプチャ要求の宛先を書き換えます。本番トラフィックをステージング、開発サーバー、同僚のマシンへ向けて、再現性のあるバグ repro を作ります。

`Host Rewrite` · `Regex Patterns` · `Preserve Host Header`

### ブレークポイントとルール

<img src="docs/images/features/DemoBreakpoint.png" alt="Rockxy breakpoints pausing a request to edit method, headers, body, or status mid-flight" width="820" />

要求や応答を一時停止し、method、header、body、status を編集してから続行できます。「API が 401 を返したらどうなる?」をバックエンドに触らずにテストする最速の方法です。

`Request Breakpoints` · `Response Breakpoints` · `Block` · `Throttle` · `Regex / Wildcard Match` · `Inject Failure States`

### ヘッダー変更

<img src="docs/images/features/DemoModifyHeader.png" alt="Rockxy modifying request and response headers per host with CORS and auth presets" width="820" />

再デプロイなしで任意のホストの header を追加、削除、置換します。組み込みプリセットで CORS、認証、キャッシュの変更を数秒でテストできます。

`Add / Remove / Replace` · `CORS Presets` · `Auth Stripping` · `Request Phase` · `Response Phase` · `URL Pattern Scope`

### カスタム要求/応答ヘッダー

<img src="docs/images/features/DemoCustomRequestResponseHeader.png" alt="Rockxy custom request and response header rules injecting tokens and stripping cookies" width="820" />

ホスト単位で、両方のフェーズを完全に制御しながら header を上書きできます。送信要求に認証トークンを注入し、応答から Set-Cookie を取り除き、カスタム User-Agent を固定 — いつでも切り替えできる名前付きルールとして保存できます。

`Per-Host Override` · `Request Phase` · `Response Phase` · `Auth Token Inject` · `Cookie Strip` · `Named Rules`

### ネットワーク条件

<img src="docs/images/features/DemoNetworkConnection.png" alt="Rockxy network conditions throttling traffic to 3G, EDGE, LTE, or custom latency" width="820" />

3G、EDGE、LTE、WiFi、またはカスタム遅延にスロットルします。あなたのノート PC は光ファイバーですが、ユーザーはそうではありません — 400 ms RTT での UX をユーザーより先に確認できます。

`3G` · `EDGE` · `LTE` · `WiFi` · `Very Bad Network` · `Custom Latency`

### Compose — 編集とリプレイ

<img src="docs/images/features/DemoCompose.png" alt="Rockxy Compose editing and replaying a captured HTTP request without leaving the app" width="820" />

キャプチャした HTTP 要求を再構成 — method、URL、header、クエリパラメータ、body を変更 — して Rockxy を離れずに再送します。Postman、Insomnia、curl のコピペループは不要です。LLM プロンプトを反復、認証境界をファジング、OpenAI、Anthropic、Cohere エンドポイントの失敗ケースを数秒で再現します。

`Edit Headers` · `Edit Body` · `Edit Query` · `Edit Method` · `LLM Prompt Iteration` · `Postman Alternative` · `OAuth Flow Debug` · `Webhook Replay`

### 比較

<img src="docs/images/features/DemoDiff.png" alt="Rockxy comparing two captured responses side-by-side with JSON, header, and body diff" width="820" />

キャプチャ済みの 2 つの応答を並べて比較し、反転したすべてのフィールドを見つけます — status、header、JSON キー、body バイト。サードパーティの diff ツールにデータを送ることなく、静かな API リグレッション、非決定的な LLM 出力、プロンプトドリフトを捉えます。Side-by-side diff は差分を強調表示し、深い JSON 比較はキー順序を無視します。

`Diff Compare` · `Side-by-Side` · `JSON Diff` · `Header Diff` · `Body Diff` · `LLM Output Compare` · `Non-determinism` · `API Regression` · `Schema Drift`

### カスタムプレビュータブ

<img src="docs/images/features/DemoCustomPreviewerTab.png" alt="Rockxy custom inspector previewer tabs for JSON, GraphQL, JWT, and image bodies" width="820" />

要求と応答 body を望む形でレンダリングします。JSON、GraphQL、JWT、画像、または独自フォーマット用のタブをインスペクタにピン留め — どのキャプチャ要求でも再利用できます。

`JSON` · `GraphQL` · `JWT Decoder` · `Image / Hex` · `Custom Format` · `Pinned per Inspector`

### セッションとエクスポート

<img src="docs/images/features/DemoSessionExport.png" alt="Rockxy session export to HAR, cURL, and JSON with secret redaction before sharing" width="820" />

セッションを保存し、HAR を import/export してツール間で受け渡し、任意の要求を cURL または JSON にコピーします。共有前に authorization header、cookie、bearer token を redact — 秘密情報を漏らさずに、動作するバグ repro をチームメイトに渡せます。

`.rockxysession` · `HAR Import / Export` · `Copy as cURL` · `Copy as JSON` · `Raw HTTP` · `Secret Redaction` · `Token Sanitize` · `Privacy-Safe Share`

### マルチタブワークスペース

<img src="docs/images/features/DemoMultipleTabWorkingSpace.png" alt="同じ live capture を独立して filter した view を並べる Rockxy multi-tab workspace" width="820" />

同じ live capture に対する独立した調査 view を並べます。各 tab は独自の filter、sort、selection、sidebar scope、inspector state を持ちながら、proxy と capture transaction を共有します。

`Shared Live Capture` · `Per-Tab Filters & Sort` · `Per-Tab Inspector` · `Compare Environments` · `Mac & iOS Together` · `Detach & Rename`

### JavaScript スクリプティング

<img src="docs/images/features/DemoScripting.png" alt="Rockxy JavaScript scripting with request and response hooks and inline error feedback" width="820" />

静的ルールでは対応できないケースに、要求と応答に JS フックをかけます — PII を redact、トークンを署名、ペイロードを書き換え。エラーはトラフィックを壊さずインラインで表示されます。

`Request Hooks` · `Response Hooks` · `Programmatic Filtering` · `PII Redaction` · `Inline Error Feedback`

## プロトコル対応の検査

Rockxy は通常の HTTP debugging workflow 内で AI、Web3 RPC、x402 の protocol-aware inspection を提供しています。

### AI トラフィック検査

通常の capture ワークフローの中で model traffic をデバッグしやすくします。AI request を検出し、選択した model call を検査し、streaming response を診断し、prompt/output の挙動を比較し、sensitive payload を別サービスへ貼り付けずに tool-call chain を理解します。

`AI Requests` · `Model Inspector` · `Streaming State` · `Tool Calls` · `Retrieval Hints` · `Usage Signals`

### Web3/RPC 検査

EVM と Solana-style HTTP JSON-RPC traffic を provider host、request ID、method、batch summary、error、chain、transaction、payload、debug-intent detail とともに inspect し、Rockxy を wallet や block explorer にはしません。

`JSON-RPC` · `Solana RPC` · `Request ID` · `RPC Errors` · `Batch Summary` · `Network Evidence`

### x402 Payment Flow Hints

payment-gated HTTP flow をネットワーク層から理解します。payment-required response を強調し、retry path を追跡し、debugging evidence を local-first かつ redaction-aware に保ちます。

`Payment Required` · `Retry Flow` · `Headers` · `Redaction` · `Local First`

## 今後の取り組み

以下は現在の動作ではなく、公開している方向性です。

### Protocol-Aware Rules

Rockxy は現在 AI/Web3 traffic を label・inspect できます。model、tool call、JSON-RPC method、chain、transaction hash、batch subcall による深い rule matching は今後の取り組みで、現在の traffic modification tool は URL、HTTP method、header で match します。

`Smart Filters` · `Request Badges` · `Optional Columns` · `Rules` · `Compare` · `Local MCP`

### Redacted Evidence Bundles `近日公開`

secret を漏らさずに、bug repro に必要な事実を共有します。selected traffic、protocol summary、redaction preview、source-backed context をまとめ、チームメイトが監査できる形にします。

`Debug Bundles` · `Protocol Summary` · `Export Preview` · `Secret Redaction` · `Repro Context`

### チーム共有とコラボレーション `近日公開`

キャプチャしたセッションをワンクリックでチームメイトに送ります。失敗した要求にインラインで注釈を付け、誰が何を見ているかリアルタイムで確認し、画面共有なしで HTTPS トラフィックをペアデバッグできます。将来のリリースを目標にしています。

`Shared Sessions` · `Team Workspaces` · `Inline Comments` · `Live Cursor` · `Cloud Sync` · `Pair Debug` · `SSO` · `Audit Log`

> 100% ネイティブ macOS。Electron なし。Web ビューなし。SwiftUI + AppKit + SwiftNIO。

## クイックスタート

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Xcode でビルドして実行。ウェルカムウィンドウがルート CA のセットアップ、ヘルパーのインストール、プロキシの有効化をガイドします。

**要件：** macOS 14.0+、Xcode 16+、Swift 5.9

## Rockxy vs. 他のツール

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **プロジェクトモデル** | AGPL-3.0 オープンソースプロジェクト | プロプライエタリな商用アプリ | プロプライエタリな商用アプリ |
| **ソースコード** | 公開、監査可能、fork 可能 | クローズドソース | クローズドソース |
| **ソースからのビルド** | このリポジトリから Xcode で無料ビルド | 公開ソースからは利用不可 | 公開ソースからは利用不可 |
| **ネイティブ macOS 基盤** | Swift + SwiftNIO + SwiftUI/AppKit | ネイティブ macOS 商用アプリ | クロスプラットフォーム商用アプリ |
| **Local-first キャプチャ** | ローカルプロキシ、証明書、ヘルパー、キャプチャデータは Mac 上に保持 | デスクトッププロキシアプリ | デスクトッププロキシアプリ |
| **開発者セットアップワークフロー** | runtime、client、device、framework、environment 向けの Developer Setup Hub を内蔵 | 製品固有のセットアップガイド | 製品固有のセットアップガイド |
| **MCP/local automation bridge** | 内蔵、トークン認証、デフォルトでマスキング | 確認した公開ドキュメントでは未記載 | 確認した公開ドキュメントでは未記載 |
| **オープンな貢献経路** | 公開 issues、discussions、roadmap、PR | ベンダー管理の製品 | ベンダー管理の製品 |

ロードマップの方向性: より深い protocol-aware rules、安全な redacted evidence bundle、強化された replay/comparison workflow、幅広い Developer Setup guide、HTTP/2・HTTP/3 の継続研究。

## セキュリティ

Rockxy はネットワークトラフィックを傍受します — セキュリティは基盤であり、オプションではありません。

- XPC ヘルパーは bundle ID だけでなく、**証明書チェーン比較**で呼び出し元を検証
- プラグインは**サンドボックス化された JavaScriptCore** で実行、5 秒タイムアウト、ファイルシステム/ネットワークアクセス不可
- すべての境界で**入力バリデーション** — Body サイズ上限、URI 制限、正規表現 DoS 防止、パストラバーサル防止
- ログ内の認証情報を**自動的にマスキング**
- 機密ファイルは **0o600 パーミッション**で保存

脆弱性の報告は [SECURITY.md](SECURITY.md) を参照。詳細は[セキュリティアーキテクチャ](docs/development/security.mdx)をご覧ください。

## ロードマップ

Rockxy の公開ロードマップはワークフロー指向で、固定日程の約束ではありません。信頼性、ネイティブ macOS UX、デバッグワークフロー、プロトコル対応、AI/Web3 時代の traffic visibility、ドキュメント、コントリビューターのオンボーディングに焦点を当てています。

- [ROADMAP.md](ROADMAP.md)：高レベルの公開エンジニアリング方針
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1)：ロードマップ対象 issue の実行状況

## ドキュメント

完全なドキュメントは [Rockxy Docs](docs/index.mdx) で利用可能：

- [クイックスタートガイド](docs/quickstart.mdx) — 数分でセットアップ
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — ランタイム向けスニペット、デバイスガイド、検証プローブ、サポートマトリクス
- [AI Assistant](docs/features/ai-assistant.mdx) — ローカル分析または Review Data を確認した設定済み model で選択 traffic を調査
- [フィルタと検索](docs/core-features/filters-and-search.mdx) — sidebar scope、Focus Sets、Noise Control、toolbar filter、search
- [AI と Web3 の検査](docs/features/ai-web3-inspection.mdx) — 認識した model API、JSON-RPC、x402-style traffic を検査
- [MCP Integration](docs/features/mcp.mdx) — Rockxy をローカル MCP クライアントへ接続
- [アーキテクチャ](docs/development/architecture.mdx) — プロキシエンジン、Actor モデル、データフロー
- [セキュリティモデル](docs/development/security.mdx) — 信頼境界、XPC バリデーション、証明書管理
- [設計判断](docs/development/design-decisions.mdx) — SwiftNIO、NSTableView、Actor を選んだ理由
- [ソースからビルド](docs/development/building.mdx) — ビルド、テスト、lint、デバッグ
- [コードスタイル](docs/development/code-style.mdx) — SwiftLint、SwiftFormat、コーディング規約
- [変更履歴](CHANGELOG.md) — 未リリース作業と正式リリースの履歴

## コントリビューション

あらゆる貢献を歓迎します — コード、テスト、ドキュメント、バグ報告、UX フィードバック。

セットアップ手順、コードスタイル、PR チェックリストについては **[CONTRIBUTING.md](CONTRIBUTING.md)** をご覧ください。

初心者向けの issue には [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue) ラベルが付いています。PR を送ることで [CLA](CLA.md) に同意したものとみなされます。

## スポンサーとパートナー

Rockxy は独立した開発者によって構築・メンテナンスされています。スポンサーシップは継続的な開発、セキュリティ監査、新機能の資金となります。

<p align="center">
  <a href="https://opencollective.com/rockxy/donate">
    <img src="https://img.shields.io/badge/Support_on_Open_Collective-7FADF2?style=for-the-badge&logo=opencollective&logoColor=white" alt="Open Collective" />
  </a>
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Rockxy_をスポンサー-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Rockxy をスポンサー" />
  </a>
</p>

Rockxy は [Open Source Collective](https://docs.oscollective.org/) による財務ホスティングを受けています。寄付とプロジェクト支出は [Rockxy の公開 Open Collective ページ](https://opencollective.com/rockxy)に記録され、資金の受領と利用状況を透明に確認できます。

| ティア | 支援額 | 支援内容 |
|--------|--------|----------|
| **Backer** | 月額 $5 から | オープンソースの保守、ドキュメント、テスト、リリース |
| **Builder** | 月額 $25 から | リグレッションテスト、パフォーマンス改善、日常的なデバッグワークフロー |
| **Sponsor** | 月額 $100 | プライバシーを重視し、開発者が無料で利用できるツールの長期保守 |
| **Sustaining Sponsor** | 月額 $500 | リリース自動化やプロトコル対応を含む、集中的な保守と製品開発 |

**パートナーシップのお問い合わせ** — 開発者ツール企業、セキュリティ企業、カスタム統合やホワイトラベルソリューションをお探しのエンタープライズチーム：[rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## サポート

- [Open Collective](https://opencollective.com/rockxy/donate) — 透明性のあるプロジェクト予算を通じて Rockxy を支援
- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — Rockxy の開発を支援
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — バグ報告と機能リクエスト
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — 質問とコミュニティチャット
- **メール** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **セキュリティ問題** — 責任ある開示については [SECURITY.md](SECURITY.md) を参照

## ライセンス

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## スター履歴

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Swift、SwiftNIO、SwiftUI、AppKit で構築。</sub>
</p>
