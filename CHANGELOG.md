# Changelog

All notable changes to Rockxy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added

### Fixed

### Changed

- Added a Star History chart to all README translations.

## [0.11.0] - 2026-04-25

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

## [0.10.0] - 2026-04-21

### Added

- Developer Setup Hub: dedicated rows for `Postman`, `Insomnia`, and `Paw` under **Browsers & Clients**, each with its own proxy + certificate workflow.
- Developer Setup Hub: `tvOS / watchOS` and `Vision Pro` rows under **Devices**, documented as iOS-class guide-only targets with honest limitations.
- Developer Setup Hub: guide content for `iOS Device`, `iOS Simulator`, `Android Device`, `Android Emulator`, `Flutter`, and `React Native` — bind/listen, certificate trust, and platform-specific caveats (Android network-security-config, iOS simulator trust, Metro restarts).
- Developer Setup Hub: validated manual snippets + httpbin validation watcher for eight additional targets — `Java VMs` (keytool import + HttpClient sample), `Firefox` (Network Settings + authority-store import + cURL verification), `Postman`, `Insomnia`, and `Paw` (proxy + CA settings snippet + cURL verification), `Docker` (throwaway `docker run` probe mounting the CA via `host.docker.internal`), `ElectronJS` (`--proxy-server` CLI flag and `session.setProxy` main-process snippet, both with `NODE_EXTRA_CA_CERTS`), and `Next.js` (App Router route handler with `NODE_EXTRA_CA_CERTS` + `HTTPS_PROXY` for `next dev`).

### Fixed

- MCP Settings: config JSON no longer shows escaped forward slashes (`\/`) in the `command` path — output now matches standard local JSON configuration files.
- SSL Proxying controls: the encrypted HTTPS response prompt, sidebar actions, and the main request table now stay in sync when enabling or disabling interception by domain or app.
- Request table: CONNECT tunnel rows no longer show placeholder request/response byte counts, and duration now falls back to measured tunnel timing when detailed timing data is unavailable.

### Changed

- Developer Setup Hub: removed the combined `HTTP Clients` row in favor of individual client targets; the neutrality test now allows `Vision Pro` as a proper noun while still rejecting standalone packaging terms.
- Developer Setup Hub: promoted `Java VMs`, `Firefox`, `Postman`, `Insomnia`, `Paw`, `Docker`, `ElectronJS`, and `Next.js` from `guideOnly` to `availableNow` — each now ships a real snippet path with the in-app validation watcher instead of just guide tips.
- Inspector: request and response tabs now use a single-line scrolling tab strip, and short tabs such as Query stay top-aligned in both right and bottom inspector layouts.
- Request table: added `Status`, `Request`, `Response`, and `SSL` columns, restored the `ID` header, and made the SSL icon reflect effective interception state instead of URL scheme alone.

## [0.9.0] - 2026-04-18

### Added

- MCP Server: embedded Model Context Protocol (MCP 2025-11-25) backend — exposes proxy traffic, rules, and status via JSON-RPC 2.0 over a local HTTP server with token-based authentication.
- MCP Server: 10 read-only tools — `get_version`, `get_proxy_status`, `get_certificate_status`, `get_recent_flows`, `get_flow_detail`, `search_flows`, `filter_flows`, `export_flow_curl`, `list_rules`, `get_ssl_proxying_list`.
- MCP Server: `rockxy-mcp` stdio CLI binary bundled in the app for standard MCP stdio transport with automatic session tracking.
- MCP Server: privacy-first redaction — sensitive headers, URL query parameters, and body fields (JSON, form-encoded, XML, plain-text Bearer tokens) redacted by default. Live toggle without server restart.
- MCP Server: Settings > MCP tab with enable/disable toggle, running status indicator, copyable connection config, and redaction privacy controls.
- MCP Server: auto-starts on app launch when previously enabled; survives Settings window close; falls back to SessionStore when main window is closed.

### Changed

- MCP Server: initialize requests now negotiate compatible MCP protocol versions, recycle stale per-connection sessions, and harden transport/session validation.
- MCP Server: handshake writes now create restricted `0o600` files up front; flow-query fallback filtering, URL/cURL redaction, and port/config validation are stricter and more deterministic.
- MCP Server: recent-flow SessionStore fallback no longer under-filters when callers request a small limit with host/method/status filters.
- MCP Server: transport/tool error payloads now stay valid JSON even when messages contain quotes, backslashes, or control characters.

## [0.8.0] - 2026-04-16

### Added

- Scripting: dedicated **Scripting List** window (sidebar idiom matching Allow List / Block List / SSL Proxying List) with three-column table (Name / Method / Matching Rule), folder grouping with rename-in-place, slide-up filter bar, bottom bar with `+` `−` `New Folder` `?` / Filter / Advance / More.
- Scripting: dedicated **Script Editor** window with Matching Rule header (Name, URL, method picker, Wildcard/Regex picker, "Test your Rule", "Include all subpaths"), Run-on row (Request / Response / Run as Mock + saved-and-active dot), code editor with line-number ruler + the multi-arg default template, right-side console panel with eye-icon log-level filter (Errors / Warnings / User Logs / System), footer (More / Beautify ⌘B / Snippet Code / Save & Activate ⌘S / console eye toggle).
- Scripting: multi-arg JS API support — `onRequest(context, url, request)` and `onResponse(context, url, request, response)` with `request.headers` / `request.queries` / `request.body` / `response.statusCode` / `response.headers` / `response.body` / `response.bodyFilePath`. Single-arg `onRequest(ctx)` / `onResponse(ctx)` continues to work; the runtime dispatches by JS function `length`.
- Scripting: `response.bodyFilePath` — load a local file (sandboxed to user home, capped at `ProxyLimits.maxResponseBodySize`) as the response body.
- Scripting: Advance menu — "Allow Scripts to read System Environment Variables" exposes `$rockxy.env.system(key)`; "Allow Running Multiple Scripts for one Request" enables id-sorted chained execution. Both persisted in `AppSettings`.
- Scripting: "Enable Scripting Tool" toggle in the Scripting List title row, persisted as `AppSettings.scriptingToolEnabled`.
- Scripting: folder grouping persisted as a single JSON blob in UserDefaults; `ScriptFolderStore` reconciles the index against live plugin ids on every refresh.
- Scripting: enabled scripts now run on live HTTP and HTTPS traffic without the Scripting or Settings window needing to be open. `PluginManager.ensureLoadedOnce()` is awaited on the capture-start path and called at app launch.
- Scripting: optional `scriptBehavior` block on `PluginManifest` (`matchCondition`, `runOnRequest`, `runOnResponse`, `runAsMock`) — opt-in per-script matching and mode gating.
- Scripting: response-side hook now actually mutates what the client receives and what Rockxy persists. `ScriptResponseContext` is mutable with `setStatus`, `setHeader`, `setBody` JS helpers and a Swift apply-back to `HTTPResponseData`.
- Scripting: inline mock responses via `runAsMock=true`. `onRequest(ctx)` returns a `{ statusCode, headers?, body? }` object; the request never goes upstream. Invalid mock output fails locally with HTTP `502`.
- Scripting: CommonJS `module.exports = { onRequest, onResponse }` compatibility added alongside the existing direct-global pattern.

### Fixed

- Scripting: legacy `onResponse(ctx)` scripts can once again mutate top-level `ctx.statusCode`, `ctx.responseHeaders`, and `ctx.body` directly.
- Scripting: legacy `ctx.setBody("plain text")` now actually replaces the outgoing request body instead of silently falling back to the original bytes.
- Scripting: `Save & Activate` truthfully enables a script on save; the UI no longer reports an inactive script as active. Quota-reached and load-error paths surface explicit status messages.
- Scripting: request and response framing headers (`Content-Length` / `Transfer-Encoding`) are recomputed after any script body mutation so downstream receivers stay in sync.
- Scripting: oversize responses no longer flush early when a response breakpoint is armed — breakpoint semantics take precedence over the scripting fast-path.
- Scripting: request and response hooks no-op when the `Enable Scripting Tool` toggle is off, even for already-enabled scripts.
- Scripting: legacy `openWindow(id: "scripting")` call sites updated to the new `scriptingList` window id.

### Changed

