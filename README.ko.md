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
  <strong>macOS용 오픈소스 HTTP 디버깅 프록시.</strong>
</p>

<p align="center">
  HTTP/HTTPS/WebSocket/GraphQL 트래픽 가로채기, 검사, 수정 — Swift로 네이티브 빌드.<br>
  <a href="#rockxy-vs-대안-도구">Proxyman과 Charles Proxy</a>의 무료, 소스코드 감사 가능한 대안.
</p>

<p align="center">
  <a href="https://github.com/LocNguyenHuu/Rockxy/releases"><img src="https://img.shields.io/github/v/release/LocNguyenHuu/Rockxy?label=release&color=blue" alt="릴리스" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="플랫폼" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="라이선스" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PR 환영" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="후원" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Dark.png" alt="macOS에서 실행 중인 Rockxy" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## 최신 릴리스

**v0.8.0** — 2026-04-16

### 수정

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

### 변경

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

전체 릴리스 기록은 [CHANGELOG.md](CHANGELOG.md)에서 확인하세요.
<!-- END GENERATED: latest-release -->

## 기능

**트래픽 캡처** — SwiftNIO 기반 프록시. CONNECT 터널 지원, 호스트별 TLS 인증서 자동 생성, WebSocket 프레임 캡처, GraphQL 작업 자동 감지.

**모든 것을 검사** — JSON 트리 뷰, 16진수 인스펙터, 타이밍 워터폴(DNS/TCP/TLS/TTFB/Transfer), 헤더, 쿠키, 쿼리 파라미터, 인증 정보 — 모두 탭 형식의 인스펙터에서 확인.

**Mock 및 수정** — Map Local(로컬 파일에서 응답 제공), Map Remote(다른 서버로 리다이렉트), Breakpoints(중간에 일시 정지 후 편집), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**로그 상관관계** — macOS 시스템 로그(OSLog)를 캡처하고 타임스탬프로 네트워크 요청과 연결. 각 요청을 보낸 앱 확인.

**플러그인으로 확장** — 샌드박스화된 JavaScriptCore 런타임에서 JavaScript 스크립팅. 커스텀 훅으로 트래픽 검사, 수정, 자동화.

**대규모 처리 설계** — NSTableView 가상 스크롤로 100k+ 요청 처리. 링 버퍼 퇴거, 디스크 body 오프로딩, 배치 UI 업데이트. 지연 없음.

> 100% 네이티브 macOS. Electron 없음. 웹 뷰 없음. SwiftUI + AppKit + SwiftNIO.

## 빠른 시작

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Xcode에서 빌드하고 실행. 환영 윈도우가 루트 CA 설정, 헬퍼 설치, 프록시 활성화를 안내합니다.

**요구 사항:** macOS 14.0+, Xcode 16+, Swift 5.9

## Rockxy vs. 대안 도구

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **라이선스** | AGPL-3.0 (오픈소스) | 독점 (프리미엄) | 독점 ($50) |
| **소스 코드** | 완전히 감사 가능 | 비공개 | 비공개 |
| **기술** | Swift + SwiftNIO | Swift + AppKit | Java |
| **HTTPS 인터셉트** | 예 | 예 | 예 |
| **WebSocket** | 예 | 예 | 예 |
| **GraphQL 감지** | 예 | 예 | 아니오 |
| **Map Local / Remote** | 예 | 예 | 예 |
| **Breakpoints** | 예 | 예 | 예 |
| **JavaScript 스크립팅** | 예 | 예 | 아니오 |
| **OSLog 상관관계** | 예 | 아니오 | 아니오 |
| **프로세스 식별** | 예 | 예 | 아니오 |
| **요청 비교** | 예 | 예 | 아니오 |
| **HAR 가져오기/내보내기** | 예 | 예 | 아니오 |
| **100k+ 행 성능** | 예 | 예 | 느림 |
| **비밀번호 없는 프록시 설정** | 예 (헬퍼 데몬) | 예 | 아니오 |
| **커뮤니티 기여** | PR 오픈 | 아니오 | 아니오 |

## 보안

Rockxy는 네트워크 트래픽을 가로챕니다 — 보안은 기반이지 선택이 아닙니다.

- XPC 헬퍼는 bundle ID만이 아닌 **인증서 체인 비교**로 호출자 검증
- 플러그인은 **샌드박스화된 JavaScriptCore**에서 실행, 5초 타임아웃, 파일시스템/네트워크 접근 불가
- 모든 경계에서 **입력 유효성 검사** — body 크기 제한, URI 제한, regex DoS 방지, 경로 순회 방지
- 로그에서 자격 증명 **자동 마스킹**
- 민감한 파일은 **0o600 권한**으로 저장

취약점 보고는 [SECURITY.md](SECURITY.md)를 참조. 자세한 내용은 [보안 아키텍처](docs/development/security.mdx)를 확인하세요.

## 로드맵

- [x] HTTP/HTTPS/WebSocket/GraphQL 인터셉트
- [x] Map Local, Map Remote, Breakpoints, Block, Throttle
- [x] JavaScript 플러그인 시스템 (샌드박스 실행)
- [x] HAR 가져오기/내보내기, 네이티브 세션 파일, 요청 비교
- [x] OSLog 상관관계 및 자격 증명 마스킹
- [ ] HTTP/2 및 HTTP/3 지원
- [ ] 원격 디바이스 프록시 (iOS USB/Wi-Fi 경유)
- [ ] CI/CD 파이프라인용 헤드리스 모드
- [ ] gRPC / Protocol Buffers 검사
- [ ] 오류 그룹화 및 분석 대시보드

## 문서

전체 문서는 [Rockxy Docs](docs/index.mdx)에서 확인 가능:

- [빠른 시작 가이드](docs/quickstart.mdx) — 몇 분 만에 설정
- [아키텍처](docs/development/architecture.mdx) — 프록시 엔진, Actor 모델, 데이터 플로우
- [보안 모델](docs/development/security.mdx) — 신뢰 경계, XPC 검증, 인증서 관리
- [설계 결정](docs/development/design-decisions.mdx) — SwiftNIO, NSTableView, Actor를 선택한 이유
- [소스에서 빌드](docs/development/building.mdx) — 빌드, 테스트, lint, 디버그
- [코드 스타일](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, 코딩 규칙

## 기여

모든 종류의 기여를 환영합니다 — 코드, 테스트, 문서, 버그 리포트, UX 피드백.

설정 안내, 코드 스타일, PR 체크리스트는 **[CONTRIBUTING.md](CONTRIBUTING.md)**를 참조하세요.

초보자용 이슈는 [`good first issue`](https://github.com/LocNguyenHuu/Rockxy/labels/good%20first%20issue)로 표시되어 있습니다. PR을 제출하면 [CLA](CLA.md)에 동의한 것으로 간주합니다.

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
- [GitHub Issues](https://github.com/LocNguyenHuu/Rockxy/issues) — 버그 리포트 및 기능 요청
- [GitHub Discussions](https://github.com/LocNguyenHuu/Rockxy/discussions) — 질문 및 커뮤니티 채팅
- **이메일** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **보안 문제** — 책임 있는 공개를 위해 [SECURITY.md](SECURITY.md) 참조

## 라이선스

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

---

<p align="center">
  <sub>Swift, SwiftNIO, SwiftUI, AppKit으로 빌드.</sub>
</p>
