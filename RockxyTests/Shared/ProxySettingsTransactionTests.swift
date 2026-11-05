import Foundation
@testable import Rockxy
import SystemConfiguration
import Testing

// Tests for the pure decision layer behind the helper's single-transaction proxy writes: which
// keys, which values, which service, and when to fall back. The SystemConfiguration shell needs
// root and cannot run here; everything it executes is decided by what these tests pin.

// MARK: - ProxySettingsTransactionFixtures

enum ProxySettingsTransactionFixtures {
    typealias Fixtures = ProxyRecoveryJournalFixtures

    /// Keys the old command path never wrote. They must come through every write untouched.
    static let untouchedKeys: [String: Any] = [
        ProxySettingsKey.excludeSimpleHostnames: NSNumber(value: 1),
        "FTPPassive": NSNumber(value: 1),
        "FTPEnable": NSNumber(value: 0),
        "HTTPUser": "someone",
    ]

    /// Targets that exercise every branch of the old restore: all modes captured, an endpoint
    /// with no host, one with no port, PAC on without a URL, everything off, an empty bypass list.
    static let restoreTargets: [ProxyServiceRestorationState] = [
        Fixtures.capturedSettings,
        restoration(
            http: ProxyEndpointState(enabled: true, host: "", port: 8_080),
            https: ProxyEndpointState(enabled: true, host: "secure.corp.example", port: 0),
            socks: ProxyEndpointState(enabled: false, host: "", port: 0)
        ),
        restoration(pacEnabled: true, pacURL: ""),
        restoration(pacEnabled: false, pacURL: "https://proxy.corp.example/config.pac"),
        restoration(autoDiscoveryEnabled: true),
        restoration(bypassDomains: []),
        restoration(
            http: ProxyEndpointState(enabled: false, host: "proxy.corp.example", port: 8_080),
            https: ProxyEndpointState(enabled: false, host: "proxy.corp.example", port: 8_080),
            socks: ProxyEndpointState(enabled: false, host: "socks.corp.example", port: 1_080)
        ),
    ]

    /// The dictionary a service holds when it reads as `state`, plus the keys no write may touch.
    static func dictionary(for state: ProxyServiceRestorationState) -> [String: Any] {
        var dictionary: [String: Any] = [
            ProxySettingsKey.httpEnable: NSNumber(value: state.http.enabled ? 1 : 0),
            ProxySettingsKey.httpHost: state.http.host,
            ProxySettingsKey.httpPort: NSNumber(value: state.http.port),
            ProxySettingsKey.httpsEnable: NSNumber(value: state.https.enabled ? 1 : 0),
            ProxySettingsKey.httpsHost: state.https.host,
            ProxySettingsKey.httpsPort: NSNumber(value: state.https.port),
            ProxySettingsKey.socksEnable: NSNumber(value: state.socks.enabled ? 1 : 0),
            ProxySettingsKey.socksHost: state.socks.host,
            ProxySettingsKey.socksPort: NSNumber(value: state.socks.port),
            ProxySettingsKey.pacEnable: NSNumber(value: state.pacEnabled ? 1 : 0),
            ProxySettingsKey.pacURL: state.pacURL,
            ProxySettingsKey.autoDiscoveryEnable: NSNumber(value: state.autoDiscoveryEnabled ? 1 : 0),
            ProxySettingsKey.exceptionsList: state.bypassDomains,
        ]
        for (key, value) in untouchedKeys {
            dictionary[key] = value
        }
        return dictionary
    }

    static func read(_ dictionary: [String: Any], service: String = Fixtures.service) -> ProxyServiceRestorationState? {
        ProxyDictionaryReader.restorationState(service: service, from: dictionary)
    }

    static func restoration(
        http: ProxyEndpointState = ProxyEndpointState(enabled: false, host: "", port: 0),
        https: ProxyEndpointState = ProxyEndpointState(enabled: false, host: "", port: 0),
        socks: ProxyEndpointState = ProxyEndpointState(enabled: false, host: "", port: 0),
        pacEnabled: Bool = false,
        pacURL: String = "",
        autoDiscoveryEnabled: Bool = false,
        bypassDomains: [String] = ["localhost", "*.local"]
    )
        -> ProxyServiceRestorationState
    {
        ProxyServiceRestorationState(
            service: Fixtures.service,
            http: http,
            https: https,
            socks: socks,
            pacEnabled: pacEnabled,
            pacURL: pacURL,
            autoDiscoveryEnabled: autoDiscoveryEnabled,
            bypassDomains: bypassDomains
        )
    }

    static func item(
        _ service: String,
        writes: [ProxyKeyWrite] = ProxyWritePlan.bypass(["localhost"]),
        admission: ProxyAdmission = .equals(Fixtures.rockxyOverride)
    )
        -> ProxyTransactionItem
    {
        ProxyTransactionItem(service: service, writes: writes, admission: admission)
    }
}

// MARK: - ProxyWritePlanTests

struct ProxyWritePlanTests {
    typealias Fixtures = ProxyRecoveryJournalFixtures
    typealias Support = ProxySettingsTransactionFixtures