- Scripting: forwarded request head is now rebuilt from the (possibly script-mutated) `HTTPRequestData` via `ProxyHandlerShared.buildForwardHead(from:originalHead:)`. Method, path, query, headers, and body-derived `Content-Length` reach upstream as expected. Host, port, and scheme mutations from scripts are dropped (with a one-time warning per plugin); use the **Map Remote** rule action for cross-host rewrites.
- Scripting: deterministic id-sorted plugin execution order; first-match wins on both request and response side.
- Scripting: response hook runs between response-header rule operations and breakpoint dispatch. When the upstream body exceeds `ProxyLimits.maxResponseBodySize`, response-side scripting is skipped for that request and the existing full streaming behavior is preserved.

## [0.7.1] - 2026-04-15

### Fixed

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

### Changed

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

## [0.7.0] - 2026-04-13

### Added

- Redesign SSL Proxying List with Include/Exclude tabs and import support

### Fixed

- Empty include list no longer intercepts all traffic, rebuild bypass cache on import
- Reconcile selection on visible-list changes and batch Add-App saves
- Reject unrelated JSON in SSL importer, route context menu to clicked row
- Detect helper signing mismatch and BTM desync instead of looping
- Refresh snapshot after HAR/session import, add picker flow + coordinator path tests
- Refresh snapshot on clear/rebuild/enrichment, restore Select control, add picker flow tests
- Add App uses real observed domains — no manual fallback or guessed wildcards
- Add App picker shows both Apps and Domains sections from live traffic
- Restore Add App picker UI matching Figma design
- Cleanup pass — remove misleading app picker, fix bypass help text, add sidebar tests
- Harden SSL Proxying List — cache loading, import validation, sidebar toggle, wildcard matching

### Changed

- Assert only newly added slice in addRulesAddsMultipleDomains
- Harden SSL importer normalization, domain validation, snapshot dedupe, and test isolation
- Add coordinator-entrypoint regression tests for sidebar SSL toggle

## [0.6.0] - 2026-04-11

### Added

- Redesign Allow List with full URL pattern matching and dedicated management window
- Redesign breakpoint rules window with dedicated management UI

### Changed

- Sync changelog surfaces
- Trim Allow List rule name before persisting
- Noun-phrase inflection for paused header, trim and regex-safe Allow List save
- Allow List and Breakpoint cleanup pass — normalize method, tighten logs, localize headers, tighten tests

## [0.5.0] - 2026-04-10

### Added

- Security hardening, docs honesty, trust recovery, helper lifecycle, architecture cleanup

### Fixed

- Wire JSONInspectorView into response body tab, deterministic tab selection
- Code review follow-up — thread safety, fail-closed backup, honest docs, UI polish

### Changed

- Sync changelog release surfaces

## [0.4.0] - 2026-04-09

### Added

- Redesign rule editor with Proxyman-style dropdowns and enlarged window

### Fixed

- Prevent selectPlugin load failure from being overwritten by success status
- Surface UI feedback when applyTemplate receives unknown name
- Tighten scripting template fallback, scope subpaths toggle, localize provenance
- Address code review findings for block-list PR
- Restore quick-create handoff, remove nonfunctional controls, enforce honest UI

### Changed

- Merge remote-tracking branch 'origin/main'
- Add multilingual README translations
- Add localized readmes

## [0.3.0] - 2026-04-08

### Added

- Add edition capability model, replay toast, and product naming

### Fixed

- Satisfy release doctor swiftlint check
- Stop swallowing non-3 launchctl errors in watchdog removal
- Replace precondition with throwing resolver in neutrality tests
- Address review findings for community core cleanup
- Remove release scripts from tracking
- Guard universal web download release sync

### Changed

- Clean public repo language and harden release script guards
- Remove placeholder surfaces and dead settings code
- Apply swiftformat across codebase

## [0.2.0] - 2026-04-06

### Added

- Add request-list row model, native table sorting, and scaling foundation
- Add app-wide readiness state propagation and CA lifecycle hardening
- Automatic proxy port fallback when preferred port is occupied

### Fixed

- Harden session store row iteration
- Clear rockxy doctor release blockers
- Replace force-unwrap with Data(UTF-8) in WebSocket test helper
- Address review findings for request-list scaling foundation
- Improve trust prompt and direct proxy recovery
- Address review findings for request-list scaling foundation
- Harden helper notification propagation, test reliability, and readability
- Guard getsockname return value, snapshot full settings in test teardown
- Socket failure returns unavailable, harden resolveAtMaxPort test
- Resolver crash at port 65535, bind-probe for 0.0.0.0, stable tests

### Changed

- Adopt community identity and harden macOS setup
- Harden universal release validation
- Fix changelog entries for v0.1.1 release

## [0.1.1] - 2026-03-31

### Fixed

- Fix unbounded memory accumulation in HTTP body and WebSocket handlers
- Fix CONNECT tunnel URI parsing for IPv6 and invalid ports
- Fix ReDoS vulnerability in rule regex matching — patterns now validated at import
- Fix SQL interpolation in schema migration
- Fix path traversal in body file loading
- Fix TOCTOU race in MapLocal file validator
- Fix CRLF injection in MapRemote host header
- Harden helper tool input validation for bypass domains and service names
- Add sensitive data redaction in proxy logs
- Tighten file permissions on stored body files

### Changed

- Clean up Window menu — remove feature window entries, keep standard macOS items only
- Restructure View menu with standard labels and keyboard shortcuts
- Restructure Flow menu with Repeat, Edit and Repeat, Save, Export, Comment, Highlight, Delete
- Fix Modify Headers window empty state layout
- Update menu links and About dialog to correct URLs
- Update README with current architecture, security documentation, and feature comparison table

## [0.1.0] - 2026-03-30

### Added

