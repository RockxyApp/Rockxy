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
  <strong>macOS 向けオープンソース HTTP デバッグプロキシ。</strong>
</p>

<p align="center">
  HTTP/HTTPS/WebSocket/GraphQL トラフィックの傍受、検査、変更 — Swift でネイティブに構築。<br>
  <a href="#rockxy-vs-他のツール">Proxyman と Charles Proxy</a> の無料でソースコード監査可能な代替ツール。
</p>

<p align="center">
  <a href="https://github.com/LocNguyenHuu/Rockxy/releases"><img src="https://img.shields.io/github/v/release/LocNguyenHuu/Rockxy?label=release&color=blue" alt="リリース" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="プラットフォーム" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="ライセンス" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PR 歓迎" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="スポンサー" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Dark.png" alt="macOS で動作中の Rockxy" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.11.0** — 2026-04-25

### Added

- Sparkle-powered automatic updates for signed public releases.
- Bundled Rockxy MCP support for local developer-tool integrations.
- Rockxy Pro activation and entitlement-aware upgrade foundations.

### Fixed

- Improved paid-license activation recovery and product validation reliability.
- Closed release-readiness gaps around production licensing configuration and update metadata.
- Fixed release signing settings required for Apple notarization and Gatekeeper acceptance.

### Changed

- Hardened the release pipeline with production signing, notarization, stapling, checksum, and update-feed validation.
- Refreshed public documentation, localized README content, and release metadata for the 0.11.0 release.
- Improved Xcode project and build configuration reproducibility for fresh checkouts.

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

**AI-Ready (MCP Server)** — 内蔵の Model Context Protocol サーバーにより、Claude CLI、Claude Desktop、その他の MCP クライアントからチャット上でライブトラフィック、ルール、プロキシ状態を直接クエリできます。ローカル専用、トークン認証、機密データはデフォルトでマスキング。

> 100% ネイティブ macOS。Electron なし。Web ビューなし。SwiftUI + AppKit + SwiftNIO。

## クイックスタート

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Xcode でビルドして実行。ウェルカムウィンドウがルート CA のセットアップ、ヘルパーのインストール、プロキシの有効化をガイドします。

**要件：** macOS 14.0+、Xcode 16+、Swift 5.9

## Rockxy vs. 他のツール

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **ライセンス** | AGPL-3.0（オープンソース） | プロプライエタリ（フリーミアム） | プロプライエタリ（$50） |
| **ソースコード** | 完全に監査可能 | クローズド | クローズド |
| **技術** | Swift + SwiftNIO | Swift + AppKit | Java |
| **HTTPS インターセプト** | あり | あり | あり |
| **WebSocket** | あり | あり | あり |
| **GraphQL 検出** | あり | あり | なし |
| **Map Local / Remote** | あり | あり | あり |
| **Breakpoints** | あり | あり | あり |
| **JavaScript スクリプティング** | あり | あり | なし |
| **OSLog 相関** | あり | なし | なし |
| **プロセス識別** | あり | あり | なし |
| **リクエスト差分** | あり | あり | なし |
| **HAR インポート/エクスポート** | あり | あり | なし |
| **100k+ 行のパフォーマンス** | あり | あり | 低速 |
| **パスワード不要のプロキシ設定** | あり（ヘルパーデーモン） | あり | なし |
| **コミュニティ貢献** | PR 受付中 | なし | なし |

## セキュリティ

Rockxy はネットワークトラフィックを傍受します — セキュリティは基盤であり、オプションではありません。

- XPC ヘルパーは bundle ID だけでなく、**証明書チェーン比較**で呼び出し元を検証
- プラグインは**サンドボックス化された JavaScriptCore** で実行、5 秒タイムアウト、ファイルシステム/ネットワークアクセス不可
- すべての境界で**入力バリデーション** — Body サイズ上限、URI 制限、正規表現 DoS 防止、パストラバーサル防止
- ログ内の認証情報を**自動的にマスキング**
- 機密ファイルは **0o600 パーミッション**で保存

脆弱性の報告は [SECURITY.md](SECURITY.md) を参照。詳細は[セキュリティアーキテクチャ](docs/development/security.mdx)をご覧ください。

## ロードマップ

- [x] HTTP/HTTPS/WebSocket/GraphQL インターセプト
- [x] Map Local、Map Remote、Breakpoints、Block、Throttle
- [x] JavaScript プラグインシステム（サンドボックス実行）
- [x] HAR インポート/エクスポート、ネイティブセッションファイル、リクエスト差分
- [x] OSLog 相関と認証情報マスキング
- [x] AI アシスタント向け Model Context Protocol (MCP) サーバー（Claude CLI、Claude Desktop）
- [ ] HTTP/2 および HTTP/3 サポート
- [ ] リモートデバイスプロキシ（iOS USB/Wi-Fi 経由）
- [ ] CI/CD パイプライン用ヘッドレスモード
- [ ] gRPC / Protocol Buffers インスペクション
- [ ] エラーグルーピングと分析ダッシュボード

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

初心者向けの issue には [`good first issue`](https://github.com/LocNguyenHuu/Rockxy/labels/good%20first%20issue) ラベルが付いています。PR を送ることで [CLA](CLA.md) に同意したものとみなされます。

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
- [GitHub Issues](https://github.com/LocNguyenHuu/Rockxy/issues) — バグ報告と機能リクエスト
- [GitHub Discussions](https://github.com/LocNguyenHuu/Rockxy/discussions) — 質問とコミュニティチャット
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
  <sub>Swift、SwiftNIO、SwiftUI、AppKit で構築。</sub>
</p>
