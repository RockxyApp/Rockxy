import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct MapRemoteModelTests {
    // MARK: Internal

    @Test("filter matches name, method, rule, and destination")
    func filterMatchesVisibleColumns() {
        let vm = MapRemoteWindowViewModel()
        let usersRule = ProxyRule(
            name: "Users",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/users/.*", method: "POST"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com", path: "/users"))
        )
        let assetsRule = ProxyRule(
            name: "Assets",
            matchCondition: RuleMatchCondition(urlPattern: "https://cdn.example.com/.*", method: "GET"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "assets-dev.example.com"))
        )
        vm.allRules = [usersRule, assetsRule]

        vm.searchText = "post"
        #expect(vm.filteredRules.map(\.id) == [usersRule.id])

        vm.searchText = "assets-dev"
        #expect(vm.filteredRules.map(\.id) == [assetsRule.id])
    }

    @Test("management list includes only Map Remote rules and prunes stale selections")
    func listFiltersMapRemoteRulesAndPrunesSelectionOnNotification() {
        let vm = MapRemoteWindowViewModel()
        let remote = ProxyRule(
            name: "Remote",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
        )
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(urlPattern: "https://blocked.example.com/.*"),
            action: .block(statusCode: 403)
        )
        let staleID = UUID()
        vm.allRules = [remote, block]
        vm.selectedRuleIDs = [remote.id, staleID]

        #expect(vm.mapRemoteRules.map(\.id) == [remote.id])

        vm.handleRulesDidChange(Notification(name: .rulesDidChange, object: [remote]))

        #expect(vm.allRules.map(\.id) == [remote.id])
        #expect(vm.selectedRuleIDs == [remote.id])
    }

    @Test("visible Map Remote row labels match the management table")
    func visibleRowLabelsMatchManagementTable() {
        let vm = MapRemoteWindowViewModel()
        let pattern = MapLocalPatternFormatter.wildcardToRegex("https://localhost:3000/v1/*")
        let rule = ProxyRule(
            name: "Untitled",
            matchCondition: RuleMatchCondition(urlPattern: pattern),
            action: .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "https",
                host: "api.production.com",
                path: "/v2/api",
                query: "id=123"
            ))
        )

        #expect(vm.methodLabel(for: rule) == "ANY")
        #expect(vm.matchingRuleLabel(for: rule) == "Wildcard: https://localhost:3000/v1/*")
        #expect(vm.destinationLabel(for: rule) == "https://api.production.com/v2/api?id=123")
    }

    @Test("management destination label uses override tokens when host is inherited")
    func inheritedHostDestinationLabelUsesTokens() {
        let vm = MapRemoteWindowViewModel()
        let rule = ProxyRule(
            name: "Keep host",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "https",
                port: 8_443,
                path: "/v2",
                query: "debug=1"
            ))
        )

        let label = vm.destinationLabel(for: rule)
        #expect(label == "Protocol HTTPS · Port 8443 · Path /v2 · Query debug=1 · Original host")
        #expect(!label.contains("https://"))
    }

    @Test("management destination label brackets IPv6 hosts")
    func ipv6DestinationLabelUsesBrackets() {
        let vm = MapRemoteWindowViewModel()
        let rule = ProxyRule(
            name: "IPv6 target",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "https",
                host: "2001:db8::1",
                port: 8_443
            ))
        )

        #expect(vm.destinationLabel(for: rule) == "https://[2001:db8::1]:8443")
    }

    @Test("remove selected Map Remote rows preserves unrelated rules")
    func removeSelectedPreservesOtherRules() async {
        await withSharedRuleStateRestored {
            let vm = MapRemoteWindowViewModel()
            let mapRemote = ProxyRule(
                name: "Remote",
                matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
                action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
            )
            let block = ProxyRule(
                name: "Block",
                matchCondition: RuleMatchCondition(urlPattern: "https://blocked.example.com/.*"),
                action: .block(statusCode: 403)
            )
            await RuleEngine.shared.replaceAll([mapRemote, block])
            await vm.refreshFromEngine()
            vm.selectedRuleIDs = [mapRemote.id]

            vm.removeSelectedRules()
            await vm.waitForPendingRuleSync()

            #expect(vm.allRules.map(\.id) == [block.id])
            #expect(vm.selectedRuleIDs.isEmpty)
        }
    }

    @Test("remove selected is a no-op without selection")
    func removeSelectedNoopWhenSelectionIsEmpty() {
        let vm = MapRemoteWindowViewModel()
        let rule = ProxyRule(
            name: "Remote",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
        )
        vm.allRules = [rule]

        vm.removeSelectedRules()

        #expect(vm.allRules.map(\.id) == [rule.id])
    }

    @Test("duplicate selected Map Remote rule keeps behavior and selects the copy")
    func duplicateSelectedRule() async {
        await withSharedRuleStateRestored {
            let vm = MapRemoteWindowViewModel()
            let rule = ProxyRule(
                name: "Remote",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*", method: "PATCH"),
                action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com")),
                priority: 7
            )
            vm.allRules = [rule]
            vm.selectedRuleIDs = [rule.id]

            vm.duplicateSelectedRule()
            await vm.waitForPendingRuleSync()

            #expect(vm.allRules.count == 2)
            let copy = vm.allRules[1]
            #expect(copy.id != rule.id)
            #expect(copy.name == "Remote Copy")
            #expect(copy.matchCondition == rule.matchCondition)
            #expect(copy.priority == 7)
            #expect(vm.selectedRuleIDs == [copy.id])
        }
    }

    @Test("toggle and remove-row actions update clicked row immediately")
    func rowActionsUpdateClickedRule() async {
        await withSharedRuleStateRestored {
            let vm = MapRemoteWindowViewModel()
            let remote = ProxyRule(
                name: "Remote",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
                action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
            )
            let other = ProxyRule(
                name: "Other",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: "https://other.example.com/.*"),
                action: .mapRemote(configuration: MapRemoteConfiguration(host: "other-staging.example.com"))
            )
            await RuleSyncService.replaceAllRules([remote, other])
            vm.allRules = [remote, other]
            vm.selectedRuleIDs = [remote.id]

            vm.toggleRule(id: remote.id)
            await vm.waitForPendingRuleSync()
            #expect(vm.allRules.first?.isEnabled == false)

            vm.removeRule(id: remote.id)
            await vm.waitForPendingRuleSync()
            #expect(vm.allRules.map(\.id) == [other.id])
            #expect(vm.selectedRuleIDs.isEmpty)
        }
    }

    @Test("tool enable setter updates view model immediately")
    func toolEnableSetter() async {
        await withSharedRuleStateRestored {
            let vm = MapRemoteWindowViewModel(isToolEnabled: true)
            vm.setToolEnabled(false)
            await vm.waitForPendingRuleSync()
            #expect(vm.isToolEnabled == false)
        }
    }

    @Test("editor store opens blank, draft, and existing contexts")
    func editorStoreContexts() {
        let store = MapRemoteEditorStore.shared
        let startingVersion = store.draftVersion
        let draft = MapRemoteDraft(
            origin: .domainQuickCreate,
            suggestedName: "example.com",
            sourceURL: nil,
            sourceHost: "example.com",
            sourcePath: nil,
            sourceMethod: nil
        )
        let existing = ProxyRule(
            name: "Existing",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
        )

        store.openNew(draft: draft)
        #expect(store.context.draft?.sourceHost == "example.com")
        #expect(store.context.existingRule == nil)
        #expect(store.draftVersion == startingVersion &+ 1)

        store.openExisting(existing)
        #expect(store.context.existingRule?.id == existing.id)
        #expect(store.context.draft == nil)
        #expect(store.draftVersion == startingVersion &+ 2)
    }

    @Test("editor saves rule with method, wildcard pattern, destination, and advanced flags")
    func editorCreatesRule() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Remote"
        vm.urlText = "https://localhost:3000/v1/*"
        vm.method = .post
        vm.matchType = .wildcard
        vm.destScheme = "https"
        vm.destHost = "api.production.com"
        vm.destPort = "443"
        vm.destPath = "v2/api"
        vm.destQuery = "id=123"
        vm.preserveOriginalURL = true
        vm.preserveHost = true

        let rule = try #require(vm.makeRule())

        #expect(rule.name == "Remote")
        #expect(rule.matchCondition.method == "POST")
        #expect(rule.matchCondition.urlPattern == #"https:\/\/localhost:3000\/v1\/.*"#)
        if case let .mapRemote(config) = rule.action {
            #expect(config.scheme == "https")
            #expect(config.host == "api.production.com")
            #expect(config.port == 443)
            #expect(config.path == "/v2/api")
            #expect(config.query == "id=123")
            #expect(config.preserveOriginalURL)
            #expect(config.preserveHostHeader)
        } else {
            Issue.record("Expected .mapRemote")
        }
    }

    @Test("editor saves regex pattern without wildcard conversion")
    func editorCreatesRegexRule() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Regex Remote"
        vm.urlText = #"https://api\.example\.com/v[0-9]+/users"#
        vm.method = .any
        vm.matchType = .regex
        vm.includeSubpaths = true
        vm.destHost = "staging.example.com"

        let rule = try #require(vm.makeRule())

        #expect(rule.matchCondition.method == nil)
        #expect(rule.matchCondition.urlPattern == #"https://api\.example\.com/v[0-9]+/users"#)
    }

    @Test("editor fills destination fields from a full URL and clears stale components")
    func editorFillsDestinationFromURL() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)

        #expect(vm.applyDestinationURL("HTTPS://api.production.com:8443/v2/api?filter=hello%20world&id=1&id=2"))
        #expect(vm.destScheme == "https")
        #expect(vm.destHost == "api.production.com")
        #expect(vm.destPort == "8443")
        #expect(vm.destPath == "v2/api")
        #expect(vm.destQuery == "filter=hello%20world&id=1&id=2")
        #expect(vm.urlParseError == nil)

        // A URL lacking an explicit path targets the remote root and clears port/query.
        #expect(vm.applyDestinationURL("http://staging.example.com"))
        #expect(vm.destScheme == "http")
        #expect(vm.destHost == "staging.example.com")
        #expect(vm.destPort == "")
        #expect(vm.destPath == "/")
        #expect(vm.destQuery == "")
        #expect(vm.urlFillConfirmation != nil)
    }

    @Test("full URL fill preserves encoded paths and rejects dropped components")
    func editorFullURLFillPreservesPathEncoding() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)

        #expect(vm.applyDestinationURL("https://api.example.com/files/a%2Fb%20c"))
        #expect(vm.destPath == "files/a%2Fb%20c")
        let source = try #require(URL(string: "https://source.example.com/original"))
        #expect(vm.mergedDestination(onto: source) == "https://api.example.com/files/a%2Fb%20c")

        #expect(!vm.applyDestinationURL("https://user:secret@api.example.com/files"))
        #expect(!vm.applyDestinationURL("https://api.example.com/files#section"))
        #expect(vm.destPath == "files/a%2Fb%20c")
    }

    @Test("editor surfaces feedback for an invalid pasted destination URL")
    func editorInvalidDestinationURL() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.destHost = "keepme.example.com"

        #expect(!vm.applyDestinationURL("not a url"))
        #expect(vm.urlParseError != nil)
        // A failed parse must not mutate the existing destination fields.
        #expect(vm.destHost == "keepme.example.com")
    }

    @Test("editor rejects unsupported destination URL schemes without changing fields")
    func editorRejectsUnsupportedDestinationScheme() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.destScheme = "https"
        vm.destHost = "keepme.example.com"

        #expect(!vm.applyDestinationURL("ftp://files.example.com/archive"))
        #expect(vm.destScheme == "https")
        #expect(vm.destHost == "keepme.example.com")
        #expect(vm.urlParseError != nil)
    }

    @Test("editor loads transaction and domain drafts")
    func editorLoadsDrafts() throws {
        let transactionURL = try #require(URL(string: "https://api.prod.example.com/v2/users?page=1"))
        let transactionDraft = MapRemoteDraft(
            origin: .selectedTransaction,
            suggestedName: "Users",
            sourceURL: transactionURL,
            sourceHost: "api.prod.example.com",
            sourcePath: "/v2/users",
            sourceMethod: "POST"
        )
        let domainDraft = MapRemoteDraft(
            origin: .domainQuickCreate,
            suggestedName: "Domain",
            sourceURL: nil,
            sourceHost: "cdn.example.com",
            sourcePath: nil,
            sourceMethod: nil
        )
        let vm = MapRemoteEditorViewModel()

        vm.load(context: MapRemoteEditorContext(draft: transactionDraft))
        #expect(vm.name == "Users")
        #expect(vm.method == .post)
        #expect(vm.includeSubpaths == false)
        #expect(vm.urlText == "https://api.prod.example.com/v2/users?page=1")

        vm.load(context: MapRemoteEditorContext(draft: domainDraft))
        #expect(vm.name == "Domain")
        #expect(vm.method == .any)
        #expect(vm.includeSubpaths)
        #expect(vm.urlText == "https://cdn.example.com/*")
    }

    @Test("editor loads existing rule with stable identity and flags")
    func editorLoadsExistingRule() {
        let existing = ProxyRule(
            name: "Existing",
            isEnabled: false,
            matchCondition: RuleMatchCondition(
                urlPattern: MapLocalPatternFormatter.wildcardToRegex("https://api.example.com/v1/*"),
                sourceURLPattern: "https://api.example.com/v1/*",
                method: "DELETE",
                headerName: "X-Debug",
                headerValue: "1",
                matchType: .wildcard,
                includeSubpaths: false
            ),
            action: .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "http",
                host: "staging.example.com",
                port: 8_080,
                path: "/v2",
                query: "debug=true",
                preserveOriginalURL: true,
                preserveHostHeader: true
            )),
            priority: 42
        )
        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(existingRule: existing))

        #expect(vm.existingID == existing.id)
        #expect(vm.name == "Existing")
        #expect(vm.method == .delete)
        #expect(vm.matchType == .wildcard)
        #expect(vm.urlText == "https://api.example.com/v1/*")
        #expect(vm.destScheme == "http")
        #expect(vm.destHost == "staging.example.com")
        #expect(vm.destPort == "8080")
        #expect(vm.destPath == "v2")
        #expect(vm.destQuery == "debug=true")
        #expect(vm.preserveOriginalURL)
        #expect(vm.preserveHost)
    }

    @Test("editor validation requires destination and valid port")
    func editorValidation() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Remote"
        vm.urlText = "https://api.example.com/*"

        #expect(!vm.isSaveEnabled)

        vm.destHost = "staging.example.com"
        #expect(vm.isSaveEnabled)

        vm.destPort = "abc"
        #expect(!vm.isSaveEnabled)

        vm.destPort = "70000"
        #expect(!vm.isSaveEnabled)

        #expect(vm.makeRule() == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test("editor rejects embedded ports and malformed hosts while accepting IPv6")
    func editorHostValidation() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Host validation"
        vm.urlText = "https://api.example.com/*"

        for invalidHost in [
            "staging.example.com:8443",
            "staging.example.com?debug=1",
            "staging.example.com#fragment",
            "staging.example.com%",
            "[::1",
        ] {
            vm.destHost = invalidHost
            #expect(!vm.isSaveEnabled, "Expected invalid host: \(invalidHost)")
            #expect(vm.hostValidationMessage != nil)
        }

        vm.destHost = "::1"
        #expect(vm.isSaveEnabled)
        let rawIPv6Rule = vm.makeRule()
        if case let .mapRemote(configuration) = rawIPv6Rule?.action {
            #expect(configuration.host == "::1")
        } else {
            Issue.record("Expected an IPv6 Map Remote rule")
        }
        vm.destHost = "[2001:db8::1]"
        #expect(vm.isSaveEnabled)
        let bracketedIPv6Rule = vm.makeRule()
        if case let .mapRemote(configuration) = bracketedIPv6Rule?.action {
            #expect(configuration.host == "2001:db8::1")
        } else {
            Issue.record("Expected a normalized IPv6 Map Remote rule")
        }
        vm.destHost = "staging.example.com"
        #expect(vm.isSaveEnabled)
    }

    @Test("editor saves wildcard rule with exact boundary when subpaths are off")
    func editorExactWildcardBoundaryWhenSubpathsOff() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Baseline"
        vm.urlText = "127.0.0.1:43210/rockxy-demo/environment"
        vm.matchType = .wildcard
        vm.includeSubpaths = false
        vm.destScheme = "HTTPS"
        vm.destHost = "httpbin.org"
        vm.destPath = "get"

        let rule = try #require(vm.makeRule())

        #expect(rule.matchCondition.urlPattern == #"127\.0\.0\.1:43210\/rockxy-demo\/environment($|[?#])"#)
        if case let .mapRemote(config) = rule.action {
            #expect(config.scheme == "https")
            #expect(config.host == "httpbin.org")
            #expect(config.path == "/get")
        } else {
            Issue.record("Expected Map Remote rule")
        }
    }

    @Test("editor destination summary describes overrides without inventing a host")
    func editorDestinationSummaryDescribesOverrides() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)

        // Nothing configured yet, and no fabricated example.com placeholder.
        #expect(!vm.destinationSummary.contains("example.com"))

        vm.destScheme = "http"
        vm.destHost = "staging.example.com"
        vm.destPort = "8080"
        vm.destPath = "api/v2"
        vm.destQuery = "debug=true"

        let summary = vm.destinationSummary
        #expect(summary.contains("scheme → http"))
        #expect(summary.contains("host → staging.example.com"))
        #expect(summary.contains("port → 8080"))
        #expect(summary.contains("path → /api/v2"))
        #expect(summary.contains("query → debug=true"))
    }

    @Test("editor destination summary merges a concrete draft source URL")
    func editorDestinationSummaryMergesDraftSource() throws {
        let sourceURL = try #require(URL(string: "https://api.prod.example.com/v2/users?page=1"))
        let draft = MapRemoteDraft(
            origin: .selectedTransaction,
            suggestedName: "Users",
            sourceURL: sourceURL,
            sourceHost: "api.prod.example.com",
            sourcePath: "/v2/users",
            sourceMethod: "GET"
        )
        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(draft: draft))
        vm.destHost = "staging.example.com"
        vm.destPath = "internal/users"

        // Host and path are overridden; scheme and query are inherited from the source.
        #expect(vm.destinationSummary == "https://staging.example.com/internal/users?page=1")
    }

    @Test("keep-original summary renders the effective request target")
    func editorDestinationSummaryKeepsOriginalTarget() throws {
        let sourceURL = try #require(URL(string: "https://api.example.com/original?source=1"))
        let draft = MapRemoteDraft(
            origin: .selectedTransaction,
            suggestedName: "Original",
            sourceURL: sourceURL,
            sourceHost: "api.example.com",
            sourcePath: "/original",
            sourceMethod: "GET"
        )
        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(draft: draft))
        vm.destHost = "staging.example.com"
        vm.destPath = "ignored"
        vm.destQuery = "ignored=true"
        vm.preserveOriginalURL = true

        #expect(
            vm.destinationSummary
                == "https://staging.example.com/original?source=1 The forwarded request keeps its original path and query."
        )
    }

    @Test("scheme override without a port uses the new scheme default in preview")
    func editorDestinationSummaryResetsInheritedPortForSchemeOverride() throws {
        let sourceURL = try #require(URL(string: "http://api.prod.example.com:8080/v2/users"))
        let draft = MapRemoteDraft(
            origin: .selectedTransaction,
            suggestedName: "Users",
            sourceURL: sourceURL,
            sourceHost: "api.prod.example.com",
            sourcePath: "/v2/users",
            sourceMethod: "GET"
        )
        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(draft: draft))
        vm.destScheme = "https"
        vm.destPort = ""

        #expect(vm.destinationSummary == "https://api.prod.example.com/v2/users")
    }

    @Test("destination preview safely encodes an incomplete percent query while typing")
    func editorDestinationSummarySafelyEncodesLiveQuery() throws {
        let sourceURL = try #require(URL(string: "https://api.prod.example.com/v2/users"))
        let draft = MapRemoteDraft(
            origin: .selectedTransaction,
            suggestedName: "Users",
            sourceURL: sourceURL,
            sourceHost: "api.prod.example.com",
            sourcePath: "/v2/users",
            sourceMethod: "GET"
        )
        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(draft: draft))
        vm.destQuery = "progress=100% ready"

        #expect(vm.destinationSummary == "https://api.prod.example.com/v2/users?progress=100%25%20ready")
    }

    @Test("editor persists authoring metadata alongside the compiled pattern")
    func editorPersistsAuthoringMetadata() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Metadata"
        vm.urlText = "https://api.example.com/v1/*"
        vm.matchType = .wildcard
        vm.includeSubpaths = false
        vm.destHost = "staging.example.com"

        let rule = try #require(vm.makeRule())
        #expect(rule.matchCondition.sourceURLPattern == "https://api.example.com/v1/*")
        #expect(rule.matchCondition.matchType == .wildcard)
        #expect(rule.matchCondition.includeSubpaths == false)
        #expect(rule.matchCondition.urlPattern == #"https:\/\/api\.example\.com\/v1\/.*($|[?#])"#)
    }

    @Test("wildcard rule with subpaths round-trips through save and reload")
    func wildcardSubpathsRoundTrip() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Subpaths"
        vm.urlText = "https://api.example.com/v1/*"
        vm.matchType = .wildcard
        vm.includeSubpaths = true
        vm.destHost = "staging.example.com"

        let saved = try #require(vm.makeRule())
        #expect(saved.matchCondition.includeSubpaths == true)

        let reopened = MapRemoteEditorViewModel()
        reopened.load(context: MapRemoteEditorContext(existingRule: saved))
        #expect(reopened.urlText == "https://api.example.com/v1/*")
        #expect(reopened.matchType == .wildcard)
        #expect(reopened.includeSubpaths)

        let resaved = try #require(reopened.makeRule())
        #expect(resaved.matchCondition.urlPattern == saved.matchCondition.urlPattern)
    }

    @Test("legacy compiled pattern remains a regex and re-saves verbatim")
    func legacyRegexRoundTrip() throws {
        // A legacy rule stored only the compiled pattern, with no authoring metadata.
        let compiled = #"127\.0\.0\.1:43210\/rockxy-demo\/environment($|[?#])"#
        let legacy = ProxyRule(
            name: "Legacy",
            matchCondition: RuleMatchCondition(urlPattern: compiled),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "httpbin.org", path: "/get"))
        )
        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(existingRule: legacy))

        #expect(vm.matchType == .regex)
        #expect(vm.includeSubpaths == false)
        #expect(vm.urlText == compiled)

        // Re-saving without touching the URL controls reproduces the identical pattern.
        let resaved = try #require(vm.makeRule())
        #expect(resaved.matchCondition.urlPattern == compiled)
    }

    @Test("legacy advanced regex ending in wildcard syntax is never reinterpreted")
    func legacyAdvancedRegexRoundTrip() throws {
        let compiled = #"https://api\.example\.com/v[0-9]+/.*"#
        let legacy = ProxyRule(
            name: "Advanced regex",
            matchCondition: RuleMatchCondition(urlPattern: compiled),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
        )
        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(existingRule: legacy))

        #expect(vm.matchType == .regex)
        #expect(vm.urlText == compiled)
        let resaved = try #require(vm.makeRule())
        #expect(resaved.matchCondition.urlPattern == compiled)
    }

    @Test("advanced regex rule round-trips through save and reload verbatim")
    func advancedRegexRoundTrip() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Regex"
        vm.urlText = #"https://api\.example\.com/v[0-9]+/users"#
        vm.matchType = .regex
        vm.destHost = "staging.example.com"

        let saved = try #require(vm.makeRule())
        #expect(saved.matchCondition.matchType == .regex)
        #expect(saved.matchCondition.urlPattern == #"https://api\.example\.com/v[0-9]+/users"#)

        let reopened = MapRemoteEditorViewModel()
        reopened.load(context: MapRemoteEditorContext(existingRule: saved))
        #expect(reopened.matchType == .regex)
        #expect(reopened.urlText == #"https://api\.example\.com/v[0-9]+/users"#)

        let resaved = try #require(reopened.makeRule())
        #expect(resaved.matchCondition.urlPattern == saved.matchCondition.urlPattern)
    }

    @Test("root destination path survives save and reopen")
    func rootDestinationPathRoundTrip() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Root"
        vm.urlText = "https://api.example.com/v1/*"
        vm.destHost = "staging.example.com"
        vm.destPath = "/"

        let saved = try #require(vm.makeRule())
        guard case let .mapRemote(savedConfiguration) = saved.action else {
            Issue.record("Expected Map Remote configuration")
            return
        }
        #expect(savedConfiguration.path == "/")

        let reopened = MapRemoteEditorViewModel()
        reopened.load(context: MapRemoteEditorContext(existingRule: saved))
        #expect(reopened.destPath == "/")

        let resaved = try #require(reopened.makeRule())
        guard case let .mapRemote(resavedConfiguration) = resaved.action else {
            Issue.record("Expected Map Remote configuration")
            return
        }
        #expect(resavedConfiguration.path == "/")
    }

    @Test("authored wildcard metadata still matches without a cached regex")
    func authoredWildcardMetadataMatchesWithoutCompiledCache() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Direct Match"
        vm.urlText = "https://api.example.com/v1/*"
        vm.matchType = .wildcard
        vm.includeSubpaths = false
        vm.destHost = "staging.example.com"

        let rule = try #require(vm.makeRule())
        let matchingURL = try #require(URL(string: "https://api.example.com/v1/users?debug=1"))
        let nonMatchingURL = try #require(URL(string: "https://api.example.com/v2/users"))

        #expect(rule.matchCondition.matches(method: "GET", url: matchingURL, headers: []))
        #expect(!rule.matchCondition.matches(method: "GET", url: nonMatchingURL, headers: []))
    }

    @Test("quota rejection keeps editor state and exposes an inline error")
    func quotaRejectionKeepsEditorState() async {
        await withSharedRuleStateRestored {
            let vm = MapRemoteEditorViewModel()
            vm.load(context: .blank)
            vm.name = "Keep this draft"
            vm.urlText = "https://api.example.com/*"
            vm.destHost = "staging.example.com"

            let accepted = await vm.save(using: RulePolicyGate(policy: MapRemoteQuotaPolicy(maxRules: 0)))

            #expect(!accepted)
            #expect(!vm.isSaving)
            #expect(vm.name == "Keep this draft")
            #expect(vm.urlText == "https://api.example.com/*")
            #expect(vm.destHost == "staging.example.com")
            #expect(vm.errorMessage != nil)
        }
    }

    // MARK: Private

    private func withSharedRuleStateRestored(_ body: () async -> Void) async {
        await RuleTestLock.shared.acquire()
        let rulesSnapshot = await RuleEngine.shared.allRules
        let enabledSnapshot = UserDefaults.standard.object(forKey: "mapRemoteToolEnabled") as? Bool

        await RuleSyncService.replaceAllRules([])
        await body()

        await RuleSyncService.replaceAllRules(rulesSnapshot)
        if let enabledSnapshot {
            await RuleSyncService.setMapRemoteToolEnabled(enabledSnapshot)
        } else {
            UserDefaults.standard.removeObject(forKey: "mapRemoteToolEnabled")
            await RuleEngine.shared.setMapRemoteToolEnabled(true)
        }
        await RuleTestLock.shared.release()
    }
}

