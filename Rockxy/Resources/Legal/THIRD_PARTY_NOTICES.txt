# Third-Party Software Notices

This inventory applies to the public Rockxy Community source edition and to
builds made solely from that source. Component versions are pinned in
`Rockxy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
The final application artifact must be inspected before distribution because
the lockfile alone does not prove which components were embedded.

Complete license and NOTICE texts required by a redistributed build are stored
with unique names under `Rockxy/Resources/Legal/ThirdPartyLicenses/` so Xcode
resource flattening cannot silently replace files with generic names.

## Swift packages

| Component | Version | Revision | Relationship | License |
| --- | --- | --- | --- | --- |
| [swift-nio](https://github.com/apple/swift-nio) | 2.95.0 | `e932d3c4d8f77433c8f7093b5ebcbf91463948a0` | Direct | Apache-2.0; includes llhttp 9.3.0 under MIT |
| [swift-nio-ssl](https://github.com/apple/swift-nio-ssl) | 2.36.0 | `173cc69a058623525a58ae6710e2f5727c663793` | Direct | Apache-2.0; includes BoringSSL snapshot `817ab07e…` |
| [swift-nio-http2](https://github.com/apple/swift-nio-http2) | 1.46.0 | `0f3e54e29c944c2e835ad52159da7d9e1c94ac69` | Direct | Apache-2.0 |
| [swift-certificates](https://github.com/apple/swift-certificates) | 1.18.0 | `24ccdeeeed4dfaae7955fcac9dbf5489ed4f1a25` | Direct | Apache-2.0 |
| [swift-crypto](https://github.com/apple/swift-crypto) | 4.2.0 | `6f70fa9eab24c1fd982af18c281c4525d05e3095` | Direct | Apache-2.0; includes BoringSSL snapshot `0226f304…` |
| [SQLite.swift](https://github.com/stephencelis/SQLite.swift) | 0.16.0 | `964c300fb0736699ce945c9edb56ecd62eba27a3` | Direct | MIT, Copyright © 2014–2015 Stephen Celis |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.1 | `066e75a8b3e99962685d6a90cdd5293ebffd9261` | Direct | Compound permissive license; reproduce the complete upstream LICENSE |
| [swift-asn1](https://github.com/apple/swift-asn1) | 1.5.1 | `810496cf121e525d660cd0ea89a758740476b85f` | Transitive/product | Apache-2.0 |
| [swift-atomics](https://github.com/apple/swift-atomics) | 1.3.0 | `b601256eab081c0f92f059e12818ac1d4f178ff7` | Transitive | Apache-2.0 |
| [swift-collections](https://github.com/apple/swift-collections) | 1.4.0 | `8d9834a6189db730f6264db7556a7ffb751e99ee` | Transitive | Apache-2.0 |
| [swift-system](https://github.com/apple/swift-system) | 1.6.4 | `7c6ad0fc39d0763e0b699210e4124afd5041c5df` | Transitive | Apache-2.0 |

The two BoringSSL snapshots are distinct components. Their complete compound
ISC/OpenSSL/Original SSLeay/MIT-family license texts are preserved separately
at the exact audited revisions.

## Swagger UI

Rockxy vendors `swagger-ui-dist` 5.32.6 for offline OpenAPI HTML export.

- Source: [Swagger UI v5.32.6](https://github.com/swagger-api/swagger-ui/tree/v5.32.6)
- Top-level license: Apache-2.0
- Notice: `swagger-ui`, Copyright 2020–2021 SmartBear Software Inc.
- `normalize.css` 7.0.0: MIT, Copyright © Nicolas Gallagher and Jonathan Neal
- DOMPurify 3.4.0 is used under its Apache-2.0 option.
- The checked-in `swagger-ui-bundle.js.LICENSE.txt` is preserved unchanged and
  records retained notices for bundled JavaScript components.

The minifier companion file is not claimed to be a complete Swagger dependency
SBOM. A release must preserve it and inspect the final vendored bundle.

## Toolchain redistributables

A distributed macOS build may contain Apple/Xcode Swift compatibility
libraries, including `libswiftCompatibilitySpan.dylib`. These are toolchain
redistributables rather than SwiftPM dependencies and must be tracked against
the Xcode license used for the release.

## Distribution gate

Before distributing a build:

1. compare the final app's embedded frameworks and resource bundles with this
   inventory;
2. verify every listed license/NOTICE resource is present in the app;
3. preserve the Swagger companion license beside the vendored JavaScript;
4. update versions and immutable source revisions when `Package.resolved`
   changes; and
5. stop the release for an unknown or incompatible license.

This notice is informational and does not replace the complete license texts.
