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
  <strong>HTTP debugging proxy mã nguồn mở cho macOS.</strong>
</p>

<p align="center">
  Chặn bắt, kiểm tra và chỉnh sửa lưu lượng HTTP/HTTPS/WebSocket/GraphQL — xây dựng hoàn toàn bằng Swift.<br>
  Giải pháp thay thế miễn phí, có thể kiểm tra mã nguồn cho <a href="#rockxy-vs-các-giải-pháp-khác">Proxyman và Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/LocNguyenHuu/Rockxy/releases"><img src="https://img.shields.io/github/v/release/LocNguyenHuu/Rockxy?label=release&color=blue" alt="Phiên bản" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Nền tảng" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Giấy phép" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="Chào đón PR" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Tài trợ" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Dark.png" alt="Rockxy chạy trên macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Bản Phát Hành Mới Nhất

**v0.7.1** — 2026-04-15

### Đã Sửa

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

### Đã Thay Đổi

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

Xem [CHANGELOG.md](CHANGELOG.md) để biết toàn bộ lịch sử phát hành.
<!-- END GENERATED: latest-release -->

## Tính Năng

**Chặn bắt lưu lượng** — Proxy SwiftNIO với CONNECT tunnel, tự động tạo chứng chỉ TLS cho từng host, bắt frame WebSocket, và tự động phát hiện truy vấn GraphQL.

**Kiểm tra mọi thứ** — JSON tree viewer, hex inspector, biểu đồ thời gian (DNS/TCP/TLS/TTFB/Transfer), headers, cookies, query params, auth — tất cả trong inspector dạng tab.

**Mock & Chỉnh sửa** — Map Local (phục vụ từ file), Map Remote (chuyển hướng sang server khác), Breakpoints (tạm dừng và chỉnh sửa giữa chừng), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**Tương quan Log** — Bắt log hệ thống macOS (OSLog) và tương quan với các request mạng theo thời gian. Xem ứng dụng nào gửi từng request.

**Mở rộng bằng Plugin** — Scripting JavaScript trong môi trường JavaScriptCore sandbox. Kiểm tra, chỉnh sửa và tự động hóa lưu lượng bằng hook tùy chỉnh.

**Xây dựng cho quy mô lớn** — NSTableView virtual scrolling xử lý 100k+ request. Ring buffer eviction, lưu body lớn ra đĩa, cập nhật UI theo batch. Không giật lag.

> 100% native macOS. Không Electron. Không web view. SwiftUI + AppKit + SwiftNIO.

## Bắt Đầu Nhanh

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Build và chạy trong Xcode. Cửa sổ Welcome sẽ hướng dẫn bạn cài đặt root CA, helper tool, và kích hoạt proxy.

**Yêu cầu:** macOS 14.0+, Xcode 16+, Swift 5.9

## Rockxy vs. Các Giải Pháp Khác

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Giấy phép** | AGPL-3.0 (mã nguồn mở) | Độc quyền (freemium) | Độc quyền ($50) |
| **Mã nguồn** | Hoàn toàn có thể kiểm tra | Đóng | Đóng |
| **Công nghệ** | Swift + SwiftNIO | Swift + AppKit | Java |
| **Chặn bắt HTTPS** | Có | Có | Có |
| **WebSocket** | Có | Có | Có |
| **Phát hiện GraphQL** | Có | Có | Không |
| **Map Local / Remote** | Có | Có | Có |
| **Breakpoints** | Có | Có | Có |
| **JavaScript scripting** | Có | Có | Không |
| **Tương quan OSLog** | Có | Không | Không |
| **Nhận diện process** | Có | Có | Không |
| **So sánh request** | Có | Có | Không |
| **Import/export HAR** | Có | Có | Không |
| **Hiệu suất 100k+ dòng** | Có | Có | Chậm |
| **Cài proxy không cần mật khẩu** | Có (helper daemon) | Có | Không |
| **Đóng góp cộng đồng** | Mở PR | Không | Không |

## Bảo Mật

Rockxy chặn bắt lưu lượng mạng — bảo mật là nền tảng, không phải tùy chọn.