private struct MapRemoteQuotaPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool: Int
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000

    init(maxRules: Int) {
        maxActiveRulesPerTool = maxRules
    }
}

// MARK: - MapRemoteGraphQLOperationTests

@MainActor
struct MapRemoteGraphQLOperationTests {
    @Test("A GraphQL request prefills its operation so the redirect targets one operation")
    func draftCarriesOperation() {
        let transaction = TestFixtures.makeGraphQLTransaction(operationName: "GetUsers")
        let draft = MapRemoteDraftBuilder.fromTransaction(transaction)
        #expect(draft.graphQLOperationName == "GetUsers")
        #expect(MapRemoteDraftBuilder.fromDomain("example.com").graphQLOperationName == nil)

        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(draft: draft))
        #expect(vm.graphQLOperationName == "GetUsers")
    }

    @Test("Saving stores the trimmed operation, and clearing it matches every request again")
    func saveAndReloadOperation() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Users to staging"
        vm.urlText = "https://api.example.com/graphql"
        vm.destHost = "staging.example.com"
        vm.graphQLOperationName = "  GetUsers "
        let rule = try #require(vm.makeRule())
        #expect(rule.matchCondition.graphQLOperationName == "GetUsers")

        let reloaded = MapRemoteEditorViewModel()
        reloaded.load(context: MapRemoteEditorContext(existingRule: rule))
        #expect(reloaded.graphQLOperationName == "GetUsers")

        reloaded.graphQLOperationName = " "
        let cleared = try #require(reloaded.makeRule())
        #expect(cleared.matchCondition.graphQLOperationName == nil)
    }
}