    @Test("Every key is the SDK's own constant")
    func keysMatchTheSDK() {
        #expect(ProxySettingsKey.httpEnable == kSCPropNetProxiesHTTPEnable as String)
        #expect(ProxySettingsKey.httpHost == kSCPropNetProxiesHTTPProxy as String)
        #expect(ProxySettingsKey.httpPort == kSCPropNetProxiesHTTPPort as String)
        #expect(ProxySettingsKey.httpsEnable == kSCPropNetProxiesHTTPSEnable as String)
        #expect(ProxySettingsKey.httpsHost == kSCPropNetProxiesHTTPSProxy as String)
        #expect(ProxySettingsKey.httpsPort == kSCPropNetProxiesHTTPSPort as String)
        #expect(ProxySettingsKey.socksEnable == kSCPropNetProxiesSOCKSEnable as String)
        #expect(ProxySettingsKey.socksHost == kSCPropNetProxiesSOCKSProxy as String)
        #expect(ProxySettingsKey.socksPort == kSCPropNetProxiesSOCKSPort as String)
        #expect(ProxySettingsKey.pacEnable == kSCPropNetProxiesProxyAutoConfigEnable as String)
        #expect(ProxySettingsKey.pacURL == kSCPropNetProxiesProxyAutoConfigURLString as String)
        #expect(ProxySettingsKey.autoDiscoveryEnable == kSCPropNetProxiesProxyAutoDiscoveryEnable as String)
        #expect(ProxySettingsKey.exceptionsList == kSCPropNetProxiesExceptionsList as String)
        #expect(ProxySettingsKey.excludeSimpleHostnames == kSCPropNetProxiesExcludeSimpleHostnames as String)
    }

    @Test("A restore leaves exactly the settings the journal expects, for every capture shape")
    func restoreMatchesTheJournalsExpectedResult() {
        for target in Support.restoreTargets {
            let pre = Fixtures.rockxyOverride
            let written = ProxyWritePlan.apply(
                ProxyWritePlan.restore(to: target),
                to: Support.dictionary(for: pre)
            )
            let expected = ProxyServiceRestorationState.expectedRestorationResult(target: target, from: pre)
            #expect(Support.read(written) == expected)
        }
    }

    @Test("A restore ends in the last state the old command-by-command sequence ends in")
    func restoreMatchesTheLegacySequence() throws {
        for target in Support.restoreTargets {
            let pre = Fixtures.rockxyOverride
            let legacyFinal = try #require(
                ProxyRestoreTransition.reachableStates(from: pre, target: target).last
            )
            let written = ProxyWritePlan.apply(
                ProxyWritePlan.restore(to: target),
                to: Support.dictionary(for: pre)
            )
            #expect(Support.read(written) == legacyFinal)
        }
    }

    @Test("An override ends in the last state the old seven-command sequence ends in")
    func overrideMatchesTheLegacySequence() throws {
        for captured in [Fixtures.capturedSettings, Support.restoration(), Fixtures.restoredSettings] {
            let legacyFinal = try #require(
                ProxyOverrideTransition.reachableStates(from: captured, port: 9_090).last
            )
            let written = ProxyWritePlan.apply(
                ProxyWritePlan.override(port: 9_090),
                to: Support.dictionary(for: captured)
            )
            #expect(Support.read(written) == legacyFinal)
        }
    }

    @Test("Keys the old commands never wrote survive every write unchanged")
    func untouchedKeysSurvive() {
        let start = Support.dictionary(for: Fixtures.rockxyOverride)
        let writes = [
            ProxyWritePlan.restore(to: Fixtures.capturedSettings),
            ProxyWritePlan.override(port: 9_090),
            ProxyWritePlan.bypass([]),
        ]
        for plan in writes {
            let written = ProxyWritePlan.apply(plan, to: start) as NSDictionary
            for (key, value) in Support.untouchedKeys {
                #expect((written[key] as AnyObject).isEqual(value), "\(key) changed")
            }
        }
        #expect(!writes.flatMap { $0 }.contains { $0.key == ProxySettingsKey.excludeSimpleHostnames })
    }

    @Test("Bypass lists keep their order and an empty list is an empty array")
    func bypassValues() {
        let ordered = ["b.example", "a.example", "*.local"]
        #expect(ProxyWritePlan.bypass(ordered).first?.value == .strings(ordered))
        let cleared = ProxyWritePlan.apply(ProxyWritePlan.bypass([]), to: [:])
        #expect((cleared[ProxySettingsKey.exceptionsList] as? [String])?.isEmpty == true)
    }

    @Test("Flags and ports are numbers, never booleans")
    func valuesAreCFNumbers() {
        let writes = ProxyWritePlan.restore(to: Fixtures.capturedSettings) + ProxyWritePlan.override(port: 9_090)
        for write in writes {
            guard case .number = write.value else {
                continue
            }
            let object = write.value.foundationValue as AnyObject
            #expect(CFGetTypeID(object) == CFNumberGetTypeID(), "\(write.key) is not a CFNumber")
        }
    }

    @Test("A well-formed plan is accepted and malformed values are refused")
    func rejection() {
        #expect(ProxyWritePlan.rejection(of: ProxyWritePlan.restore(to: Fixtures.capturedSettings)) == nil)
        #expect(ProxyWritePlan.rejection(of: ProxyWritePlan.override(port: 9_090)) == nil)
        #expect(ProxyWritePlan.rejection(of: ProxyWritePlan.bypass([])) == nil)

        let tooManyDomains = (0 ..< 501).map { "h\($0).example" }
        let oversizeList = (0 ..< 400).map { _ in String(repeating: "a", count: 200) }
        let refused: [[ProxyKeyWrite]] = [
            ProxyWritePlan.override(port: 0),
            ProxyWritePlan.override(port: 70_000),
            [ProxyKeyWrite(key: ProxySettingsKey.httpHost, value: .string("host\0evil"))],
            [ProxyKeyWrite(key: ProxySettingsKey.httpHost, value: .string("host\nevil"))],
            [ProxyKeyWrite(key: ProxySettingsKey.pacURL, value: .string(String(repeating: "u", count: 9_000)))],
            [ProxyKeyWrite(key: ProxySettingsKey.httpEnable, value: .number(2))],
            [ProxyKeyWrite(key: "HTTPUser", value: .string("anything"))],
            [ProxyKeyWrite(key: ProxySettingsKey.excludeSimpleHostnames, value: .number(1))],
            ProxyWritePlan.bypass(tooManyDomains),
            ProxyWritePlan.bypass(oversizeList),
            ProxyWritePlan.bypass(["ok.example", "bad\u{7F}entry"]),
        ]
        for writes in refused {
            #expect(ProxyWritePlan.rejection(of: writes) == .writeRejected)
        }
    }
}