- XPC helper xác thực caller bằng **so sánh chuỗi chứng chỉ**, không chỉ bundle ID
- Plugin chạy trong **JavaScriptCore sandbox** với timeout 5 giây, không truy cập filesystem/network
- **Kiểm tra đầu vào** trên mọi ranh giới — giới hạn kích thước body, giới hạn URI, chống regex DoS, chống path traversal
- Thông tin xác thực **tự động che giấu** trong log
- File nhạy cảm được lưu với **quyền 0o600**

Báo cáo lỗ hổng qua [SECURITY.md](SECURITY.md). Xem [kiến trúc bảo mật đầy đủ](docs/development/security.mdx) để biết chi tiết.

## Lộ Trình

- [x] Chặn bắt HTTP/HTTPS/WebSocket/GraphQL
- [x] Map Local, Map Remote, Breakpoints, Block, Throttle
- [x] Hệ thống plugin JavaScript với sandbox
- [x] Import/export HAR, file session, so sánh request
- [x] Tương quan OSLog và che giấu thông tin xác thực
- [ ] Hỗ trợ HTTP/2 và HTTP/3
- [ ] Proxy thiết bị từ xa (iOS qua USB/Wi-Fi)
- [ ] Chế độ headless cho CI/CD
- [ ] Kiểm tra gRPC / Protocol Buffers
- [ ] Nhóm lỗi và bảng phân tích

## Tài Liệu

Tài liệu đầy đủ tại [Rockxy Docs](docs/index.mdx):

- [Hướng dẫn nhanh](docs/quickstart.mdx) — thiết lập và chạy trong vài phút
- [Kiến trúc](docs/development/architecture.mdx) — proxy engine, actor model, luồng dữ liệu
- [Mô hình bảo mật](docs/development/security.mdx) — ranh giới tin cậy, xác thực XPC, quản lý chứng chỉ
- [Quyết định thiết kế](docs/development/design-decisions.mdx) — tại sao SwiftNIO, NSTableView, actors
- [Build từ mã nguồn](docs/development/building.mdx) — build, test, lint, và debug
- [Phong cách code](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, và quy ước

## Đóng Góp

Chào đón mọi đóng góp — code, test, tài liệu, báo lỗi, và phản hồi UX.

Xem **[CONTRIBUTING.md](CONTRIBUTING.md)** để biết hướng dẫn cài đặt, phong cách code, và checklist PR đầy đủ.

Các issue dành cho người mới được gắn nhãn [`good first issue`](https://github.com/LocNguyenHuu/Rockxy/labels/good%20first%20issue). Khi mở PR, bạn đồng ý với [CLA](CLA.md).

## Nhà Tài Trợ & Đối Tác

Rockxy được xây dựng và duy trì bởi các developer độc lập. Tài trợ giúp trang trải phát triển liên tục, kiểm tra bảo mật, và các tính năng mới.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Tài_trợ_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Tài trợ Rockxy" />
  </a>
</p>

| Hạng | Quyền lợi |
|------|-----------|
| **Gold Sponsor** | Logo trên README + trang docs, ưu tiên yêu cầu tính năng, kênh hỗ trợ trực tiếp |
| **Silver Sponsor** | Logo trên README, được ghi nhận trong ghi chú phát hành |
| **Bronze Sponsor** | Được ghi nhận trên README và docs |
| **Partner** | Đồng phát triển, hỗ trợ tích hợp, truy cập sớm các tính năng sắp ra mắt |

**Liên hệ hợp tác** — các công ty developer tools, công ty bảo mật, và đội ngũ enterprise cần tích hợp tùy chỉnh hoặc giải pháp white-label: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Hỗ Trợ

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — hỗ trợ phát triển Rockxy
- [GitHub Issues](https://github.com/LocNguyenHuu/Rockxy/issues) — báo lỗi và yêu cầu tính năng
- [GitHub Discussions](https://github.com/LocNguyenHuu/Rockxy/discussions) — câu hỏi và thảo luận cộng đồng
- **Email** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Vấn đề bảo mật** — xem [SECURITY.md](SECURITY.md) để báo cáo có trách nhiệm

## Giấy Phép

[GNU Affero General Public License v3.0](LICENSE) — Bản quyền 2024–2026 Rockxy Contributors.

---

<p align="center">
  <sub>Xây dựng bằng Swift, SwiftNIO, SwiftUI, và AppKit.</sub>
</p>