- Initial open-source release of Rockxy
- Diff integration: select exactly 2 transactions in the request list, right-click "Compare Selected" to open the diff window with both transactions loaded for side-by-side comparison of headers, body, and timing; also available via Diff > Compare Selected menu (Cmd+Option+D)
- Session metadata dialog after opening a `.rockxysession` file: shows transaction count, log entry count, capture date range, and Rockxy version that saved the session
- Scripting window empty state: explains what JavaScript scripting does, lists capabilities (modify headers, inspect responses, block patterns, mock responses), and provides a "Create Your First Script" button
- Script sidebar error visibility: plugins in error state now show the error message inline (red text, tooltip) instead of just a version number; loading state shows "Loading..." label
- Script console surfaces load-time errors: plugins that fail during initial load now emit error entries to the console automatically
- Specific error messages for script timeouts and JS exceptions in the scripting console, with actionable hints (e.g., "Check for infinite loops")
- "Edit and Repeat" replay sheet: right-click context menu now splits "Repeat" (fast replay) from "Edit and Repeat" (opens editable sheet with method, URL, headers, body editing and inline response display)
- Unified rule management: `MapLocalWindowView`, `MapRemoteWindowView`, and `BlockListWindowView` now route all mutations through `RuleSyncService` instead of using private `RuleStore` instances; all windows subscribe to `.rulesDidChange` notifications for cross-window consistency
- `RuleEngine.updateRule(_:)`, `replaceAll(_:)`, `setEnabled(id:enabled:)` methods for granular and batch rule mutations
- `RuleSyncService.updateRule(_:)`, `replaceAllRules(_:)`, `setRuleEnabled(id:enabled:)` methods with automatic persist + notification broadcast
- Persistent direct-mode proxy backup (`DirectProxyBackup` plist) survives crashes and force-quits; written before any `networksetup` mutation, cleared after successful restore
- Launch-time stale proxy recovery: `recoverStaleProxyIfNeeded()` detects and restores leftover Rockxy proxy overrides on app launch (discards backups older than 24 hours)
- Ownership-aware `disableSystemProxy()` via `effectiveOverrideOwner()`: detects whether the proxy is owned by direct mode or helper, restores from in-memory state or disk backup, and handles partial failure without losing the backup
- Partial failure rollback in `enableSystemProxyViaNetworkSetup`: if any service fails mid-setup, already-mutated services are rolled back to their original state
- `HelperConnection.getProxyStatus()` async wrapper for querying helper proxy state
- Response breakpoints: proxy pipeline now intercepts upstream responses when breakpoint phase is `.response` or `.both`, buffers the full response, pauses for user editing (status code, headers, body), and forwards the modified response via `BreakpointResponseBuilder`; works for both HTTP and HTTPS traffic
- Editable query parameters in breakpoint editor: the Query tab now shows editable name/value TextFields with add/remove buttons instead of read-only text; edits sync back to the draft URL in real time
- "Add Breakpoint for Selected Request" command in Tools menu and toolbar breakpoint dropdown: creates a regex-based breakpoint rule matching the selected transaction's host and path
- Breakpoints window (`Cmd+Shift+B`) with queue-backed `BreakpointManager`: supports multiple simultaneous paused requests, two-column layout (queue list + editor), per-item resolve or bulk resolve-all, elapsed time tracking, and toolbar indicator with paused count
- Live bandwidth metering in the footer status bar: cumulative upload/download totals, instantaneous throughput via 1-second sliding window with 250ms decay timer, and tooltips on speed indicators
- Helper tool `unreachable` status with XPC diagnostic properties (`installedVersion`, `isReachable`, `registrationStatus`, `lastErrorMessage`, `isBusy`) and `retryConnection()`/`reinstall()` actions
- Advanced Proxy Settings helper section redesigned with 3-zone layout: summary row with status-mapped icons/colors/subtitles, diagnostics grid (bundled vs installed version, registration status, XPC reachability), conditional error detail, and state-dependent action buttons with inline progress indicator
- Uninstall confirmation alert for helper tool removal in Advanced Proxy Settings
- Deferred settings controls in General, Tools, and Advanced tabs cleaned up — non-functional settings removed entirely rather than shown as disabled previews
- Behavior-oriented settings wiring tests covering `NoCacheHeaderMutator.isEnabled` integration and `ImportSizePolicy` oversized-file rejection, replacing shallow UserDefaults round-trip tests
- `RuleEngine` converted from struct to shared singleton actor for thread-safe rule evaluation across proxy handlers; async rule evaluation in HTTPS handler via `makeFutureWithTask`
- `RuleSyncService` centralizes all rule mutations (add, remove, toggle, load) with automatic disk persistence, `BreakpointWindowModel` refresh, and `rulesDidChange` notification broadcasting
- `MainContentCoordinator` rules snapshot kept in sync via `rulesDidChange` notification observer; views read `coordinator.rules` instead of crossing actor boundary
- Breakpoint window two-section sidebar (`BreakpointSidebarView`) showing both breakpoint rules and paused items; `BreakpointWindowModel` tracks selection mode (rule vs paused item) with automatic fallback; `BreakpointEditorView` shows rule detail (pattern, phase, status) or paused-item editor depending on selection; adaptive action bar switches between rule enable/disable/remove and paused-item cancel/abort/execute controls
- `breakpointRuleCreated` notification opens the breakpoints window automatically when a new breakpoint rule is created
- Wire `showAlertOnQuit` setting — AppDelegate now reads `com.amunx.Rockxy.showAlertOnQuit` from UserDefaults and shows a confirmation alert before quitting when enabled
- Settings truth audit — every @AppStorage key across all 4 settings tabs annotated with wiring status (WIRED or DEFERRED) in both doc comments and inline comments
- Import size boundaries — `ImportSizePolicy` validates file sizes before loading HAR (100 MB limit) and session (200 MB limit) imports to prevent OOM/hangs from oversized files
- Map Local Directory support — serve files from an entire local directory instead of a single file, with automatic subpath resolution, index.html fallback, MIME type detection, and path traversal protection
- File/Directory segmented toggle in Map Local rule editor with path resolution preview
- `MapLocalDirectoryResolver` for secure directory-to-URL mapping with symlink resolution and 10 MB file size cap
- Test suite: MapLocalDirectoryResolverTests (12 tests) covering path resolution, index fallback, traversal prevention, MIME detection, symlinks, and size limits
- Allow List — capture-level filter that restricts recording to specific domains only; non-matching traffic is forwarded but not captured
- Allow List window (Tools > Allow List, Cmd+Opt+A) with master toggle, warning banner, domain table with per-entry enable/disable, add/remove/import/export
- "Add to Allow List" / "Remove from Allow List" in sidebar domain context menu
- "Allow List" accent-colored badge in status bar when active
- `AllowListManager` singleton with thread-safe `isHostAllowed(_:)` for NIO access, JSON persistence, import/export
- `AllowListEntry` model with wildcard and exact domain matching
- No Caching toggle — global switch (Tools menu + Settings) injects `Cache-Control: no-cache, no-store, must-revalidate` and `Pragma: no-cache` on all outbound requests, strips `If-Modified-Since` and `If-None-Match` conditional headers to force fresh responses from origin servers
- "No Cache" orange status bar badge when No Caching is active
- Breakpoint end-to-end wiring — `.breakpoint` rule action now pauses HTTP and HTTPS requests in the NIO pipeline, presents the breakpoint sheet for user editing, and forwards/aborts/cancels based on decision
- `BreakpointViewModel` moved to `MainContentCoordinator` so both the proxy callback and the sheet view share the same instance
- Multiple workspace tabs — open independent debugging workspaces in tabs (Cmd+T new tab, Cmd+W close, Cmd+1-9 switch)
- Each workspace tab has its own filter criteria, selection, sidebar scope, and inspector state
- "Open in New Tab" context menu on domain and app rows in sidebar
- Tab strip UI with close, duplicate, rename (double-click), and "Close Other Tabs" context menu
- Previous/Next tab navigation (Cmd+Shift+[/])
- "Copy as" submenu: Request Headers, Response Headers, Request Body, Response Body, Request Cookies, Response Cookies
- "Copy URL" in Edit menu (Cmd+C) for selected request
- `RequestCopyFormatter` — pure formatter layer for all copy-to-clipboard formats with proper shell escaping
- Custom Previewer Tabs — user-configurable body preview tabs in request/response inspector (JSON Treeview, HTML Preview, Hex, Raw, CSS, JavaScript, XML, Images, Form URL-Encoded)
- "+" button on inspector tab bars opens panel-scoped popover to toggle preview tabs
- Custom Previewer Tabs settings window (Tools menu) as secondary global defaults surface
- `PreviewRenderer` — pure rendering engine for all preview formats with hex dump, JSON tree, HTML/CSS/JS beautify
- Custom Header Columns settings window (Tools menu) — add request/response header columns to the flow table
- `RequestCopyFormatter.cellValue` resolves custom header column values via `HeaderColumnStore`
- Auto-discover headers from captured traffic — settings view shows discovered headers as unchecked items alongside stored columns
- Built-in column visibility toggles in column header right-click menu (Status, #, URL, Client, Method, Code, Time, Duration, Size, Query Name)
- Hidden built-in column state persisted to UserDefaults
- Discovered headers persisted to UserDefaults across app restarts
- "Manage Header Columns..." menu action opens Custom Columns settings window
- Settings window merges stored and discovered headers into a unified checkbox list
- Tests for header discovery persistence, built-in column visibility toggle, and persistence
- Quick search bar with field picker in traffic list toolbar — search by URL, host, path, method, status code, headers, query string, comment, or color
- Active filter summary strip showing current filter state with removable chips and "Clear All" button
- Filter fields: statusCode, requestHeader, responseHeader, queryString, comment, color for advanced filter rules
- Filter operators: "Is Not" (notEqual) and "Regex" for advanced filter rules
- Protocol filter pills: Form (application/x-www-form-urlencoded, multipart/form-data) and Font (woff, woff2, ttf, otf) content type filters
- Filter count badge on status bar Filter button when filters are active
- Test suites: FilterOperatorTests (20 tests), FilteringTests (22 integration tests), ProtocolFilterTests (13 tests)
- Native `.rockxysession` format — save and open full debug sessions with all metadata, timing, WebSocket frames, GraphQL info, and log entries
- HAR import (File → Import HAR…) — load HAR 1.2 archives from Chrome DevTools, Firefox, or other proxy tools into Rockxy
- Test suites: SessionSerializerTests (10 tests), HARImporterTests (9 tests) covering serialization round-trips and HAR parsing
- TLS rejection UI warning — after 3+ unique hosts reject proxy certificate, show banner suggesting browser restart or trust check
- Clear stale auto-passthrough hosts when root CA trust is freshly established
- Lazy helper status check in `enableSystemProxy()` — resolves race condition where proxy start could miss the helper if `AppDelegate.checkStatus()` hadn't finished yet
- Targeted warning banner when helper tool needs re-approval in System Settings after version update
- Sidebar right-click context menu on domain and app rows — Pin, Enable/Disable SSL Proxying, Sort by Alphabet, Tools (Map Local/Remote, Block, Breakpoint), Export (Copy Domain, Export Transactions as HAR), Delete
- SSL proxying status indicator (lock shield badge) on sidebar domain rows
- Bypass Proxy List — dedicated window (Tools → Bypass Proxy List… / Cmd+Opt+B) to manage domains excluded from proxying at the macOS system level
- System proxy bypass integration via `networksetup -setproxybypassdomains` on all enabled network services
- Helper tool `setBypassDomains` XPC method for privileged bypass domain management
- Crash recovery backup/restore for original system bypass domains
- Live bypass list updates — editing the bypass list while proxy is running applies changes immediately
- Sidebar context menu: Add to / Remove from Bypass Proxy List
- Remove dead `excludedHosts` field from AppSettings and ProxyConfiguration (replaced by BypassProxyManager)
- Helper tool certificate trust management — `installRootCertificate`, `removeRootCertificate`, `verifyRootCertificateTrusted`, `cleanupStaleCertificates` XPC methods with SHA-256 fingerprint-based identity
- Map Local rules now support a configurable status code (defaults to 200 for backward compatibility)
- Rule import/export to JSON files via `RuleStore.exportRules(to:)` and `importRules(from:)`
- Breakpoint phase selection (request vs response) via `BreakpointPhase` enum on `BreakpointRequestData`
- Right-click context menu on request list — Copy URL/cURL/cell value/JSON/HAR/raw, Repeat, Pin, Highlight (6 colors), Tools (Map Local/Remote, Block, Breakpoint, SSL Proxying), Export body, Add Comment, Delete — with SF Symbol icons and keyboard shortcuts matching the menu bar
- Transaction highlight colors (red/orange/yellow/green/blue/purple) with tinted row background
- Transaction pinning (isPinned property on HTTPTransaction)
- User-Agent app identification — extract app names (Chrome, Safari, Firefox, Edge, curl, Slack, etc.) from HTTP User-Agent headers at capture time, providing instant app identification without waiting for lsof process resolution
- TLS failure suppression — duplicate TLS handshake failures for cert-pinned hosts (e.g., `gateway.icloud.com`) are suppressed within a 30-second window, showing only the first failure per host
- Column auto-sizing — double-click column dividers to fit content; URL and Client columns auto-size on first data load
- Process identification via `lsof` — resolve which macOS app (Safari, Chrome, `trustd`, `cloudd`, etc.) made each proxy connection by mapping TCP source ports to PIDs, with 2-second batch caching
- Real macOS app icons in sidebar — resolve app icons via `NSWorkspace` bundle ID lookup with gradient monogram fallback
- Real macOS app icons in client column — resolve app icons via `NSWorkspace` bundle ID lookup with fallback to colored initials for unknown apps
- Status dot column in request list — colored dots (green/yellow/orange/red/gray) before row number indicate transaction state at a glance
- Welcome/Getting Started window with live setup checklist (cert, helper, proxy status detection)
- Map Local window for serving local files in place of matched requests
- Map Remote window for redirecting requests to different servers
- Block List window for blocking requests by URL pattern (wildcard/regex)
- SSL Proxying List window for managing HTTPS interception domains
- Diff window with side-by-side comparison of two transactions (headers, body, timing)
- Scripting window with code editor, plugin sidebar, and console output
- Breakpoint sheet for intercepting and editing requests mid-flight (edit URL, headers, body, status)
- Engine status pills in toolbar showing Proxy/Logs/Plugins state
- Enhanced status bar with request count, session duration timer, error count, selected request info
- All menu items now functional: SSL Proxying, Map Local, Map Remote, Block List, Diff, Scripting, Getting Started
- Rule Hub: grid layout with toggle/name/pattern/action/priority columns, search field, action type filter, presets menu (Block Ads, Block Analytics, Map API Local, Throttle API, Breakpoint All), import/export buttons
- Block List: info bar explaining block behavior, icon-style match type badges (wildcard `*` blue, regex `R` purple, exact `=` green) with "auto" detection tag
- Map Local: info bar, inline browse button for file selection, orange status code text for non-200 codes
- Map Remote: info bar, purple destination URLs, collapsible detail panel showing URL breakdown (protocol/host/port/path/query)
- Breakpoint: elapsed timer in orange alert banner (MM:SS format), response tab for viewing/editing response bodies, inline status code picker, segmented tab bar (Headers/Body/Query/Response)
- Scripting: yellow "JavaScript" language badge, Templates dropdown menu with 4 preset scripts (Modify Headers, Log Requests, Block Pattern, Custom Response), color-coded console timestamps (blue=info, orange=warning, red=error, green=output)
- Plugin Manager: category filter tabs (All/Inspector/Exporter/Script), search field, Reinstall button for non-built-in plugins
- System proxy warning banner with Retry button when proxy runs but system proxy fails to configure
- 10-second XPC timeout for all helper tool calls to prevent hung continuations
- Test suites: RuleActionTests (11 tests), CertificateTests (9 tests), StorageTests (8 tests) using Swift Testing framework
- Inspector Comments tab with TextEditor for per-transaction notes
- Sidebar Favorites persistence via UserDefaults (survives app restart)
- Certificate menu items wired: "Install on This Mac…" calls CertificateManager, "Export Root Certificate…" opens NSSavePanel to export PEM
- Stub Settings tabs (GitHub Integration, Platform Detection) replaced with "Coming Soon" placeholders
- `comment` property on HTTPTransaction for inspector comments
- `Codable` conformance on SidebarItem and AnalyticsSection for JSON persistence
- JavaScript plugin ecosystem (Phase 1): runtime script plugins with JavaScriptCore, plugin manifest parsing (`plugin.json`), filesystem discovery from `~/Library/Application Support/Rockxy/Plugins/`
- `$rockxy` bridge API for JS plugins: logging (OSLog), crypto (SHA256/MD5), encoding (base64/URL), scoped storage (UserDefaults), environment config
- Plugin request hooks in proxy pipeline — enabled plugins can inspect and modify HTTP/HTTPS requests before forwarding
- Read-only response hooks for plugins to observe completed responses
- Plugin Settings tab with searchable plugin list, detail panel (icon, badges, config form, actions), install/uninstall/reload controls
- Plugin type badges (Script green, Inspector blue, Exporter orange, Detector purple) and status indicators in Settings UI
- Auto-generated configuration forms from plugin manifest (text fields, secure fields, toggles, number inputs)
- 5-second timeout for plugin script execution to prevent hung scripts from blocking the proxy
- Test suites: PluginManifestTests, ScriptBridgeTests, ScriptRuntimeTests using Swift Testing framework
- Test suites: WelcomeViewModelTests (15 tests), SystemProxyManagerTests (20 tests) covering setup flow, error descriptions, and networksetup output parsing
- Test suite: HelperConnectionErrorTests (6 tests) covering XPC error descriptions including timeout
- Privileged Helper Tool (RockxyHelperTool): SMAppService-based launch daemon for instant system proxy changes without password prompts, with XPC caller verification and crash recovery
- Helper tool build/verify/uninstall scripts for development and release workflows
- Dual-mode system proxy: fast XPC path via helper daemon, fallback to networksetup CLI
- Helper Tool management UI in Advanced Proxy Settings with install/uninstall/update controls
- SSL Proxying List: per-domain control over which HTTPS connections get intercepted and decrypted; domains not in the list pass through as raw tunnels
- Welcome screen auto-shows on first launch when no trusted root CA is detected
- RockxyHelperTool Xcode target with hardened runtime, entitlements, and SMAuthorizedClients/SMPrivilegedExecutables
- Build-time Team ID injection via xcconfig (never hardcoded in source)
- Developer setup script (`scripts/setup-developer.sh`) for first-run contributor onboarding
- Notarization script (`scripts/notarize-app.sh`) reading credentials from environment only
- Code signing script (`scripts/sign-helper.sh`) for distribution helper builds
- Full app reset script (`scripts/rockxy-reset.sh`) to return to first-run state
- NSTableView-backed request list (RequestTableView) for 100k+ row virtual scrolling performance
- Status bar showing row count and selection state
- CenterContentView combining request table, inspector panel, and status bar in a VSplitView
- Protocol filter models (ProtocolFilter, FilterField, RequestInspectorTab, ResponseInspectorTab, ResponseFormat)
- JSON tree view with collapsible nodes, syntax-colored values (strings, numbers, booleans, null), and disclosure triangles
- Theme constants for table, JSON syntax, filter pills, status bar, and inspector styling
- `clientApp` property on HTTPTransaction for tracking originating application
- Proxyman-style app-centric sidebar with Favorites (Pinned, Saved), All (Apps grouped by client app with nested domains, Domains tree), and Analytics sections
- Sidebar bottom bar with add and filter shortcut buttons
- Toolbar status indicator showing proxy connection state (green dot + listening address) in center toolbar
- Protocol filter bar with pill buttons for content types (HTTP, HTTPS, WebSocket, JSON, XML, JS, CSS, GraphQL, Document, Media, Other) and status codes (1xx-5xx)
- FilterPillButton reusable component with Theme.FilterPill styling
- SearchFilterBar component with field selector dropdown, text search, and enable/disable toggle
- Full macOS menu bar with File, Edit, View, Flow, Tools, and Certificate menus with keyboard shortcuts
- Help menu with Getting Started, Homepage, Github, Technical Documents, Report Bug, and Copy Debug Info
- Diff and Scripting menus (placeholder) between Tools and Certificate menus
- Check for Updates and Change Logs entries in app menu
- Professional source code documentation across all 146 Swift files for open-source readiness
- Initial project structure and architecture
- SwiftNIO-based proxy engine foundation
- SwiftUI + AppKit hybrid app shell with 3-column NavigationSplitView
- Certificate management module for HTTPS interception
- Rule engine for traffic modification
- Log capture engine for application log intelligence
- [Planned] Analytics engine for error analysis and performance insights
- SQLite-based session persistence
- Mintlify documentation for network debugging features (Traffic Capture, HTTPS Interception, WebSocket Inspection, GraphQL Support)
- Mintlify documentation for intelligence features (Traffic Rules, Request Replay, Log Intelligence, Error Analysis, Performance Insights)
- Mintlify documentation for customization (Settings, Keyboard Shortcuts) and development (Architecture, Code Style, Building)
- X.509 certificate generation via swift-certificates (P256 keys, root CA, per-host certs with SAN extensions, LRU cache for 1,000 hosts)
- macOS Keychain integration for root CA private key storage
- PEM-based certificate persistence in Application Support
- SQLite session store with 3 tables (transactions, log_entries, websocket_frames), body >1MB offloaded to disk
- Compression framework body decoder (gzip, deflate, brotli) with growing buffer strategy
- [Planned] Analytics: error grouping by normalized URL pattern + status code, P50/P95/P99 latency per endpoint, timeline dependency detection, trend tracking vs baseline sessions
- OSLog stream capture with 500ms polling, process stdout/stderr capture via Process + Pipe
- System proxy management via networksetup CLI (auto-detect active network service)
- SwiftNIO proxy server with HTTP/HTTPS/WebSocket support (ServerBootstrap, ChannelInboundHandler pipeline)
- HTTPS CONNECT tunnel with per-host TLS interception (NIOSSLServerHandler + NIOSSLClientHandler)
- WebSocket frame capture and bidirectional forwarding
- Settings view with General/Proxy/SSL tabs and AppStorage bindings
- Rule management view with add/edit/delete/toggle and swipe-to-delete
- Request timeline waterfall view with colored timing segments (DNS, TCP, TLS, TTFB, Transfer)
- Certificate setup view with generate/install/export/reset actions
- Data flow wiring: ProxyServer → TrafficSessionManager (100ms batch timer) → MainContentCoordinator → SwiftUI views
- Log engine wiring with LogCorrelator for request-log correlation
- [Planned] Auto-triggered analytics at every 100-transaction milestone
- Buffer eviction: oldest 10% moved to SQLite when exceeding 50k capacity
- Plugin system with InspectorPlugin, ExporterPlugin, and ProtocolHandler protocols
- HAR 1.2 exporter with full spec compliance (ISO8601 timestamps, timing breakdown, base64 binary bodies)
- Debug-only sample data generator with realistic HTTP transactions, log entries, error groups, performance metrics, session trends, and domain tree
- Debug menu commands and toolbar button to load/clear sample data
- Launch argument `-RockxySampleData` for auto-loading sample data on startup

### Fixed

- `SystemProxyWarningBanner` ignored the runtime `message` parameter and always showed hardcoded generic text; now displays the actual warning from the coordinator
- Response breakpoint edits not recorded in transaction — after user edits status/headers/body in response breakpoint, the transaction still showed original server response; now updates `responseHead` and `responseBody` before building the transaction
- Stale `pendingBreakpointPhase` leaked across requests — phase was never cleared after handoff to `UpstreamResponseHandler`, causing subsequent non-breakpoint requests on the same connection to incorrectly pause; now cleared after handoff and defensively at request start
- Context menu and sidebar "Add Breakpoint" bypassed `addRule()` coordinator method, calling `ruleEngine.addRule()` directly and skipping JSON persistence; now routes through `addRule()` so rules are saved to disk
- Quick-add breakpoint via Tools menu gave no visual feedback; now shows a confirmation alert with the matched host/path
- Removed dead `BreakpointViewModel` class superseded by queue-backed `BreakpointManager`; kept shared types (`BreakpointPhase`, `BreakpointDecision`, `BreakpointRequestData`, `EditableHeader`)
- `CertificateStore.saveRootCAPrivateKey` wrote plaintext PEM to disk unconditionally even after successful Keychain save; now only writes disk PEM as fallback when Keychain save fails
- Import size-validation and deserialization errors were silently logged with no user feedback; `openSession()` and `importHAR()` now show an `NSAlert` on failure
- `showAlertOnQuit` preference defaulted to `false` for new users because `UserDefaults.bool(forKey:)` returns `false` for unset keys; registered `true` as the default at launch
- Keychain-dependent certificate tests could fail in sandbox/CI environments; added keychain availability probes that skip gracefully when keychain is inaccessible
- `RuleStore` init crashed with `fatalError` when Application Support directory was unavailable; now falls back to a temporary directory with a logged warning
- "Map API Local" preset rule shipped with hardcoded `~/Desktop/mock.json` path; replaced with empty string so users select a file via Browse
- HTTP breakpoint loses non-default ports — after BreakpointRequestBuilder converts to origin-form, `head.uri` no longer contains port info; port derivation now reads `requestData.url.port` instead of parsing origin-form URI
- Breakpoint Content-Length not reconciled after body edit — editing the request body in the breakpoint sheet left the original Content-Length header intact, causing length mismatches; builder now recomputes Content-Length from actual body bytes and strips Transfer-Encoding
- Map Local directory path containment bypass — sibling directories with a shared prefix (e.g. `/tmp/web-evil` vs `/tmp/web`) could pass the `hasPrefix` check; now enforces trailing-slash boundary in both resolve and loadFile paths
- MCP Settings status indicator falsely showed "Running" when toggle was on despite no MCP server existing; now shows "Enabled (server not available)"
- Map Local info bar claimed "Set status code, headers, and body independently" but only status code is configurable; removed misleading copy
- Breakpoint body forwarding — edited request body in the breakpoint sheet was ignored; both HTTP and HTTPS proxy handlers wrote the original captured body (`self.requestBody`) instead of the edited body from `requestData.body`
- HTTPS breakpoint host header desync — enforce original Host header on HTTPS breakpoint execution so user edits cannot mismatch the established TLS tunnel
- HTTP breakpoint origin-form bug — when `head.uri` was path-only (e.g. `/foo`), the breakpoint sheet showed just the path; `URL(string: "/foo")` has no host so forwarding failed with 400. Now seeds the breakpoint with the full absolute URL from `requestData.url`
- HTTPS breakpoint URL field now constrains editing to path and query only — the scheme+host prefix is shown as non-editable text, preventing user edits that would desync from the TLS tunnel
- HTTP breakpoint scheme-change mismatch — user could type `https://` in the breakpoint URL field for a plain HTTP request, causing the builder to emit a URL whose scheme did not match the cleartext transport; builder now forces the original scheme when `isHTTPS == false`, and the sheet locks the scheme prefix as non-editable for HTTP requests too
- XPC caller validation hardened with two-layer defense-in-depth: existing certificate chain comparison (Pearcleaner pattern) plus new `SecRequirement`-based bundle identity check that pins `com.amunx.Rockxy` identifier with Apple anchor, using audit token for PID-race-resistant caller identification
- Removed dead disabled menu items from Diff menu (Add to Pool, Left Side, Right Side) and Scripting menu (Beautify, Save and Activate) that had no implementation
- Fix blank main window visible behind welcome screen on first launch — welcome is now a `.sheet` on the main `ContentView` instead of a separate window, eliminating the `Color.clear` placeholder and preventing duplicate windows
- Discovered headers lost on app restart — now saved to UserDefaults
- Header discovery only ran every 100 transactions — now runs on every batch
- "Manage Header Columns..." notification had no listener — ContentView now opens the settings window
- Table layout not refreshed after toggling built-in column visibility
- Settings window only showed stored columns, not discovered headers
- Fix search field selection ignored — filtering always searched URL regardless of field picker selection
- Fix "Save Session…" menu item exporting HAR instead of saving native Rockxy session format
- Fix Chrome `ERR_CERT_AUTHORITY_INVALID` — add SHA-256 fingerprint-based root CA identity, clean up stale duplicate Rockxy roots from keychain before trust installation
- Remove `keyEncipherment` from ECDSA leaf cert KeyUsage — semantically wrong for ECDHE key exchange, BoringSSL (Chrome) may reject
- Add fail-closed trust validation at proxy start — warn when root CA is not trusted so HTTPS interception falls back to raw tunnel instead of producing cert errors
- Harden root CA regeneration — clear host cert cache when root changes, stop swallowing `ensureRootCA()` errors with `try?` at app launch
- Detect port conflicts before proxy bind — report which process owns the port instead of a generic NIO bind failure
- Replace 60-second connection lifetime cap with idle timeout that resets on data activity (300s) — fixes premature termination of CONNECT tunnels, WebSocket, and long-lived HTTPS connections
- Fix TLS handshake race condition where both success and error handlers fire on the same channel — add `handshakeResolved` guard to `PostHandshakeHandler` so only one path executes
- Fix XPC stale connection reuse after error or timeout — invalidate and nil the cached connection on `remoteObjectProxyWithErrorHandler` error, add `resetConnection()` for explicit cleanup
- Increase helper re-registration wait from 0.5s to 2s and reset XPC connection before availability check — fixes "registered but not responding" loop
- Stop restoring system proxy on transient XPC interruptions — only CrashRecovery handles proxy restore now, preventing proxy instability from brief reconnects
- Add SubjectKeyIdentifier extension to host certificates for proper TLS chain building alongside AuthorityKeyIdentifier
- Add post-install trust verification in KeychainHelper — immediately checks if admin trust settings were actually applied after `installRootCAWithTrust`, warns if user dismissed the auth dialog
- Fix `reinstallPlugin()` attempting to install from already-deleted bundle path — now copies plugin to temp directory before uninstall
- Path traversal protection for Map Local rules — `MapLocalFileValidator` resolves symlinks, validates file existence/readability, and enforces 10 MB size cap before serving
- Rule import rejects files larger than 5 MB to prevent memory exhaustion
- Plugin install validates source is a directory containing `plugin.json` and sanitizes directory names
- Fix crash after long running (`HTTPServerProtocolErrorHandler` precondition failure) — guard all HTTP response writes with `channel.isActive` checks in UpstreamResponseHandler timeout, TLSInterceptHandler sendBlockResponse, sendErrorResponse, and HTTPProxyHandler sendErrorResponse
- Auto-passthrough for strict TLS clients — hosts that reject Rockxy's intercepted certificate (e.g., certificate-pinned apps) are automatically routed through raw tunnel on subsequent connections, with 5-minute TTL before retrying interception
- Fall back to raw tunnel when certificate generation fails instead of closing the channel and breaking traffic
- Fix proxy blocking all internet traffic after ~5 minutes — close client channel after error responses (`Connection: close` header + explicit channel close), close leaked NIO channels on all error paths, add connection limiter to raw tunnel paths
- Revert harmful `Connection: close` on successful responses — restore HTTP/1.1 keep-alive semantics so browsers reuse connections instead of opening one per request
- Wire pinned transactions into sidebar "Pinned" section — clicking Pin in context menu now shows the request in the sidebar
- Wire sidebar selection to request list filtering — clicking a domain or app in the sidebar filters the request list
- Display user-added favorites (domains/apps) in sidebar favorites section
- Fix "Save this Request" context menu action to toggle saved state for sidebar persistence
- Persist pinned and saved transactions to SQLite — pinned/saved requests survive app restarts via schema migration (is_pinned, is_saved, comment, highlight_color, client_app columns)
- Add per-destination connection limit (max 6 concurrent) to prevent unbounded FD growth under heavy traffic
- Add 60-second idle timeout to raw tunnel handler to prevent indefinite FD consumption on hung connections
- Reduce connection lifetime timeout from 120s to 60s for faster zombie connection cleanup
- Fix Chrome `ERR_CERT_AUTHORITY_INVALID` by removing self-signed root CA from TLS certificate chain — serve leaf-only chain per RFC 5246, matching mitmproxy behavior
- Fix app crash after ~40 minutes of capture — add eviction observer for `bufferEvictionRequested` notification to remove oldest transactions and rebuild sidebar indexes
- Fix `-34018` trust write failure by moving root CA install/verify/cleanup to privileged helper tool (runs as root) instead of unprivileged app process
- Fail closed for HTTPS when root CA is untrusted — force global passthrough mode so CONNECT requests tunnel raw instead of producing cert errors
- Fix NIO resource leak — guard `certFuture.whenComplete` with `channel.isActive` check, cancel pending throttle tasks in `handlerRemoved()`
- Fix Chrome privacy interstitial on first TLS rejection — downgrade same connection to raw passthrough instead of closing, so cert-pinned hosts (Google, LinkedIn, etc.) work without user intervention
- Fix `RecentFailureTracker` crash during high-volume TLS failures — move timestamp capture inside lock to prevent `UInt64` underflow race between concurrent NIO event loops
- Fix helper tool version mismatch causing spurious uninstall/reinstall cycles on startup
- Persist auto-passthrough hosts across app restarts (24-hour TTL) — hosts that reject MITM certs are remembered so subsequent sessions skip interception immediately
- Fix helper trust install failing with `-60007` (`errAuthorizationInteractionNotAllowed`) — split cert install: helper adds to system keychain (works from root), app sets trust (has GUI context for macOS auth dialog)
- Fix VPN/tunnel no-capture not surfaced when using helper tool — move VPN detection before helper/networksetup branch so warning banner always appears when default route is `utun`/`ppp`/`tun`
- Fix helper proxy backup saving settings for wrong network service — detect primary service via route table instead of using `services.first`
- Make keychain private key save non-fatal — disk storage is primary, keychain is backup recovery path
- Stop treating all pre-handshake TLS errors as permanent host-level MITM rejection — classify BoringSSL errors, only persist auto-passthrough for confirmed certificate-trust rejections (not timeouts, resets, or protocol errors)
- Fix misleading certificate chain diagnostic — add `validateSystemTrust()` that tests generated certs against real macOS trust store without injecting root CA as explicit anchor
- TLS failure transactions now hidden even when no user filters are active — previously the `isTLSFailure` check was inside the filter block that only ran when filters were set
- Fix proxy blocking all internet traffic — add 5-second connection timeouts to all upstream `ClientBootstrap` calls, 30-second read timeout to `UpstreamResponseHandler`, and 120-second max connection lifetime to prevent hung connections from exhausting resources
- Fix leaked connections on failed TLS handshakes — `PostHandshakeHandler.errorCaught` now closes the channel after recording the failed transaction (was leaving it open with `autoRead = false`, leaking one connection per cert-pinned host)
- Fix lost HTTPS transactions when upstream server closes without TLS `close_notify` — complete and record the transaction from whatever response data was already received instead of silently dropping it
- Fix failed TLS handshakes (cert pinning) invisible in UI — record as failed transactions so they appear in the request list like Proxyman
- Fix noisy `uncleanShutdown` errors flooding console — handle as normal TLS connection close, downgrade upstream close log from error to debug
- Fix HTTPS interception "EOF during handshake" on all connections — change root CA trust from `.user` to `.admin` domain so Safari, Chrome, and system services honor the trust setting; include root CA in server certificate chain for macOS TLS compatibility; replay buffered TLS data after async pipeline reconfiguration to prevent ClientHello loss; add SecTrust chain validation diagnostic at proxy startup
- Fix CONNECT tunnel TLS handshake failure (`WRONG_VERSION_NUMBER`) — replace broken `channel.pipeline.fireChannelRead` replay with forward-based `ProtocolDetectorHandler` that sits before NIOSSLServerHandler and forwards TLS data naturally via `context.fireChannelRead`
- Fix incomplete HTTP pipeline teardown leaving `NIOHTTPResponseHeadersValidator` in the channel after CONNECT
- Fix HTTPS interception TLS handshake failing on all browsers — add `Content-Length: 0` to CONNECT 200 response so NIO's HTTPResponseEncoder uses identity encoding instead of chunked; without this, the chunked terminator bytes (`0\r\n\r\n`) corrupt the TLS handshake stream (browsers don't consume body after CONNECT 200 per RFC 7231 §4.3.6)
- Fix HTTPS interception TLS handshake failing with "EOF during handshake" — add `SubjectKeyIdentifier` to root CA and `AuthorityKeyIdentifier` to per-host leaf certs so macOS SecTrust can build the certificate chain (mitmproxy `dummy_cert` pattern)
- Fix HTTPS MITM fatal crash ("tried to decode as HTTPPart but found IOData") — place `NIOSSLServerHandler` at pipeline `.first` position so outbound TLS bytes go directly to socket, add belt-and-suspenders HTTP codec removal in `installTLSHandlers`, and defer HTTP codec installation until after `TLSUserEvent.handshakeCompleted` via `PostHandshakeHandler`
- Fix "certificate not yet valid" errors with clock skew — backdate `notValidBefore` by 2 days on both root CA and per-host certs (mitmproxy pattern)
- Fix potential DER/BoringSSL incompatibility in per-host certificate generation — switch certificate and private key serialization from DER to PEM format for NIOSSL
- Auto-regenerate root CA on launch if missing `SubjectKeyIdentifier` extension (added in this release)
- Fix helper auto-update "Operation not permitted" after unregister — catch BTM re-approval failure gracefully, set status to `.requiresApproval`, and open System Settings for user to re-approve
- Fix ChannelError 5 (outputClosed) during TLS interception — client no longer times out waiting for ServerHello because buffered data is replayed immediately after cert generation completes
- Fix invalid context use after handler removal in TLS pipeline — capture `channel` reference before `removeHandler` and use `channel.close()` instead of `context.close()`
- Fix helper tool always reporting "notInstalled" despite SMAppService `.enabled` — remove `setCodeSigningRequirement("anchor apple generic")` which rejects all development-signed builds; certificate chain comparison (matching Pearcleaner pattern) is the sole validation mechanism
- Fix helper tool version check always failing — hardcode expected version in `HelperManager` to match `HelperService.version` (Xcode's `INFOPLIST_KEY_` prefix only maps Apple-defined keys, not custom ones)
- Fix XPC continuation leak ("SWIFT TASK CONTINUATION MISUSE: getHelperVersion() leaked its continuation") — flatten nested `withXPCTimeout`/`withCheckedThrowingContinuation` into a single continuation per XPC call with inline timeout racing in the same lock scope
- Fix stale helper registration after Xcode rebuild — add Pearcleaner-style recovery (unregister → 500ms → re-register) when SMAppService reports `.enabled` but XPC doesn't respond
- Fix helper tool only configuring proxy on one network service — rewrite `ProxyConfigurator` to set proxy on ALL enabled services (matching SystemProxyManager Phase 2 fix), restore also disables all services
- Fix HTTPS TLS handshake failing on every CONNECT tunnel — add `RemovableChannelHandler` conformance to `HTTPProxyHandler` and `TLSInterceptHandler`, and reorder pipeline swap to remove application handler before HTTP codecs (matching NIO's own upgrade pattern)
- Fix Welcome screen appearing on every launch despite trusted cert — ensure root CA is loaded into memory before checking trust status, eliminating race with AppDelegate's background Task
- Fix frozen Start button — remove blocking `HelperManager.checkStatus()` from proxy startup path
- Fix XPC timeout hanging forever — replace `withThrowingTaskGroup` with unstructured timeout pattern so stuck XPC continuations don't block the app
- Fix system proxy set on wrong network interface causing zero traffic capture — configure proxy on all enabled services instead of single detected service
- Fix blank main window after clicking "Get Started" in welcome — add welcomeDidComplete notification to reset needsWelcome state
- Fix both windows showing simultaneously on first launch — consolidate welcome window management in MainWindowContent only
- Detect VPN/tunnel primary interface (utun, ppp) and show warning banner that traffic may not be captured
- Fix HTTPS traffic not captured — remove HTTP codecs from NIO pipeline before CONNECT tunnel transition to TLS; without this, TLS ClientHello bytes were misinterpreted as HTTP
- Fix empty SSL Proxying List blocking all HTTPS interception — default to intercept-all when no rules configured, matching Proxyman behavior
- Fix helper tool always showing "notInstalled" — check SMAppService status at app startup so `SystemProxyManager` reads accurate helper state
- Fix welcome screen showing on every launch — load root CA certificate into memory before checking trust status on startup
- Fix traffic not displaying — await session manager setup before proxy server starts accepting connections, preventing race condition where `onBatchReady` callback was nil
- Fix 10-second silent delay when helper tool is not installed — check `HelperManager.status` before attempting XPC, skip directly to networksetup fallback
- Fix invisible helper availability logging — upgrade from `.debug` to `.info` level so XPC results appear in Xcode console
- Add diagnostic logging to certificate trust and installation checks (DER vs label-fallback path visibility)
- Fix proxy stopping immediately after start — system proxy failure no longer kills the proxy server; proxy keeps running with warning banner instead of rollback
- Fix helper tool "Operation not permitted" — embedded Info.plist section in binary so `codesign` identifier matches launchd plist Label
- Fix Welcome screen not showing when setup is incomplete — now checks cert trust status in addition to `showWelcomeOnLaunch` flag
- Fix main window showing behind Welcome window on first launch — main window hidden until setup completes
- Rule engine: mapRemote action now forwards requests to the remapped host instead of silently completing
- Rule engine: modifyHeader action now forwards the modified request to upstream instead of dropping it
- Rule engine: throttle action now delays forwarding by the configured milliseconds instead of silently completing
- HTTPS proxy relay now evaluates rules (block, mapLocal, mapRemote, throttle, modifyHeader) — previously HTTPS requests bypassed all rules
- TLS handshake timing no longer hardcoded to 0; HTTPS connections now report approximate TCP/TLS split
- WebSocket upgrade detection now wired into UpstreamResponseHandler — 101 Switching Protocols triggers pipeline reconfiguration

### Changed

- Import error dialogs now show specific titles and messages per failure type (size exceeded, invalid format, deserialization error) instead of a generic "Import Failed"
- README roadmap updated: `.rockxy format` corrected to `.rockxysession format`
- Removed iOS Simulator Certificate step from Welcome screen — Rockxy ships with 4 setup steps (Install Cert, Trust Cert, Install Helper, Enable Proxy)
- Removed Platform settings tab
- Removed "Restore previous proxy settings on quit" toggle from Advanced Settings — restore-on-quit is now mandatory and always-on via persistent backup
- `stopProxy()` no longer gates `disableSystemProxy()` behind `isSystemProxyConfigured` flag — the ownership-aware disable handles all cases internally
- Privacy Settings tab rewritten with honest disclosure: Data Storage locations (SQLite path, large bodies path), Exports & Sharing warning about sensitive content in exports, and Analytics & Telemetry section with "No Data Collected" badge confirming zero telemetry; removed fake analytics/crash report toggles
- Removed MCP Settings tab — MCP will be re-added when the backend implementation is functional
- Removed HTTP/2 placeholder row from General Settings
- Removed certificate inspector placeholder view
- Root CA private key storage is now Keychain-primary with automatic migration from disk PEM; existing disk keys are migrated to Keychain on first load and the PEM file renamed to `.bak` as recovery-only fallback
- Remove zombie certificate buttons (More, Preview, Advanced) in General Settings and replace with functional "Install & Trust" and "Export Certificate" actions
- Wire "Full Changelogs" button in Advanced Settings to GitHub releases page
- Wire "Privacy Policy" button in Privacy Settings to GitHub wiki page
- Replace dead "External Proxy Settings" and "SOCKS Proxy Settings" buttons with a "Planned for Future Release" GroupBox explaining the feature purpose
- Add "Preview" banner to MCP Settings tab indicating the server backend is under development
- Replace generic "Coming Soon" placeholders in GitHub, Platform, and Workspace settings tabs with purposeful descriptions of planned functionality
- Add tooltip to disabled "Check for Updates" menu item
- Cmd+T now opens a new workspace tab (was "New Session", moved to Cmd+Shift+N)
- Cmd+1-9 now switch workspace tabs (MainTab shortcuts moved to Ctrl+1-5)
- `filteredTransactions` converted from computed property to cached stored property — eliminates O(n) re-filtering on every SwiftUI view evaluation (was running twice per batch delivery)
- Batch timer interval increased from 100ms to 250ms — reduces UI update frequency from 10/sec to 4/sec, producing larger batches instead of 1-2 transaction micro-batches
- Text cells in request list now vertically centered using container NSView pattern (same as status dot and client icon) — fixes NSTableView overriding direct cell view frames
- Batch delivery decoupled from lsof — process resolution now runs asynchronously after batch is delivered, eliminating 50-200ms blocking per cache miss
- Double GraphQL detection removed — JSON parsing now runs once per request (in HTTPProxyHandler) instead of twice
- Auto-analysis throttled to every 10 seconds with 500-transaction threshold (was 2s/100) — reduces MainActor contention during high traffic
- Incremental `appendFilteredTransactions()` fast path — when no user filters are active, new transactions are appended directly instead of re-scanning all transactions O(n)
- Column auto-sizing deferred via `DispatchQueue.main.async` to avoid blocking `updateNSView` hot path
- Process resolution moved off main thread — `lsof` calls now run in `TrafficSessionManager` actor with async dispatch, eliminating 50-200ms main thread blocking per cache miss
- Process resolution cache TTL increased from 2s to 5s — TCP ports reuse slowly, reducing lsof invocations
- Request list row height increased from 22pt to 28pt — better vertical centering and visual breathing room
- NSTableView cell reuse for status dot and client cells — eliminates per-row view allocation during scrolling
- TLS failure transactions hidden from traffic list by default — reduces noise from cert-pinned hosts
- Helper tool auto-updates on version mismatch — `HelperManager.checkStatus()` detects outdated helper and triggers uninstall/reinstall cycle automatically instead of requiring manual update
- System proxy now configures all enabled network services instead of a single detected service, matching Charles/Proxyman behavior
- Detect primary network interface via routing table (`route -n get 0.0.0.0`) for accurate diagnostics
- Add TCP connection logging to proxy server NIO pipeline for connection-level diagnostics
- Upgrade helper tool status logging from debug to info level for Xcode console visibility
- Re-check helper tool status before each proxy start to pick up installs done during welcome flow
- Welcome window now opens as a separate window (Xcode-style) instead of replacing main window content
- Helper tool binary moved to `Contents/MacOS/` with embedded Info.plist, matching SMAppService reference pattern
- Helper tool XPC validation uses certificate chain comparison instead of team-ID-from-plist, removing build configuration dependency
- Certificate install button now updates immediately after successful install (optimistic state update)
- Wire PluginSettingsViewModel to ScriptPluginManager for real plugin loading, reload, and uninstall
- Cookie inspector now shows full request/response cookie details (name, value, domain, path, secure, expiry)
- App termination now properly cleans up system proxy settings before exiting
- Proxy start/stop now triggers log capture lifecycle automatically
- Rules are now persisted to disk after every add/remove/toggle mutation
- ContentView initializes favorites and auto-starts proxy on launch when configured
- Sidebar section headers now use colored text (amber for Favorites, gray for All/Analytics) with increased header prominence
- App icons in sidebar replaced with colored gradient rounded squares showing the app's first letter
- Sidebar SF Symbol icons updated to filled variants matching Proxyman (pin.fill, tray.full.fill, square.stack.3d.up.fill, exclamationmark.triangle.fill)
- Added Theme.Sidebar color definitions for section headers and app icon gradients
- Incremental `NSTableView` updates — use `insertRows(at:)` for append-only batches instead of full `reloadData()`, eliminating UI jank on high-traffic sessions
- O(1) domain tree lookup — dictionary-backed index replaces O(n) `firstIndex(where:)` scan per transaction
- Cached sidebar `appNodes` — incrementally updated in `processBatch()` instead of recomputing from all transactions on every render
- Move GraphQL detection to `TrafficSessionManager` actor — runs on background thread instead of blocking main thread during batch processing
- Time-throttled auto-analytics — max once per 2 seconds instead of every 100 transactions
- Proxy server now runs independently of system proxy — matches Proxyman behavior where system proxy is best-effort
- Proxy toolbar pill shows orange when system proxy is not configured
- `stopProxy()` now guards against re-entry to prevent race conditions with double cleanup
- Helper tool ConnectionValidator now compares code signing certificate chains instead of relying on build-time team ID injection — self-referencing, zero-configuration, immune to Info.plist tampering
- Redesigned app layout from 3-column NavigationSplitView to 2-column with VSplitView center (table + inspector)
- Redesigned inspector panel with Proxyman-style HSplitView layout: URL bar on top, request tabs (left) and response tabs (right)
- Split inspector into dedicated request/response views with independent tab bars
- Added new inspector sub-views: QueryInspectorView, SetCookieInspectorView, AuthInspectorView, SynopsisInspectorView
- Filtering engine now supports protocol and status code filters
- Add port validation (1024–65535) to HelperService proxy override XPC call
- Add rate limiting (2s cooldown) on proxy change XPC calls
- Fix TOCTOU vulnerability in CrashRecovery by replacing fileExists checks with try/catch
- Set restrictive file permissions (0o600) on proxy backup files
- Fix certificate installation failing with errSecDuplicateItem (-25299) when cert exists in system keychain; treat existing cert as success and apply trust settings
- Cache network service detection (30s TTL) to eliminate repeated networksetup calls and log spam from WelcomeView polling
- Fix Welcome screen status dots not updating after certificate install by using DER-based keychain queries instead of label-based lookup
- Fix helper tool not embedded in app bundle (empty CopyFiles phase); binary now at Contents/Library/HelperTools/, plist at Contents/Library/LaunchDaemons/
- Remove legacy SMAuthorizedClients from helper launchd plist (incompatible with SMAppService)
- Wire helper tool Update action in Welcome screen (previously showed "Update" label but called install)
- Fix AdvancedSettingsTab helper section: dynamic status, functional Install/Update/Uninstall buttons with confirmation dialog
- Show Welcome screen inside main window instead of as a separate window behind the app
- Prevent re-installing already-trusted certificate (guard in installCert)
- Fix helper "Operation not permitted" by switching from ad-hoc to Apple Development signing via xcconfig
- Remove legacy SMAuthorizedClients from helper Info.plist
- Rewrite ConnectionValidator with build-time Team ID injection; DEBUG skips OU check, Release requires valid Team ID
- Add helper tool entitlements denying unsigned executable memory and dyld environment variables
- SSL Proxying List UI with domain table, wildcard support, enable/disable toggles, import/export, and common API presets
- Certificate Setup Wizard: guided 5-step first-run flow (Welcome → Generate → Install & Trust → Verify → Complete) shown automatically when no trusted root CA exists
- Certificate Setup Wizard accessible from Help menu