// MARK: - ProxyDictionaryReaderTests

struct ProxyDictionaryReaderTests {
    typealias Fixtures = ProxyRecoveryJournalFixtures
    typealias Support = ProxySettingsTransactionFixtures

    @Test("A stored dictionary reads back as the state it was built from")
    func roundTrip() {
        for state in Support.restoreTargets + [Fixtures.rockxyOverride] {
            #expect(Support.read(Support.dictionary(for: state)) == state)
        }
    }

    @Test("Absent keys read as off, empty and zero, the way networksetup prints them")
    func absentKeysReadAsDefaults() {
        let state = Support.read([:])
        #expect(state == Support.restoration(bypassDomains: []))
    }

    @Test("Padding is trimmed the way networksetup output is, so a blank PAC URL reads as empty")
    func paddingIsTrimmed() {
        var dictionary = Support.dictionary(for: Support.restoration(bypassDomains: []))
        dictionary[ProxySettingsKey.pacURL] = " "
        dictionary[ProxySettingsKey.httpHost] = " 127.0.0.1 "
        dictionary[ProxySettingsKey.exceptionsList] = [" localhost ", "", ProxyBypassDomainOutput.emptyListPrefix]
        let state = Support.read(dictionary)
        #expect(state?.pacURL == "")
        #expect(state?.http.host == "127.0.0.1")
        #expect(state?.bypassDomains == ["localhost"])
    }

    @Test("A value of the wrong type or range makes the whole state unreadable")
    func unexpectedSchemaIsNil() {
        let base = Support.dictionary(for: Fixtures.rockxyOverride)
        let corrupted: [(String, Any)] = [
            (ProxySettingsKey.httpEnable, "yes"),
            (ProxySettingsKey.httpEnable, NSNumber(value: 7)),
            (ProxySettingsKey.httpPort, "9090"),
            (ProxySettingsKey.httpPort, NSNumber(value: 70_000)),
            (ProxySettingsKey.httpPort, NSNumber(value: -1)),
            (ProxySettingsKey.httpHost, NSNumber(value: 1)),
            (ProxySettingsKey.exceptionsList, "localhost"),
            (ProxySettingsKey.exceptionsList, [1, 2]),
        ]
        for (key, value) in corrupted {
            var dictionary = base
            dictionary[key] = value
            #expect(Support.read(dictionary) == nil, "\(key) = \(value)")
        }
    }
}

// MARK: - ProxyServiceResolutionTests

struct ProxyServiceResolutionTests {
    // MARK: Internal

    @Test("A unique name resolves to its identifier")
    func unique() {
        #expect(ProxyServiceResolution.resolve("Wi-Fi", among: candidates) == .resolved(id: "A"))
        #expect(ProxyServiceResolution.resolve("USB 10/100/1000 LAN", among: candidates) == .resolved(id: "B"))
    }

    @Test("Two services with one display name are ambiguous and are never guessed between")
    func duplicateNames() {
        #expect(ProxyServiceResolution.resolve("Ethernet Adapter (en5)", among: candidates) == .ambiguous)
    }

    @Test("A service that is not there, or only differs in case or padding, is missing")
    func missing() {
        #expect(ProxyServiceResolution.resolve("Gone", among: candidates) == .missing)
        #expect(ProxyServiceResolution.resolve("wi-fi", among: candidates) == .missing)
        #expect(ProxyServiceResolution.resolve("Wi-Fi ", among: candidates) == .missing)
        #expect(ProxyServiceResolution.resolve("Wi-Fi", among: []) == .missing)
    }

    // MARK: Private

    private let candidates = [
        ProxyServiceCandidate(id: "A", name: "Wi-Fi"),
        ProxyServiceCandidate(id: "B", name: "USB 10/100/1000 LAN"),
        ProxyServiceCandidate(id: "C", name: "Ethernet Adapter (en5)"),
        ProxyServiceCandidate(id: "D", name: "Ethernet Adapter (en5)"),
    ]
}

// MARK: - ProxyTransactionPlanTests

struct ProxyTransactionPlanTests {
    // MARK: Internal

    typealias Fixtures = ProxyRecoveryJournalFixtures
    typealias Support = ProxySettingsTransactionFixtures

    @Test("An empty service list prepares nothing")
    func empty() {
        let plan = ProxyTransactionPlan.prepare(items: [], candidates: candidates)
        #expect(plan.ready.isEmpty)
        #expect(plan.declined.isEmpty)
    }

    @Test("Ready services keep request order and carry their identifier")
    func readyOrder() {
        let plan = ProxyTransactionPlan.prepare(
            items: [Support.item("Thunderbolt Bridge"), Support.item("Wi-Fi")],
            candidates: candidates
        )
        #expect(plan.ready.map(\.item.service) == ["Thunderbolt Bridge", "Wi-Fi"])
        #expect(plan.ready.map(\.serviceID) == ["B", "A"])
        #expect(plan.declined.isEmpty)
    }

