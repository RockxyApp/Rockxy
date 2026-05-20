<p align="center">
  <img src="docs/logo/logo.png" alt="Rockxy" width="128" />
</p>

<h1 align="center">Rockxy</h1>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.vi.md">Tiếng Việt</a> |
  <a href="README.zh.md">中文</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a> |
  <a href="README.fr.md">Français</a> |
  <a href="README.de.md">Deutsch</a>
</p>

<p align="center">
  <strong>macOS 向けのオープンソースで監査可能な HTTP デバッグプロキシ。</strong>
</p>

<p align="center">
  検査・ビルド・信頼できるネイティブ Swift アプリで、HTTP/HTTPS/WebSocket/GraphQL トラフィックを傍受、検査、変更。<br>
  <a href="#rockxy-vs-他のツール">Proxyman と Charles Proxy</a> に代わる local-first、AGPL-3.0 の選択肢。
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="リリース" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="プラットフォーム" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="ライセンス" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PR 歓迎" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="スポンサー" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Light.png" alt="macOS で動作中の Rockxy" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.20.1** — 2026-05-20

### Fixed

- Fixed Map Remote edge cases so rewritten requests preserve expected paths, queries, and upstream routing more reliably.
- Preserved request table scroll position when selection changes, reducing jumpiness during review.
- Improved Modify Headers editor contrast and persistence for clearer, more reliable rule editing.
- Hardened Breakpoints queue handling, persistence, and table layout for smoother interception workflows.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## 現在のブランチのハイライト

- Developer Setup Hub は、ランタイム、ブラウザ、クライアント、デバイス、フレームワーク、環境を対象に、ターゲット別スニペット、検証ウォッチャー、正直なガイド内容をまとめて提供します。
- ドメインまたはアプリ単位で SSL Proxying を有効化・無効化したとき、HTTPS レスポンスプロンプト、サイドバー操作、メインのリクエストテーブルが同期するようになりました。
- Inspector とメインのリクエストテーブルは、横スクロール可能なタブ、Query の上寄せ表示、Status/Code の明確な分離、Request/Response バイト列、Duration 修正、リアルタイム SSL 状態アイコンでさらに磨かれました。

## 機能

**トラフィックキャプチャ** — SwiftNIO ベースのプロキシ。CONNECT トンネル対応、ホストごとの TLS 証明書自動生成、WebSocket フレームキャプチャ、GraphQL オペレーション自動検出。

**あらゆるものを検査** — JSON ツリービュー、16 進インスペクタ、タイミングウォーターフォール（DNS/TCP/TLS/TTFB/Transfer）、ヘッダー、Cookie、クエリパラメータ、認証情報 — すべてタブ式インスペクタに集約。

**モックと変更** — Map Local（ローカルファイルからレスポンス提供）、Map Remote（別サーバーへリダイレクト）、Breakpoints（途中で一時停止して編集）、Block、Throttle、Modify Headers、Allow List、Bypass Proxy。

**ログ相関** — macOS システムログ（OSLog）をキャプチャし、タイムスタンプでネットワークリクエストと相関。各リクエストを発行したアプリを確認。

**プラグインで拡張** — サンドボックス化された JavaScriptCore ランタイムでの JavaScript スクリプティング。カスタムフックでトラフィックを検査、変更、自動化。

**大規模対応** — NSTableView の仮想スクロールで 100k+ リクエストに対応。リングバッファ淘汰、ディスクへの Body オフロード、バッチ UI 更新。遅延なし。

**Developer Setup Hub** — ランタイム、ブラウザ、デバイス、フレームワーク、環境ごとのセットアップを、コピー可能なスニペット、検証プローブ、トラブルシュートノート付きで案内します。

**Local MCP Bridge** — 内蔵の Model Context Protocol サーバーにより、ローカル MCP クライアントからライブトラフィック、ルール、プロキシ状態をクエリできます。ローカル専用、トークン認証、機密データはデフォルトでマスキング。

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

ロードマップの方向性: より深い replay/diff/rules/scripting ワークフロー、WebSocket と GraphQL 検査の改善、gRPC/Protobuf と HTTP/2・HTTP/3 サポートの探索。

## セキュリティ

Rockxy はネットワークトラフィックを傍受します — セキュリティは基盤であり、オプションではありません。

- XPC ヘルパーは bundle ID だけでなく、**証明書チェーン比較**で呼び出し元を検証
- プラグインは**サンドボックス化された JavaScriptCore** で実行、5 秒タイムアウト、ファイルシステム/ネットワークアクセス不可
- すべての境界で**入力バリデーション** — Body サイズ上限、URI 制限、正規表現 DoS 防止、パストラバーサル防止
- ログ内の認証情報を**自動的にマスキング**
- 機密ファイルは **0o600 パーミッション**で保存

脆弱性の報告は [SECURITY.md](SECURITY.md) を参照。詳細は[セキュリティアーキテクチャ](docs/development/security.mdx)をご覧ください。

## ロードマップ

Rockxy の公開ロードマップはワークフロー指向で、固定日程の約束ではありません。信頼性、ネイティブ macOS UX、デバッグワークフロー、プロトコル対応、ドキュメント、コントリビューターのオンボーディングに焦点を当てています。

- [ROADMAP.md](ROADMAP.md)：高レベルの公開エンジニアリング方針
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1)：ロードマップ対象 issue の実行状況

## ドキュメント

完全なドキュメントは [Rockxy Docs](docs/index.mdx) で利用可能：

- [クイックスタートガイド](docs/quickstart.mdx) — 数分でセットアップ
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — ランタイム向けスニペット、デバイスガイド、検証プローブ、サポートマトリクス
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
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Rockxy_をスポンサー-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Rockxy をスポンサー" />
  </a>
</p>

| ティア | 特典 |
|--------|------|
| **Gold Sponsor** | README + ドキュメントサイトにロゴ掲載、機能リクエスト優先、専用サポートチャンネル |
| **Silver Sponsor** | README にロゴ掲載、リリースノートで謝辞 |
| **Bronze Sponsor** | README とドキュメントで謝辞 |
| **Partner** | 共同開発、インテグレーションサポート、今後の機能への早期アクセス |

**パートナーシップのお問い合わせ** — 開発者ツール企業、セキュリティ企業、カスタム統合やホワイトラベルソリューションをお探しのエンタープライズチーム：[rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## サポート

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
