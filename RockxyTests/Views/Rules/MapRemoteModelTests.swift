import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct MapRemoteModelTests {
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
            vm.allRules = [mapRemote, block]
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

    @Test("Enable All only enables Map Remote rules")
    func enableAllOnlyTouchesMapRemoteRules() async {
        await withSharedRuleStateRestored {
            let vm = MapRemoteWindowViewModel()
            let remote = ProxyRule(
                name: "Remote",
                isEnabled: false,
                matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
                action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
            )
            let block = ProxyRule(
                name: "Block",
                isEnabled: false,
                matchCondition: RuleMatchCondition(urlPattern: "https://blocked.example.com/.*"),
                action: .block(statusCode: 403)
            )
            vm.allRules = [remote, block]

            vm.enableAll()
            await vm.waitForPendingRuleSync()

            #expect(vm.allRules[0].isEnabled)
            #expect(vm.allRules[1].isEnabled == false)
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

    @Test("editor parses pasted destination URL into components")
    func editorParsesDestinationURL() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)

        vm.tryParseDestinationURL("https://api.production.com:8443/v2/api?id=123")

        #expect(vm.destScheme == "https")
        #expect(vm.destHost == "api.production.com")
        #expect(vm.destPort == "8443")
        #expect(vm.destPath == "v2/api")
        #expect(vm.destQuery == "id=123")
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
                method: "DELETE",
                headerName: "X-Debug",
                headerValue: "1"
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

    @Test("editor destination preview uses placeholders and normalized path")
    func editorDestinationPreview() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)

        #expect(vm.destinationPreviewString == "https://example.com/")

        vm.destScheme = "http"
        vm.destHost = "staging.example.com"
        vm.destPort = "8080"
        vm.destPath = "api/v2"
        vm.destQuery = "debug=true"

        #expect(vm.destinationPreviewString == "http://staging.example.com:8080/api/v2?debug=true")
    }

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
