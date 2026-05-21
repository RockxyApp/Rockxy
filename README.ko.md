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
  <strong>macOS용 오픈소스, 감사 가능한 HTTP 디버깅 프록시.</strong>
</p>

<p align="center">
  직접 검사하고 빌드하며 신뢰할 수 있는 네이티브 Swift 앱으로 HTTP/HTTPS/WebSocket/GraphQL 트래픽을 가로채고, 검사하고, 수정하세요.<br>
  <a href="#rockxy-vs-대안-도구">Proxyman과 Charles Proxy</a>를 대체하는 local-first, AGPL-3.0 선택지.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="릴리스" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="플랫폼" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="라이선스" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PR 환영" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="후원" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Light.png" alt="macOS에서 실행 중인 Rockxy" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.21.0** — 2026-05-21

### Added

- Improved Compose history so repeated request work is easier to resume and reuse.
- Added a cleaner fresh-request flow in Compose for quickly starting over without carrying old request state forward.
- Standardized keyboard shortcuts across capture, rules, breakpoints, Compose, scripting, and settings, with a searchable Help reference.

### Fixed

- Fixed breakpoint rule persistence so saved interception rules remain available after restarting Rockxy.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## 현재 브랜치 하이라이트

- Developer Setup Hub는 런타임, 브라우저, 클라이언트, 디바이스, 프레임워크, 환경 전반을 대상으로 타깃별 스니펫, 검증 워처, 정직한 가이드를 제공합니다.
- 도메인이나 앱 단위로 SSL Proxying을 켜거나 끌 때 HTTPS 응답 프롬프트, 사이드바 액션, 메인 요청 테이블이 서로 같은 상태를 유지합니다.
- Inspector와 메인 요청 테이블은 스크롤 가능한 단일 행 탭, Query 상단 정렬, 더 명확한 Status/Code 구분, Request/Response 바이트 컬럼, Duration 수정, 실시간 SSL 상태 아이콘으로 한층 더 다듬어졌습니다.

## 기능

**트래픽 캡처** — SwiftNIO 기반 프록시. CONNECT 터널 지원, 호스트별 TLS 인증서 자동 생성, WebSocket 프레임 캡처, GraphQL 작업 자동 감지.

**모든 것을 검사** — JSON 트리 뷰, 16진수 인스펙터, 타이밍 워터폴(DNS/TCP/TLS/TTFB/Transfer), 헤더, 쿠키, 쿼리 파라미터, 인증 정보 — 모두 탭 형식의 인스펙터에서 확인.

**Mock 및 수정** — Map Local(로컬 파일에서 응답 제공), Map Remote(다른 서버로 리다이렉트), Breakpoints(중간에 일시 정지 후 편집), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**로그 상관관계** — macOS 시스템 로그(OSLog)를 캡처하고 타임스탬프로 네트워크 요청과 연결. 각 요청을 보낸 앱 확인.

**플러그인으로 확장** — 샌드박스화된 JavaScriptCore 런타임에서 JavaScript 스크립팅. 커스텀 훅으로 트래픽 검사, 수정, 자동화.

**대규모 처리 설계** — NSTableView 가상 스크롤로 100k+ 요청 처리. 링 버퍼 퇴거, 디스크 body 오프로딩, 배치 UI 업데이트. 지연 없음.

**Developer Setup Hub** — 런타임, 브라우저, 디바이스, 프레임워크, 환경별 설정을 복사 가능한 스니펫, 검증 프로브, 트러블슈팅 노트와 함께 안내합니다.

**Local MCP Bridge** — 내장된 Model Context Protocol 서버를 통해 로컬 MCP 클라이언트가 실시간 트래픽, 규칙, 프록시 상태를 조회할 수 있습니다. 로컬 전용, 토큰 인증, 민감한 데이터는 기본적으로 마스킹.

> 100% 네이티브 macOS. Electron 없음. 웹 뷰 없음. SwiftUI + AppKit + SwiftNIO.

## 빠른 시작

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Xcode에서 빌드하고 실행. 환영 윈도우가 루트 CA 설정, 헬퍼 설치, 프록시 활성화를 안내합니다.

**요구 사항:** macOS 14.0+, Xcode 16+, Swift 5.9