    @Test("A service that disappeared, a shared name and a refused write are declined, not dropped")
    func declined() {
        let badWrites = [ProxyKeyWrite(key: ProxySettingsKey.httpHost, value: .string("a\0b"))]
        let plan = ProxyTransactionPlan.prepare(
            items: [
                Support.item("Wi-Fi"),
                Support.item("Gone"),
                Support.item("Twin"),
                Support.item("Thunderbolt Bridge", writes: badWrites),
            ],
            candidates: candidates
        )
        #expect(plan.ready.map(\.item.service) == ["Wi-Fi"])
        #expect(plan.declined == [
            "Gone": .serviceMissing,
            "Twin": .serviceAmbiguous,
            "Thunderbolt Bridge": .writeRejected,
        ])
    }

    @Test("A service requested twice is written for neither request")
    func duplicateRequest() {
        let plan = ProxyTransactionPlan.prepare(
            items: [Support.item("Wi-Fi"), Support.item("Thunderbolt Bridge"), Support.item("Wi-Fi")],
            candidates: candidates
        )
        #expect(plan.ready.map(\.item.service) == ["Thunderbolt Bridge"])
        #expect(plan.declined == ["Wi-Fi": .serviceAmbiguous])
    }

    @Test("Inside the lock, settings that are still the baseline are written")
    func admissionAccepts() throws {
        let ready = try #require(
            ProxyTransactionPlan.prepare(items: [Support.item("Wi-Fi")], candidates: candidates).ready.first
        )
        let stored = Support.dictionary(for: Fixtures.rockxyOverride)
        #expect(ProxyTransactionPlan.decline(ready, storedConfiguration: stored) == nil)
    }

    @Test("Inside the lock, settings someone changed since the read are declined")
    func admissionDeclinesChange() throws {
        let ready = try #require(
            ProxyTransactionPlan.prepare(items: [Support.item("Wi-Fi")], candidates: candidates).ready.first
        )
        var stored = Support.dictionary(for: Fixtures.rockxyOverride)
        stored[ProxySettingsKey.httpPort] = NSNumber(value: 1_234)
        #expect(ProxyTransactionPlan.decline(ready, storedConfiguration: stored) == .stateChanged)
    }

    @Test("Inside the lock, a dictionary this layer cannot read is declined")
    func admissionDeclinesUnreadable() throws {
        let ready = try #require(
            ProxyTransactionPlan.prepare(items: [Support.item("Wi-Fi")], candidates: candidates).ready.first
        )
        var stored = Support.dictionary(for: Fixtures.rockxyOverride)
        stored[ProxySettingsKey.httpPort] = "9090"
        #expect(ProxyTransactionPlan.decline(ready, storedConfiguration: stored) == .unexpectedSchema)
    }

    // MARK: Private

    private let candidates = [
        ProxyServiceCandidate(id: "A", name: "Wi-Fi"),
        ProxyServiceCandidate(id: "B", name: "Thunderbolt Bridge"),
        ProxyServiceCandidate(id: "C", name: "Twin"),
        ProxyServiceCandidate(id: "D", name: "Twin"),
    ]
}

// MARK: - ProxyRestoreAdmissionTests

/// The crash analysis, as assertions. The commit is atomic, so a process that dies leaves a
/// service in exactly one of two shapes; the journal's own policy must read each one correctly.
struct ProxyRestoreAdmissionTests {
    // MARK: Internal

    typealias Fixtures = ProxyRecoveryJournalFixtures
    typealias Support = ProxySettingsTransactionFixtures

    @Test("Before the commit the service is untouched and the journal licenses the write again")
    func crashBeforeCommit() {
        #expect(ProxyAdmission.restoreContinuation(inFlight).admits(Fixtures.rockxyOverride))
        #expect(
            ProxyServiceRecoveryPolicy.continuation(for: inFlight, live: Fixtures.rockxyOverride) == .restore
        )
    }

    @Test("After the commit the service is finished and the journal drops it without writing")
    func crashAfterCommit() {
        let written = ProxyWritePlan.apply(
            ProxyWritePlan.restore(to: Fixtures.capturedSettings),
            to: Support.dictionary(for: Fixtures.rockxyOverride)
        )
        let live = Support.read(written)
        #expect(live == inFlight.expectedPostStepState)
        #expect(ProxyServiceRecoveryPolicy.continuation(for: inFlight, live: live) == .complete)
        #expect(!ProxyAdmission.restoreContinuation(inFlight).admits(Fixtures.restoredSettings))
    }

    @Test("A service someone re-pointed is not admitted")
    func foreignChange() {
        var foreign = Support.dictionary(for: Fixtures.rockxyOverride)
        foreign[ProxySettingsKey.httpHost] = "someone.else.example"
        let live = Support.read(foreign)
        #expect(live.map { !ProxyAdmission.restoreContinuation(inFlight).admits($0) } == true)
    }

    // MARK: Private

    private let inFlight = Fixtures.entry(stage: .inFlight)
}

// MARK: - ProxyFallbackPolicyTests

struct ProxyFallbackPolicyTests {
    @Test("An empty request resolves to nothing under every outcome")
    func emptyRequest() {
        let outcomes: [ProxyTransactionOutcome] = [
            .committed(services: [], declined: [:]),
            .notCommitted(reason: .lockBusy),
            .indeterminate(reason: .timedOut),
        ]
        for outcome in outcomes {
            let resolution = ProxyFallbackPolicy.resolve(requested: [], outcome: outcome)
            #expect(resolution.written.isEmpty)
            #expect(resolution.fallback.isEmpty)
        }
    }

    @Test("A landed commit writes the services it names")
    func committed() {
        let resolution = ProxyFallbackPolicy.resolve(
            requested: ["Wi-Fi", "LAN"],
            outcome: .committed(services: ["LAN", "Wi-Fi"], declined: [:])
        )
        #expect(resolution.written == ["Wi-Fi", "LAN"])
        #expect(resolution.fallback.isEmpty)
    }

