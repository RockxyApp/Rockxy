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
## 最新リリース

**v0.7.1** — 2026-04-15

### 修正

- Align live-history cap with actor accounting, guard clearSession reentry, clear ruleLoadTask on completion
- Finalize upstream normalization cleanup
- Cross-suite RuleEngine serialization via RuleTestLock and clearSession regression test
- Replace fire-and-forget engine restore with awaited cleanup in rule tests
- Eliminate MainActor starvation in rule tests and close clearSession generation gap
- Synchronous sessionGeneration in clearSession, atomic rule store writes, and detached syncAll disk I/O
- ClearSession generation sync, deterministic rollback polls, and test isolation
- ClearSession race, rule test isolation, and docs product-name normalization
- Testable ConnectionValidator seam with accept-path and audit-token coverage
- Generation-safe accepted-count reporting and audit-token SecCode extraction seam
- Real caller-validation entrypoint, generation-safe session clear, and bridge defaults isolation
- Real caller-validation tests, correct history accounting, and full plugin environment normalization
- Session clear race, plugin environment normalization, and test serialization
- Hermetic plugin test isolation, real runtime transition test, and error-status assertion
- Refresh VM on failed enable, isolate plugin fixtures, guard small-buffer eviction, and tighten signing tests
- Use Task.sleep instead of Task.yield for VM rollback test stability
- Single-flight rule loading via ensureRulesLoaded()
- Harden plugin/rule race conditions, quota logic, and error surfacing
- Short-circuit re-enable for already-enabled plugins
- Snapshot plugin IDs across await and fix exclusive netcond quota
- Rule loading race and exclusive network-condition quota bypass
- Make quota paths truly atomic and isolate gate policy from tests
- Address final review findings for gates, bulk replace, and selection
- Make script enable atomic and propagate missing-plugin errors
- Address review findings for policy gate correctness
- Make RuleQuotaTests immune to cross-suite singleton state

### 変更

- Correct batched-update interval to 100ms and qualify large-body storage path per build
- Validate loadInitialRules reuses in-flight ruleLoadTask and clears it on completion
- Harden plugin env cleanup, dedupe allowed-caller constants, remove hardcoded audit_token_t ObjC encoding, guarantee rule lock release
- Delegate RockxyIdentity bundle init to infoDictionary init
- Tighten .gitignore entries, fix README badges, correct architecture and security diagrams
- Exercise real audit-token revalidation branch in isValidCaller
- Full isValidCaller accept path and NSValue audit-token branch via TestXPCConnection
- Stabilize ConnectionValidator tests and remove infeasible XPC harness
- Direct ConnectionValidator coverage via Shared/ relocation
- Prove enable transition through real default-init production singleton
- Prove default-init VMs load consistent state through real production path
- Restore default-init wiring coverage via pluginManagerIdentity seam
- Isolate default-wiring plugin test from real app-support state
- Complete helper signing diagnostics, toggle rollback, and engine-state assertions
- Strengthen actor eviction, default VM wiring, and concurrent enable postconditions
- Cover default plugin runtime wiring
- Cover coordinator rule wiring, VM quota rollback, and script default paths
- Extract shared temp plugin helpers to TestFixtures
- Remove dead SessionStore coupling from eviction and strengthen history retention tests
- Add helper caller validation matrix
- Annotate identity fallbacks and bind tests to live config
- Add identity and helper trust matrix coverage
- Unify ScriptPluginManager ownership and add script quota
- Cap live history buffer at policy-defined limit
- Add RulePolicyGate and route rule mutations through it
- Add domain favorites capacity at coordinator boundary
- Inject workspace capacity via init
- Remove edition leakage and introduce AppPolicy
- Split family config from product identity

完全なリリース履歴は [CHANGELOG.md](CHANGELOG.md) を参照してください。
<!-- END GENERATED: latest-release -->

## 機能

**トラフィックキャプチャ** — SwiftNIO ベースのプロキシ。CONNECT トンネル対応、ホストごとの TLS 証明書自動生成、WebSocket フレームキャプチャ、GraphQL オペレーション自動検出。

**あらゆるものを検査** — JSON ツリービュー、16 進インスペクタ、タイミングウォーターフォール（DNS/TCP/TLS/TTFB/Transfer）、ヘッダー、Cookie、クエリパラメータ、認証情報 — すべてタブ式インスペクタに集約。

**モックと変更** — Map Local（ローカルファイルからレスポンス提供）、Map Remote（別サーバーへリダイレクト）、Breakpoints（途中で一時停止して編集）、Block、Throttle、Modify Headers、Allow List、Bypass Proxy。

**ログ相関** — macOS システムログ（OSLog）をキャプチャし、タイムスタンプでネットワークリクエストと相関。各リクエストを発行したアプリを確認。

**プラグインで拡張** — サンドボックス化された JavaScriptCore ランタイムでの JavaScript スクリプティング。カスタムフックでトラフィックを検査、変更、自動化。

**大規模対応** — NSTableView の仮想スクロールで 100k+ リクエストに対応。リングバッファ淘汰、ディスクへの Body オフロード、バッチ UI 更新。遅延なし。

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
- [ ] HTTP/2 および HTTP/3 サポート
- [ ] リモートデバイスプロキシ（iOS USB/Wi-Fi 経由）
- [ ] CI/CD パイプライン用ヘッドレスモード
- [ ] gRPC / Protocol Buffers インスペクション
- [ ] エラーグルーピングと分析ダッシュボード

## ドキュメント

完全なドキュメントは [Rockxy Docs](docs/index.mdx) で利用可能：

- [クイックスタートガイド](docs/quickstart.mdx) — 数分でセットアップ
- [アーキテクチャ](docs/development/architecture.mdx) — プロキシエンジン、Actor モデル、データフロー
- [セキュリティモデル](docs/development/security.mdx) — 信頼境界、XPC バリデーション、証明書管理
- [設計判断](docs/development/design-decisions.mdx) — SwiftNIO、NSTableView、Actor を選んだ理由
- [ソースからビルド](docs/development/building.mdx) — ビルド、テスト、lint、デバッグ
- [コードスタイル](docs/development/code-style.mdx) — SwiftLint、SwiftFormat、コーディング規約

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

---

<p align="center">
  <sub>Swift、SwiftNIO、SwiftUI、AppKit で構築。</sub>
</p>