## Rockxy vs. 대안 도구

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **프로젝트 모델** | AGPL-3.0 오픈소스 프로젝트 | 독점 상용 앱 | 독점 상용 앱 |
| **소스 코드** | 공개, 감사 가능, fork 가능 | 비공개 소스 | 비공개 소스 |
| **소스에서 빌드** | 이 저장소에서 Xcode로 무료 빌드 | 공개 소스로는 제공되지 않음 | 공개 소스로는 제공되지 않음 |
| **네이티브 macOS 기반** | Swift + SwiftNIO + SwiftUI/AppKit | 네이티브 macOS 상용 앱 | 크로스 플랫폼 상용 앱 |
| **Local-first 캡처** | 로컬 프록시, 인증서, 헬퍼, 캡처 데이터가 Mac에 유지됨 | 데스크톱 프록시 앱 | 데스크톱 프록시 앱 |
| **개발자 설정 워크플로** | runtime, client, device, framework, environment를 위한 Developer Setup Hub 내장 | 제품별 설정 가이드 | 제품별 설정 가이드 |
| **MCP/local automation bridge** | 내장, 토큰 인증, 기본 마스킹 | 검토한 공개 문서에서 확인되지 않음 | 검토한 공개 문서에서 확인되지 않음 |
| **열린 기여 경로** | 공개 issues, discussions, roadmap, PR | 벤더가 관리하는 제품 | 벤더가 관리하는 제품 |

로드맵 방향: 더 깊은 replay/diff/rules/scripting 워크플로, 향상된 WebSocket 및 GraphQL 검사, gRPC/Protobuf와 HTTP/2 및 HTTP/3 지원 탐색.

## 보안

Rockxy는 네트워크 트래픽을 가로챕니다 — 보안은 기반이지 선택이 아닙니다.

- XPC 헬퍼는 bundle ID만이 아닌 **인증서 체인 비교**로 호출자 검증
- 플러그인은 **샌드박스화된 JavaScriptCore**에서 실행, 5초 타임아웃, 파일시스템/네트워크 접근 불가
- 모든 경계에서 **입력 유효성 검사** — body 크기 제한, URI 제한, regex DoS 방지, 경로 순회 방지
- 로그에서 자격 증명 **자동 마스킹**
- 민감한 파일은 **0o600 권한**으로 저장

취약점 보고는 [SECURITY.md](SECURITY.md)를 참조. 자세한 내용은 [보안 아키텍처](docs/development/security.mdx)를 확인하세요.

## 로드맵

Rockxy의 공개 로드맵은 워크플로 중심이며 고정 날짜를 약속하지 않습니다. 안정성, 네이티브 macOS UX, 디버깅 워크플로, 프로토콜 지원, 문서, 기여자 온보딩에 집중합니다.

- [ROADMAP.md](ROADMAP.md): 공개 엔지니어링 방향의 큰 그림
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): 로드맵 이슈의 실행 현황

## 문서

전체 문서는 [Rockxy Docs](docs/index.mdx)에서 확인 가능:

- [빠른 시작 가이드](docs/quickstart.mdx) — 몇 분 만에 설정
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — 런타임 스니펫, 디바이스 가이드, 검증 프로브, 지원 매트릭스
- [아키텍처](docs/development/architecture.mdx) — 프록시 엔진, Actor 모델, 데이터 플로우
- [보안 모델](docs/development/security.mdx) — 신뢰 경계, XPC 검증, 인증서 관리
- [설계 결정](docs/development/design-decisions.mdx) — SwiftNIO, NSTableView, Actor를 선택한 이유
- [소스에서 빌드](docs/development/building.mdx) — 빌드, 테스트, lint, 디버그
- [코드 스타일](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, 코딩 규칙
- [변경 기록](CHANGELOG.md) — 현재 브랜치 작업과 정식 릴리스 기록

## 기여

모든 종류의 기여를 환영합니다 — 코드, 테스트, 문서, 버그 리포트, UX 피드백.

설정 안내, 코드 스타일, PR 체크리스트는 **[CONTRIBUTING.md](CONTRIBUTING.md)**를 참조하세요.

초보자용 이슈는 [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue)로 표시되어 있습니다. PR을 제출하면 [CLA](CLA.md)에 동의한 것으로 간주합니다.

## 스폰서 및 파트너

Rockxy는 독립 개발자들이 구축하고 유지합니다. 후원금은 지속적인 개발, 보안 감사, 새로운 기능에 사용됩니다.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Rockxy_후원하기-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Rockxy 후원하기" />
  </a>
</p>

| 등급 | 혜택 |
|------|------|
| **Gold Sponsor** | README + 문서 사이트에 로고 게재, 기능 요청 우선, 전용 지원 채널 |
| **Silver Sponsor** | README에 로고 게재, 릴리스 노트에서 감사 표시 |
| **Bronze Sponsor** | README 및 문서에서 감사 표시 |
| **Partner** | 공동 개발, 통합 지원, 향후 기능 조기 접근 |

**파트너십 문의** — 개발자 도구 회사, 보안 기업, 커스텀 통합 또는 화이트라벨 솔루션이 필요한 엔터프라이즈 팀: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## 지원

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — Rockxy 개발 지원
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — 버그 리포트 및 기능 요청
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — 질문 및 커뮤니티 채팅
- **이메일** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **보안 문제** — 책임 있는 공개를 위해 [SECURITY.md](SECURITY.md) 참조

## 라이선스

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## 스타 히스토리

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Swift, SwiftNIO, SwiftUI, AppKit으로 빌드.</sub>
</p>