    @Test("A service declined before the commit goes to networksetup with its reason")
    func declinedService() {
        let resolution = ProxyFallbackPolicy.resolve(
            requested: ["Wi-Fi", "Gone", "LAN"],
            outcome: .committed(services: ["Wi-Fi", "LAN"], declined: ["Gone": .serviceMissing])
        )
        #expect(resolution.written == ["Wi-Fi", "LAN"])
        #expect(resolution.fallback.map(\.service) == ["Gone"])
        #expect(resolution.fallback.map(\.reason) == [.serviceMissing])
    }

    @Test("A service the commit neither wrote nor declined is never read as written")
    func unaccountedService() {
        let resolution = ProxyFallbackPolicy.resolve(
            requested: ["Wi-Fi", "LAN"],
            outcome: .committed(services: ["Wi-Fi"], declined: [:])
        )
        #expect(resolution.written == ["Wi-Fi"])
        #expect(resolution.fallback.map(\.reason) == [.notInCommit])
    }

    @Test("A name only the commit knows about is not reported as written")
    func unrequestedService() {
        let resolution = ProxyFallbackPolicy.resolve(
            requested: ["Wi-Fi"],
            outcome: .committed(services: ["Wi-Fi", "Intruder"], declined: [:])
        )
        #expect(resolution.written == ["Wi-Fi"])
    }

    @Test("Lock contention, a refused commit, a timeout and an unreadable schema fall back wholesale")
    func wholesaleFallback() {
        let reasons: [ProxyFallbackReason] = [
            .lockBusy, .commitRefused, .timedOut, .unexpectedSchema, .sessionUnavailable, .noEligibleService,
        ]
        for reason in reasons {
            for outcome in [
                ProxyTransactionOutcome.notCommitted(reason: reason),
                ProxyTransactionOutcome.indeterminate(reason: reason),
            ] {
                let resolution = ProxyFallbackPolicy.resolve(requested: ["Wi-Fi", "LAN"], outcome: outcome)
                #expect(resolution.written.isEmpty)
                #expect(resolution.fallback.map(\.service) == ["Wi-Fi", "LAN"])
                #expect(resolution.fallback.allSatisfy { $0.reason == reason })
            }
        }
    }

    @Test("Finished settings are rewritten by the fallback after a refused apply or a deadline, and only then")
    func rewriteAfterApplyRefusal() {
        #expect(ProxyFallbackPolicy.rewritesFinishedSettings(after: .applyRefused))
        #expect(ProxyFallbackPolicy.rewritesFinishedSettings(after: .timedOut))
        #expect(!ProxyFallbackPolicy.rewritesFinishedSettings(after: .stateChanged))
        #expect(!ProxyFallbackPolicy.rewritesFinishedSettings(after: .lockBusy))
    }
}

// MARK: - ProxyFallbackCarryThroughTests

struct ProxyFallbackCarryThroughTests {
    typealias Support = ProxySettingsTransactionFixtures

    @Test("A batch-wide refusal keeps each service's own reason for declining")
    func notCommittedKeepsDeclinedReasons() {
        let resolution = ProxyFallbackPolicy.resolve(
            requested: ["Wi-Fi", "Gone", "Twin"],
            outcome: .notCommitted(
                reason: .noEligibleService,
                declined: ["Gone": .serviceMissing, "Twin": .serviceAmbiguous, "Wi-Fi": .stateChanged]
            )
        )
        #expect(resolution.written.isEmpty)
        #expect(resolution.fallback.map(\.reason) == [.stateChanged, .serviceMissing, .serviceAmbiguous])
    }

    @Test("After a landed commit that was not applied only the committed services are rewritten")
    func indeterminateSeparatesCommittedFromDeclined() {
        let resolution = ProxyFallbackPolicy.resolve(
            requested: ["Wi-Fi", "Gone"],
            outcome: .indeterminate(reason: .applyRefused, declined: ["Gone": .serviceMissing])
        )
        let reasons = Dictionary(uniqueKeysWithValues: resolution.fallback.map { ($0.service, $0.reason) })
        #expect(reasons["Wi-Fi"] == .applyRefused)
        #expect(reasons["Gone"] == .serviceMissing)
        #expect(ProxyFallbackPolicy.rewritesFinishedSettings(after: reasons["Wi-Fi"] ?? .stateChanged))
        #expect(!ProxyFallbackPolicy.rewritesFinishedSettings(after: reasons["Gone"] ?? .applyRefused))
    }

    @Test("A timed-out transaction sends every service back with a reason that rewrites finished settings")
    func timedOutRewrites() {
        let resolution = ProxyFallbackPolicy.resolve(
            requested: ["Wi-Fi", "LAN"],
            outcome: .indeterminate(reason: .timedOut)
        )
        #expect(resolution.fallback.allSatisfy { ProxyFallbackPolicy.rewritesFinishedSettings(after: $0.reason) })
    }

    @Test("A service listed twice keeps the more specific reason its first listing earned")
    func duplicateKeepsFirstReason() {
        let bad = [ProxyKeyWrite(key: ProxySettingsKey.httpHost, value: .string("a\0b"))]
        let plan = ProxyTransactionPlan.prepare(
            items: [Support.item("Wi-Fi", writes: bad), Support.item("Wi-Fi")],
            candidates: [ProxyServiceCandidate(id: "A", name: "Wi-Fi")]
        )
        #expect(plan.ready.isEmpty)
        #expect(plan.declined == ["Wi-Fi": .writeRejected])
    }
}

