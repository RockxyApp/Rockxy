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

## Các Điểm Nổi Bật Trên Nhánh Hiện Tại

- Developer Setup Hub giờ bao phủ runtime, browser, client, device, framework và environment với snippet theo từng target, validation watcher, và guide content trung thực.
- Prompt HTTPS response, action ở sidebar, và request table giờ đồng bộ khi bật hoặc tắt SSL proxying theo domain hoặc app.
- Inspector và main request table đã được polish với tab cuộn ngang, nội dung Query bám đỉnh, tách rõ Status/Code, thêm cột Request/Response bytes, sửa Duration, và icon SSL cập nhật theo trạng thái thật.

## Tính Năng

**Chặn bắt lưu lượng** — Proxy SwiftNIO với CONNECT tunnel, tự động tạo chứng chỉ TLS cho từng host, bắt frame WebSocket, và tự động phát hiện truy vấn GraphQL.

**Kiểm tra mọi thứ** — JSON tree viewer, hex inspector, biểu đồ thời gian (DNS/TCP/TLS/TTFB/Transfer), headers, cookies, query params, auth — tất cả trong inspector dạng tab.

**Mock & Chỉnh sửa** — Map Local (phục vụ từ file), Map Remote (chuyển hướng sang server khác), Breakpoints (tạm dừng và chỉnh sửa giữa chừng), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**Tương quan Log** — Bắt log hệ thống macOS (OSLog) và tương quan với các request mạng theo thời gian. Xem ứng dụng nào gửi từng request.

**Mở rộng bằng Plugin** — Scripting JavaScript trong môi trường JavaScriptCore sandbox. Kiểm tra, chỉnh sửa và tự động hóa lưu lượng bằng hook tùy chỉnh.

**Xây dựng cho quy mô lớn** — NSTableView virtual scrolling xử lý 100k+ request. Ring buffer eviction, lưu body lớn ra đĩa, cập nhật UI theo batch. Không giật lag.

**Developer Setup Hub** — Thiết lập theo runtime, browser, device, framework và environment với snippet có thể copy, validation probe, và troubleshooting note.

**AI-Ready (MCP Server)** — Máy chủ Model Context Protocol tích hợp sẵn cho phép Claude CLI, Claude Desktop và các MCP client khác truy vấn traffic trực tiếp, rule và trạng thái proxy ngay từ chat. Chỉ chạy cục bộ, xác thực bằng token, dữ liệu nhạy cảm được che giấu mặc định.

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
- [x] Máy chủ Model Context Protocol (MCP) cho trợ lý AI (Claude CLI, Claude Desktop)
- [ ] Hỗ trợ HTTP/2 và HTTP/3
- [ ] Proxy thiết bị từ xa (iOS qua USB/Wi-Fi)
- [ ] Chế độ headless cho CI/CD
- [ ] Kiểm tra gRPC / Protocol Buffers
- [ ] Nhóm lỗi và bảng phân tích

## Tài Liệu

Tài liệu đầy đủ tại [Rockxy Docs](docs/index.mdx):

- [Hướng dẫn nhanh](docs/quickstart.mdx) — thiết lập và chạy trong vài phút
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — snippet theo runtime, guide cho device, validation probe và support matrix
- [Kiến trúc](docs/development/architecture.mdx) — proxy engine, actor model, luồng dữ liệu
- [Mô hình bảo mật](docs/development/security.mdx) — ranh giới tin cậy, xác thực XPC, quản lý chứng chỉ
- [Quyết định thiết kế](docs/development/design-decisions.mdx) — tại sao SwiftNIO, NSTableView, actors
- [Build từ mã nguồn](docs/development/building.mdx) — build, test, lint, và debug
- [Phong cách code](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, và quy ước
- [Changelog](CHANGELOG.md) — thay đổi chưa phát hành và các bản phát hành đã gắn tag

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

## Lịch Sử Stars

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Xây dựng bằng Swift, SwiftNIO, SwiftUI, và AppKit.</sub>
</p>
