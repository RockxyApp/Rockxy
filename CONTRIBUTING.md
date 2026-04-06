# Contributing

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Setup

You'll need macOS 14.0+, Xcode 16+, [SwiftLint](https://github.com/realm/SwiftLint), and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat).

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
git checkout develop
```

Build:

```bash
xcodebuild -project Rockxy.xcodeproj -scheme Rockxy -configuration Debug build
```

Run tests:

```bash
xcodebuild -project Rockxy.xcodeproj -scheme Rockxy test
```

## Code Style

`.swiftlint.yml` and `.swiftformat` are the source of truth. The short version:

- 4-space indentation, 120-char line length target
- Explicit access control (`private`, `internal`, `public`)
- No force unwraps or force casts. Use `guard let`, `if let`, `as?`
- `String(localized:)` for user-facing strings. SwiftUI view literals auto-localize
- OSLog only, no `print()`

Run both before committing:

```bash
swiftlint lint --strict
swiftformat .
```

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), single line, no body.

```
feat: add WebSocket frame inspector
fix: prevent crash on large response body
docs: update HTTPS interception guide
```

## Branch Naming

Branch off `develop`:

- `feat/add-grpc-support`
- `fix/proxy-connection-leak`
- `docs/update-quickstart`

## Pull Requests

All pull requests must target the **`develop`** branch. One change per PR. Make sure tests pass and lint is clean. Link related issues.

Before opening, check:

- [ ] Tests added or updated
- [ ] `CHANGELOG.md` updated under `[Unreleased]` (skip for unreleased-only fixes)
- [ ] Docs updated in `docs/` if the change affects user-facing behavior
- [ ] User-facing strings localized
- [ ] No SwiftLint/SwiftFormat violations
- [ ] If the change touches helper packaging, release scripts, or platform compatibility claims, Intel + Apple Silicon validation was updated or re-run

## Project Layout

```
Rockxy/                # App source (Core/, Views/, Models/, ViewModels/, etc.)
  Core/                # Proxy engine, certificates, rules, log engine, analytics, storage
  Views/               # SwiftUI views
  Models/              # Data structures
RockxyTests/           # Tests
docs/                  # Mintlify docs site
```

## Reporting Bugs

Open a [GitHub issue](https://github.com/LocNguyenHuu/Rockxy/issues) with your macOS version, Rockxy version, and reproduction steps.

## Contributor License Agreement

All contributors must sign the [Contributor License Agreement](CLA.md) before
their pull request can be merged. When you open your first PR, the CLA Assistant
bot will post a comment with instructions. Reply with the required phrase to
sign. This is a one-time process — once signed, all your future PRs are
automatically approved.

Pull requests from contributors who have not signed the CLA will be blocked
from merging.

## License

Contributions are licensed under [GNU Affero General Public License v3.0](LICENSE).