// MARK: - ProxyMayWriteOverTests

struct ProxyMayWriteOverTests {
    // MARK: Internal

    typealias Fixtures = ProxyRecoveryJournalFixtures

    @Test("The state a write produces is the baseline with only that write applied")
    func expectedState() {
        #expect(landed?.bypassDomains == ["landed.example"])
        #expect(landed?.http == baseline.http)
    }

    @Test("Settings still at the baseline may always be written")
    func atBaseline() {
        for reason in [ProxyFallbackReason.stateChanged, .lockBusy, .timedOut, .applyRefused] {
            #expect(ProxyFallbackPolicy.mayWriteOver(live: baseline, baseline: baseline, writes: writes, after: reason))
        }
    }

    @Test("A write that already landed is re-issued after a refused apply or a deadline")
    func landedWriteIsReissued() {
        for reason in [ProxyFallbackReason.applyRefused, .timedOut] {
            #expect(ProxyFallbackPolicy.mayWriteOver(live: landed, baseline: baseline, writes: writes, after: reason))
        }
    }

    @Test("A finished-looking state is somebody else's change after any other reason")
    func landedWriteWithoutReason() {
        for reason in [ProxyFallbackReason.stateChanged, .lockBusy, .commitRefused, .serviceMissing] {
            #expect(!ProxyFallbackPolicy.mayWriteOver(live: landed, baseline: baseline, writes: writes, after: reason))
        }
    }

    @Test("Settings that are neither the baseline nor the write's result, or unreadable, are never written over")
    func foreignOrUnreadable() {
        let foreign = Fixtures.capturedSettings
        #expect(!ProxyFallbackPolicy.mayWriteOver(live: foreign, baseline: baseline, writes: writes, after: .timedOut))
        #expect(!ProxyFallbackPolicy.mayWriteOver(live: nil, baseline: baseline, writes: writes, after: .timedOut))
    }

    // MARK: Private

    private let baseline = Fixtures.rockxyOverride
    private let writes = ProxyWritePlan.bypass(["landed.example"])

    private var landed: ProxyServiceRestorationState? {
        ProxyWritePlan.expectedState(applying: writes, to: baseline)
    }
}

// MARK: - InMemoryDebtStore

private final class InMemoryDebtStore: ProxyApplyDebtStore {
    var state: ProxyApplyDebtState = .none
    var failsToSave = false

    func load() -> ProxyApplyDebtState {
        state
    }

    func save(_ debt: ProxyApplyDebt) throws {
        if failsToSave {
            throw CocoaError(.fileWriteNoPermission)
        }
        state = .owed(debt)
    }

    func clear(ifID id: String?) throws {
        guard let id else {
            state = .none
            return
        }
        if case let .owed(current) = state, current.id == id {
            state = .none
        }
    }
}

// MARK: - ProxyApplyDebtLedgerTests

struct ProxyApplyDebtLedgerTests {
    @Test("The debt is on disk before the commit, so a process death after it leaves a record")
    func recordedBeforeCommit() throws {
        let store = InMemoryDebtStore()
        let recorded = try ProxyApplyDebtLedger.record(services: ["Wi-Fi", "LAN"], ownedPort: 9_090, in: store)
        #expect(store.state == .owed(recorded.debt))
        #expect(recorded.debt.services == ["LAN", "Wi-Fi"])
        #expect(recorded.debt.ownedPort == 9_090)
    }

    @Test("When the debt cannot be stored recording throws, so no commit follows")
    func unrecordableDebtBlocksTheCommit() {
        let store = InMemoryDebtStore()
        store.failsToSave = true
        #expect(throws: (any Error).self) {
            try ProxyApplyDebtLedger.record(services: ["Wi-Fi"], ownedPort: nil, in: store)
        }
        #expect(store.state == .none)
    }

    @Test("Process death between commit and apply: the next operation applies and clears the record")
    func recoveryAfterProcessDeath() throws {
        let store = InMemoryDebtStore()
        _ = try ProxyApplyDebtLedger.record(services: ["Wi-Fi"], ownedPort: 9_090, in: store)
        // The process dies here: no confirmApplied, no discard. A fresh process finds the record.
        var applies = 0
        let settlement = ProxyApplyDebtLedger.settle(in: store) {
            applies += 1
            return true
        }
        #expect(settlement == .settled)
        #expect(applies == 1)
        #expect(store.state == .none)
    }

    @Test("A deadline that falls between commit and apply leaves the debt for the same recovery")
    func recoveryAfterTimeout() throws {
        let store = InMemoryDebtStore()
        _ = try ProxyApplyDebtLedger.record(services: ["Wi-Fi"], ownedPort: nil, in: store)
        // The writer returns .indeterminate(.timedOut) and does not touch the record.
        #expect(store.state != .none)
        #expect(ProxyApplyDebtLedger.settle(in: store) { true } == .settled)
    }

    @Test("An apply that fails keeps the record and reports it is still owed")
    func failedSettleKeepsRecord() throws {
        let store = InMemoryDebtStore()
        _ = try ProxyApplyDebtLedger.record(services: ["Wi-Fi"], ownedPort: nil, in: store)
        #expect(ProxyApplyDebtLedger.settle(in: store) { false } == .stillOwed)
        #expect(store.state != .none)
    }

    @Test("Nothing owed means no apply is attempted")
    func nothingOwed() {
        var applies = 0
        let settlement = ProxyApplyDebtLedger.settle(in: InMemoryDebtStore()) {
            applies += 1
            return true
        }
        #expect(settlement == .nothingOwed)
        #expect(applies == 0)
    }

    @Test("A record that cannot be read is treated as owed and removed after a confirmed apply")
    func unreadableRecord() {
        let store = InMemoryDebtStore()
        store.state = .unreadable
        #expect(ProxyApplyDebtLedger.settle(in: store) { false } == .stillOwed)
        #expect(store.state == .unreadable)
        #expect(ProxyApplyDebtLedger.settle(in: store) { true } == .settled)
        #expect(store.state == .none)
    }

    @Test("A confirmed apply clears the debt; a commit that never landed leaves nothing behind")
    func confirmAndDiscard() throws {
        let store = InMemoryDebtStore()
        let applied = try ProxyApplyDebtLedger.record(services: ["Wi-Fi"], ownedPort: nil, in: store)
        ProxyApplyDebtLedger.confirmApplied(applied, in: store)
        #expect(store.state == .none)

        let refused = try ProxyApplyDebtLedger.record(services: ["Wi-Fi"], ownedPort: nil, in: store)
        ProxyApplyDebtLedger.discardUncommitted(refused, in: store)
        #expect(store.state == .none)
    }

    @Test("A debt that predates a refused commit survives it, and a second transaction merges into it")
    func priorDebtSurvives() throws {
        let store = InMemoryDebtStore()
        _ = try ProxyApplyDebtLedger.record(services: ["Wi-Fi"], ownedPort: 9_090, in: store)
        let second = try ProxyApplyDebtLedger.record(services: ["LAN"], ownedPort: nil, in: store)
        #expect(second.hadPriorDebt)
        #expect(second.debt.services == ["LAN", "Wi-Fi"])
        #expect(second.debt.ownedPort == 9_090)
        ProxyApplyDebtLedger.discardUncommitted(second, in: store)
        #expect(store.state == .owed(second.debt))
    }

    @Test("An orphaned job confirming late cannot erase a newer transaction's debt")
    func orphanCannotEraseNewerDebt() throws {
        let store = InMemoryDebtStore()
        let orphan = try ProxyApplyDebtLedger.record(services: ["Wi-Fi"], ownedPort: nil, in: store)
        let newer = try ProxyApplyDebtLedger.record(services: ["LAN"], ownedPort: nil, in: store)
        ProxyApplyDebtLedger.confirmApplied(orphan, in: store)
        #expect(store.state == .owed(newer.debt))
    }
}

