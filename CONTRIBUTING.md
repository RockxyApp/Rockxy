# Contributing

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Setup

You'll need macOS 14.0+, Xcode 16+, [SwiftLint](https://github.com/realm/SwiftLint), and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat).

```bash
git clone https://github.com/RockxyApp/Rockxy.git
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

Rockxy merges accepted external pull requests with a merge commit so the exact
reviewed contributor commit SHAs remain in project history. Squash and rebase
merges are disabled; contributors do not need to change their normal PR flow.

Before opening, check:

- [ ] Tests added or updated
- [ ] `CHANGELOG.md` updated under `[Unreleased]` (skip for unreleased-only fixes)
- [ ] Docs updated in `docs/` if the change affects user-facing behavior
- [ ] User-facing strings localized
- [ ] If string catalogs changed, `python3 .github/tools/validate_xcstrings.py` passes
- [ ] No SwiftLint/SwiftFormat violations
- [ ] If the change touches helper packaging, release scripts, or platform compatibility claims, Intel + Apple Silicon validation was updated or re-run

Mark checklist items that do not apply in the PR description. A translation-only
PR does not need Swift tests, SwiftLint, SwiftFormat, or a changelog entry unless it
also changes Swift code, English source strings, or product behavior.

## Translations

Rockxy ships native Xcode String Catalogs (`Rockxy/Localizable.xcstrings` and
`Rockxy/InfoPlist.xcstrings`); the Git-tracked catalogs are canonical and there is
an app-language picker under **Settings › Appearance › Language**. **System Default**
follows the macOS language; choosing another bundled language updates Rockxy
immediately.

There are three useful ways to contribute:

1. **Report wording:** use the
   [Translation Improvement issue template](https://github.com/RockxyApp/Rockxy/issues/new?template=4-Translation_Improvement.md)
   if you know better wording but do not want to edit the catalogs.
2. **Repair a translation:** a focused PR may update only the affected localized
   value. Small repairs can be made in GitHub or any text editor; Xcode is optional.
3. **Add a language:** use Xcode to add the locale to both catalogs, translate all
   translatable entries, and verify the changed UI in the app.

For a repair, include the locale, affected screen, proposed wording, and a short
reason the wording is better. Useful evidence can be native-speaker knowledge, a
platform terminology reference, a screenshot showing context or truncation, or a
clear explanation of the technical meaning. Do not include private captured traffic
in screenshots.

Keep non-translatable details unchanged: placeholders, protocol names, header
names, URLs, file extensions, MIME types, code fragments, product names, and
keyboard shortcuts. Machine translation may help with a draft, but bulk-generated
translations must be reviewed by someone fluent in the target language before the
PR is marked ready.

Preserve every placeholder and plural/format token, then validate before pushing:

```bash
python3 .github/tools/validate_xcstrings.py
```

A maintainer reviews every `.xcstrings` change; this gates review, not authorship.
See [`docs/development/localization.mdx`](docs/development/localization.mdx) for the
complete GitHub/text-editor workflow, Xcode workflow, language identifiers, runtime
checks, catalog hygiene, and placeholder rules.

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

Open a [GitHub issue](https://github.com/RockxyApp/Rockxy/issues) with your macOS version, Rockxy version, and reproduction steps.
Issues are for actionable bug reports and feature requests. For questions and setup help, use
[GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions).

## Contributor License Agreement

All contributors must accept the current
[Individual Contributor License Agreement v2.0](legal/cla/ICLA-v2.0.md) before
their pull request can be merged. When you open a PR, the `Rockxy CLA` check
posts a comment asking each contributor to accept. Read the ICLA, then post this
exact comment on the pull request:

```text
I have read and agree to the Rockxy ICLA v2.0
```

The `Rockxy CLA` status turns green once every contributor on the PR has
accepted. Accepting the ICLA v2.0 covers the contributions in that pull request
and your later Contributions while that version is in effect; a signature from a
different, later pull request does not cover an earlier-opened one, and a later
material agreement version requires new acceptance. Acceptance is recorded as an
append-only-by-workflow evidence record on the dedicated `cla-signatures` branch.

You retain copyright in your Contribution. The ICLA gives the Project Owner the
rights needed to publish it in the AGPL Community source edition and to use it
in separately licensed Rockxy distributions. Contributions incorporated into
the public source edition remain available there under its public source
license.

If your employer or another organization owns or controls your Contribution,
an authorized representative must also execute the
[Corporate Contributor License Agreement](legal/cla/CCLA-v1.0.md). Contact
`rockxyapp@gmail.com` before signing or submitting employer-owned work. This
organizational authorization is reviewed manually; the automated `Rockxy CLA`
check verifies individual ICLA coverage and does not replace an executed CCLA.

Pull requests from contributors who have not signed the CLA will be blocked
from merging.

## License

Contributions incorporated into this public source edition are available under
[GNU Affero General Public License v3.0 or later](LICENSE), subject to the
additional rights granted in the contributor agreement.
