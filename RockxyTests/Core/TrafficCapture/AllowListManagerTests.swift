import Foundation
@testable import Rockxy
import Testing

/// `AllowListManager` runtime-matching tests for **new user-authored rules**.
/// All matching tests (wildcard, regex, method filter, include-subpaths, URL truncation)
/// live here because the manager is the sole runtime matcher. Rules in these tests use
/// default case-sensitive regex semantics — case-insensitivity via inline `(?i)` is
/// exercised in `AllowListManagerMigrationTests`.
@MainActor
struct AllowListManagerTests {
    // MARK: Internal

    // MARK: - Inactive Master Toggle

    @Test
    func inactiveAllowsEverything() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com*"))
        manager.setActive(false)

        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/foo")))
        #expect(manager.isRequestAllowed(method: "POST", url: self.url("https://other.com/bar")))
        #expect(manager.isRequestAllowed(method: "DELETE", url: self.url("https://nothing.allow.com")))
    }

    // MARK: - Wildcard Matching

    @Test
    func wildcardStarMatchesPrefixAndSuffix() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("github", pattern: "*api.github.com*"))
        manager.setActive(true)

        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://api.github.com/user")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("http://api.github.com:8080/foo")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://gitlab.com/user")))
    }

    @Test
    func wildcardQuestionMarkMatchesSingleChar() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("version", pattern: "*example.com/v?/*"))
        manager.setActive(true)

        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/v1/users")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/v9/users")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/v10/users")))
    }

    @Test
    func wildcardIncludeSubpathsOn() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com/api", includeSubpaths: true))
        manager.setActive(true)

        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/api/users")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/api")))
    }

    @Test
    func wildcardIncludeSubpathsOff() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com/api", includeSubpaths: false))
        manager.setActive(true)

        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/api")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/api?q=1")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/api#frag")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/api/users")))
    }

    // MARK: - Regex Length Cap (ReDoS Defense)

    @Test
    func oversizedRegexPatternIsSkipped() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        // 3000 chars — over the 2048 defense-in-depth cap.
        let huge = String(repeating: "a", count: 3_000)
        manager.addRule(makeRegexRule("huge", pattern: huge))
        manager.setActive(true)

        // The oversized rule is skipped; nothing matches.
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://\(huge).com/")))
    }

    // MARK: - Regex Matching (Case-Sensitive by Default)

    @Test
    func regexDefaultIsCaseSensitive() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        // New user-authored rule — no (?i) prefix — must be case-sensitive.
        manager.addRule(makeRegexRule("github", pattern: "^https://api\\.github\\.com/.*$"))
        manager.setActive(true)

        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://api.github.com/user")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://API.GITHUB.COM/user")))
    }

    @Test
    func regexWithInlineCaseInsensitiveFlag() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        // User can opt into case-insensitivity via (?i) inline.
        manager.addRule(makeRegexRule("github", pattern: "(?i)^https://api\\.github\\.com/.*$"))
        manager.setActive(true)

        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://API.GITHUB.COM/user")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://api.github.com/user")))
    }

    // MARK: - Method Filter

    @Test
    func methodFilterAny() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com*", method: nil))
        manager.setActive(true)

        for method in ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"] {
            #expect(manager.isRequestAllowed(method: method, url: self.url("https://example.com/foo")))
        }
    }

    @Test
    func methodFilterSpecific() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com*", method: "POST"))
        manager.setActive(true)

        #expect(manager.isRequestAllowed(method: "POST", url: self.url("https://example.com/foo")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/foo")))
    }

    @Test
    func methodFilterIsUppercaseInsensitive() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com*", method: "POST"))
        manager.setActive(true)

        // Caller sends lowercase but manager uppercases internally.
        #expect(manager.isRequestAllowed(method: "post", url: self.url("https://example.com/foo")))
    }

    // MARK: - Enabled / Disabled Rules

    @Test
    func disabledRulesAreSkipped() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com*", enabled: false))
        manager.setActive(true)

        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/foo")))
    }

    @Test
    func toggleRuleAffectsMatching() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com*"))
        manager.setActive(true)
        let id = manager.rules[0].id

        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/foo")))

        manager.toggleRule(id: id)
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/foo")))

        manager.toggleRule(id: id)
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com/foo")))
    }

    // MARK: - CRUD

    @Test
    func addRuleAppends() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        #expect(manager.rules.isEmpty)
        manager.addRule(makeWildcardRule("a", pattern: "*a.com*"))
        manager.addRule(makeWildcardRule("b", pattern: "*b.com*"))
        #expect(manager.rules.count == 2)
        #expect(manager.rules[0].name == "a")
        #expect(manager.rules[1].name == "b")
    }

    @Test
    func updateRuleReplacesByID() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("original", pattern: "*a.com*"))
        let id = manager.rules[0].id

        var updated = manager.rules[0]
        updated.name = "renamed"
        updated.rawPattern = "*renamed.com*"
        manager.updateRule(updated)

        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].id == id)
        #expect(manager.rules[0].name == "renamed")
        #expect(manager.rules[0].rawPattern == "*renamed.com*")
    }

    @Test
    func removeRuleByID() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("a", pattern: "*a.com*"))
        manager.addRule(makeWildcardRule("b", pattern: "*b.com*"))
        let firstID = manager.rules[0].id

        manager.removeRule(id: firstID)
        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].name == "b")
    }

    @Test
    func replaceAllReplacesWholeList() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("old", pattern: "*old.com*"))

        let newRules = [
            makeWildcardRule("x", pattern: "*x.com*"),
            makeWildcardRule("y", pattern: "*y.com*"),
        ]
        manager.replaceAll(newRules)

        #expect(manager.rules.count == 2)
        #expect(manager.rules.map(\.name) == ["x", "y"])
    }

    // MARK: - Invalid Regex Is Skipped

    @Test
    func invalidRegexRuleIsSkippedOnCacheRebuild() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeRegexRule("valid", pattern: "^https://api\\.example\\.com.*$"))
        manager.addRule(makeRegexRule("invalid", pattern: "^[unclosed")) // broken regex
        manager.setActive(true)

        // Valid rule still matches; invalid rule is silently skipped.
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://api.example.com/foo")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://other.com/foo")))
    }

    // MARK: - URL Length Truncation

    @Test
    func urlLengthTruncatedAtProxyLimit() throws {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("api", pattern: "*example.com*"))
        manager.setActive(true)

        // Build a URL longer than ProxyLimits.maxURILength.
        let longPath = String(repeating: "a", count: ProxyLimits.maxURILength * 2)
        let longURL = try #require(URL(string: "https://example.com/\(longPath)"))
        // Host is still near the beginning, so truncation preserves the match.
        #expect(manager.isRequestAllowed(method: "GET", url: longURL))
    }

    // MARK: - Persistence Round-Trip

    @Test
    func schemaV2RoundTrip() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let writer = AllowListManager(storageURL: tempURL)
        writer.addRule(makeWildcardRule("a", pattern: "*a.com*"))
        writer.addRule(makeRegexRule("b", pattern: "^https://b\\.com.*$", method: "POST"))
        writer.setActive(true)

        let reader = AllowListManager(storageURL: tempURL)
        #expect(reader.isActive)
        #expect(reader.rules.count == 2)
        #expect(reader.rules[0].name == "a")
        #expect(reader.rules[0].matchType == .wildcard)
        #expect(reader.rules[1].name == "b")
        #expect(reader.rules[1].matchType == .regex)
        #expect(reader.rules[1].method == "POST")
    }

    // MARK: - Import / Export

    @Test
    func exportAndImportNewSchema() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(makeWildcardRule("a", pattern: "*a.com*"))
        manager.setActive(true)
        guard let data = manager.exportRulesJSON() else {
            Issue.record("exportRulesJSON returned nil")
            return
        }

        let (target, targetURL) = makeManager()
        defer { cleanup(targetURL) }
        do {
            try target.importRulesJSON(data)
        } catch {
            Issue.record("importRulesJSON threw: \(error)")
            return
        }

        #expect(target.rules.count == 1)
        #expect(target.rules[0].name == "a")
        #expect(target.isActive)
    }

    @Test
    func importMalformedJSONThrows() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        let garbage = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try manager.importRulesJSON(garbage)
        }
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeManager() -> (AllowListManager, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        return (AllowListManager(storageURL: url), url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        let legacy = url.deletingLastPathComponent().appendingPathComponent("allow-list.legacy.json")
        try? FileManager.default.removeItem(at: legacy)
    }

    private func makeWildcardRule(
        _ name: String,
        pattern: String,
        method: String? = nil,
        includeSubpaths: Bool = true,
        enabled: Bool = true
    )
        -> AllowListRule
    {
        AllowListRule(
            name: name,
            isEnabled: enabled,
            rawPattern: pattern,
            method: method,
            matchType: .wildcard,
            includeSubpaths: includeSubpaths
        )
    }

    private func makeRegexRule(
        _ name: String,
        pattern: String,
        method: String? = nil,
        enabled: Bool = true
    )
        -> AllowListRule
    {
        AllowListRule(
            name: name,
            isEnabled: enabled,
            rawPattern: pattern,
            method: method,
            matchType: .regex,
            includeSubpaths: true
        )
    }

    private func url(_ s: String) -> URL {
        URL(string: s)!
    }
}