// MARK: - ProxyEffectiveSettingsTests

struct ProxyEffectiveSettingsTests {
    // MARK: Internal

    @Test("An override still in force on the owned port is recognised")
    func stillInForce() {
        #expect(ProxyEffectiveSettings.pointsAtLoopback(port: 9_090, effective: effective()))
        #expect(ProxyEffectiveSettings.pointsAtLoopback(
            port: 9_090,
            effective: [
                ProxySettingsKey.httpsEnable: NSNumber(value: 1),
                ProxySettingsKey.httpsHost: "127.0.0.1",
                ProxySettingsKey.httpsPort: NSNumber(value: 9_090),
            ]
        ))
    }

    @Test("A disabled, foreign or differently-ported proxy, or an empty reading, is not the override")
    func notTheOverride() {
        #expect(!ProxyEffectiveSettings.pointsAtLoopback(port: 9_090, effective: effective(enabled: 0)))
        #expect(!ProxyEffectiveSettings.pointsAtLoopback(port: 9_090, effective: effective(host: "proxy.corp.example")))
        #expect(!ProxyEffectiveSettings.pointsAtLoopback(port: 9_090, effective: effective(port: 8_080)))
        #expect(!ProxyEffectiveSettings.pointsAtLoopback(port: 9_090, effective: [:]))
    }

    // MARK: Private

    private func effective(enabled: Int = 1, host: String = "127.0.0.1", port: Int = 9_090) -> [String: Any] {
        [
            ProxySettingsKey.httpEnable: NSNumber(value: enabled),
            ProxySettingsKey.httpHost: host,
            ProxySettingsKey.httpPort: NSNumber(value: port),
        ]
    }
}

// MARK: - ProxyFastReadTests

/// The rule that lets the restore read through SystemConfiguration: the fast reading may confirm
/// that a restore proceeds, and nothing else. Every other answer is the `networksetup` reader's.
struct ProxyFastReadTests {
    // MARK: Internal

    typealias Fixtures = ProxyRecoveryJournalFixtures
    typealias Support = ProxySettingsTransactionFixtures

    @Test("Stored dictionaries parse to the states the networksetup reader would give, and an unreadable one is absent")
    func statesFromStored() {
        var broken = Support.dictionary(for: Fixtures.rockxyOverride)
        broken[ProxySettingsKey.httpPort] = "9090"
        let states = ProxyFastRead.states(from: [
            "Wi-Fi": Support.dictionary(for: Fixtures.rockxyOverride),
            "Broken": broken,
        ])
        #expect(states["Wi-Fi"] == Fixtures.rockxyOverride)
        #expect(states["Broken"] == nil)
    }

    @Test("A fast reading that lets the restore proceed is used and networksetup is never run")
    func fastProceedSkipsTheAuthoritativeRead() {
        var authoritativeReads = 0
        let live = ProxyFastRead.liveState(
            for: inFlight,
            fast: { Fixtures.rockxyOverride },
            authoritative: {
                authoritativeReads += 1
                return nil
            }
        )
        #expect(live == Fixtures.rockxyOverride)
        #expect(authoritativeReads == 0)
    }

    @Test("A fast reading that says finished is confirmed by networksetup, whose answer stands")
    func fastFinishedIsConfirmed() {
        var authoritativeReads = 0
        let live = ProxyFastRead.liveState(
            for: inFlight,
            fast: { inFlight.expectedPostStepState },
            authoritative: {
                authoritativeReads += 1
                return Fixtures.rockxyOverride
            }
        )
        #expect(authoritativeReads == 1)
        #expect(live == Fixtures.rockxyOverride)
    }

    @Test("A fast reading that disagrees with the plan hands the decision to networksetup, even to say nothing")
    func fastDisagreementDefers() {
        var foreign = Support.dictionary(for: Fixtures.rockxyOverride)
        foreign[ProxySettingsKey.httpHost] = "someone.else.example"
        var authoritativeReads = 0
        let live = ProxyFastRead.liveState(
            for: inFlight,
            fast: { Support.read(foreign) },
            authoritative: {
                authoritativeReads += 1
                return nil
            }
        )
        #expect(authoritativeReads == 1)
        #expect(live == nil)
        #expect(ProxyServiceRecoveryPolicy.continuation(for: inFlight, live: live) == .retryLater)
    }

    @Test("A service the fast reader could not read is read by networksetup")
    func fastUnreadableFallsBack() {
        let live = ProxyFastRead.liveState(
            for: inFlight,
            fast: { nil },
            authoritative: { Fixtures.rockxyOverride }
        )
        #expect(live == Fixtures.rockxyOverride)
    }

    @Test("When every service proceeds on the fast reading, networksetup is not asked about any")
    func planWithoutFallbackReads() {
        var asked: [[String]] = []
        let plan = ProxyFastRead.plan(
            targets: targets,
            journal: [],
            fastStates: overridden(targets),
            ownedPort: Fixtures.rockxyPort,
            authoritative: {
                asked.append($0)
                return [:]
            }
        )
        #expect(plan.entriesToRestore.map(\.service) == names)
        #expect(asked.isEmpty)
    }

    @Test("The fast plan is the plan the authoritative readings would have produced")
    func planMatchesTheAuthoritativePlan() {
        let live = overridden(targets)
        let expected = ProxyRecoveryPlanner.plan(
            targets: targets,
            journal: [],
            liveStates: live,
            ownedPort: Fixtures.rockxyPort
        )
        let fast = ProxyFastRead.plan(
            targets: targets,
            journal: [],
            fastStates: live,
            ownedPort: Fixtures.rockxyPort,
            authoritative: { _ in [:] }
        )
        #expect(fast == expected)
    }

    @Test("A service whose fast reading disagrees is asked about alone, and the authoritative reading decides")
    func disagreeingServiceIsConfirmed() {
        let disputed = names[2]
        var fast = overridden(targets)
        fast[disputed] = Fixtures.renamed(Fixtures.capturedSettings, to: disputed)
        var asked: [[String]] = []

        // networksetup says the service is still Rockxy's: the fast reading was wrong, and the
        // restore proceeds for it.
        let confirmedOwned = ProxyFastRead.plan(
            targets: targets,
            journal: [],
            fastStates: fast,
            ownedPort: Fixtures.rockxyPort,
            authoritative: { requested in
                asked.append(requested)
                return requested.reduce(into: [:]) { $0[$1] = overridden(targets)[$1] }
            }
        )
        #expect(asked == [[disputed]])
        #expect(confirmedOwned.entriesToRestore.map(\.service) == names)

        // networksetup agrees the service is not Rockxy's: it is left out, never written.
        let confirmedForeign = ProxyFastRead.plan(
            targets: targets,
            journal: [],
            fastStates: fast,
            ownedPort: Fixtures.rockxyPort,
            authoritative: { requested in
                requested.reduce(into: [:]) { $0[$1] = fast[$1] }
            }
        )
        #expect(confirmedForeign.entriesToRestore.map(\.service) == names.filter { $0 != disputed })
        #expect(confirmedForeign.deferredServices == [disputed])
    }

    @Test("A service neither reader can read is deferred, not restored")
    func unreadableEverywhere() {
        let missing = names[1]
        var fast = overridden(targets)
        fast[missing] = nil
        let plan = ProxyFastRead.plan(
            targets: targets,
            journal: [],
            fastStates: fast,
            ownedPort: Fixtures.rockxyPort,
            authoritative: { _ in [:] }
        )
        #expect(plan.entriesToRestore.map(\.service) == names.filter { $0 != missing })
        #expect(plan.deferredServices == [missing])
    }

    @Test("A service the fast reader sees as already restored is confirmed before it is called complete")
    func restoredIsConfirmed() {
        let done = names[0]
        var fast = overridden(targets)
        fast[done] = Fixtures.renamed(Fixtures.capturedSettings, to: done)
        var asked: [[String]] = []
        let plan = ProxyFastRead.plan(
            targets: targets,
            journal: [],
            fastStates: fast,
            ownedPort: Fixtures.rockxyPort,
            authoritative: {
                asked.append($0)
                return [:]
            }
        )
        #expect(asked == [[done]])
        #expect(!plan.entriesToRestore.map(\.service).contains(done))
    }

    // MARK: Private

    private let names = ["Wi-Fi", "Ethernet", "Thunderbolt Bridge", "USB 10/100/1000 LAN"]

    private var targets: [ProxyServiceRestorationState] {
        names.map { Fixtures.renamed(Fixtures.capturedSettings, to: $0) }
    }

    private var inFlight: ProxyServiceRecoveryJournalEntry {
        Fixtures.entry(stage: .inFlight)
    }

    /// Each target as it reads while Rockxy's override is on it.
    private func overridden(_ targets: [ProxyServiceRestorationState]) -> [String: ProxyServiceRestorationState] {
        targets.reduce(into: [:]) { states, target in
            states[target.service] = ProxyOverrideTransition.reachableStates(
                from: target,
                port: Fixtures.rockxyPort
            ).last
        }
    }
}
