import Foundation

// Pure decision layer for writing system proxy settings in one SystemConfiguration transaction.
// Nothing here touches SystemConfiguration or a process: which keys, which values, which service,
// whether to fall back. The helper's thin shell (`ProxySystemConfigurationWriter`) only executes
// what this file decides, which is what makes it testable without root.

// MARK: - ProxySettingsKey

/// The keys of a service's `Proxies` dictionary, as declared in `SCSchemaDefinitions.h`
/// (`kSCPropNetProxies*`). They are spelled out here so this file stays free of the framework;
/// a test pins every one of them to the SDK constant.
enum ProxySettingsKey {
    static let httpEnable = "HTTPEnable"
    static let httpHost = "HTTPProxy"
    static let httpPort = "HTTPPort"
    static let httpsEnable = "HTTPSEnable"
    static let httpsHost = "HTTPSProxy"
    static let httpsPort = "HTTPSPort"
    static let socksEnable = "SOCKSEnable"
    static let socksHost = "SOCKSProxy"
    static let socksPort = "SOCKSPort"
    static let pacEnable = "ProxyAutoConfigEnable"
    static let pacURL = "ProxyAutoConfigURLString"
    static let autoDiscoveryEnable = "ProxyAutoDiscoveryEnable"
    static let exceptionsList = "ExceptionsList"

    /// Deliberately absent from every write: `networksetup` has no command for it, so the old
    /// path never changed it, and neither may this one. Listed so the omission is explicit.
    static let excludeSimpleHostnames = "ExcludeSimpleHostnames"
}

// MARK: - ProxyPropertyValue

/// A value of a `Proxies` property, limited to the three shapes the schema uses.
enum ProxyPropertyValue: Equatable {
    case number(Int)
    case string(String)
    case strings([String])

    // MARK: Internal

    /// The Foundation object stored in the dictionary. `Int` bridges to a `CFNumber`, which is
    /// what the schema asks for; a `Bool` would become a `CFBoolean`, which it does not.
    var foundationValue: Any {
        switch self {
        case let .number(value):
            NSNumber(value: value)
        case let .string(value):
            value
        case let .strings(value):
            value
        }
    }
}

// MARK: - ProxyKeyWrite

struct ProxyKeyWrite: Equatable {
    let key: String
    let value: ProxyPropertyValue

    static func flag(_ key: String, _ isOn: Bool) -> ProxyKeyWrite {
        ProxyKeyWrite(key: key, value: .number(isOn ? 1 : 0))
    }
}

// MARK: - ProxyFallbackReason

/// Why a service (or the whole batch) was handed back to the `networksetup` path.
enum ProxyFallbackReason: Equatable {
    // Per service, decided before anything is written.
    case serviceMissing
    case serviceAmbiguous
    case unexpectedSchema
    case stateChanged
    case writeRejected

    // Whole batch.
    case sessionUnavailable
    case lockBusy
    case commitRefused
    case applyRefused
    case timedOut
    case noEligibleService
    case notInCommit
    /// The durable record that an apply is owed could not be stored, so nothing was committed.
    case applyDebtUnrecorded
}

// MARK: - ProxyWritePlan

/// The keys each existing `networksetup` write sequence ends up changing, collapsed into one
/// ordered list. Later entries replace earlier ones for the same key, exactly as later commands
/// replaced earlier ones.
///
/// Every list is a read-modify-write: keys not named here (`ExcludeSimpleHostnames`, the FTP,
/// RTSP, Gopher and authentication keys, anything a newer macOS adds) keep whatever the service
/// already holds, which is what the per-field commands did.
enum ProxyWritePlan {
    // MARK: Internal

    /// What `disableProxyStates` + `applyServiceProxyState` + `restoreBypassDomains` leave behind.
    ///
    /// The mapping mirrors `ProxyServiceRestorationState.expectedRestorationResult` field by
    /// field, which is what the journal compares against: an endpoint that names no host or no
    /// port is only switched off, and the PAC URL is written only when PAC was on and had one.
    static func restore(to target: ProxyServiceRestorationState) -> [ProxyKeyWrite] {
        var writes: [ProxyKeyWrite] = [
            .flag(ProxySettingsKey.httpEnable, false),
            .flag(ProxySettingsKey.httpsEnable, false),
            .flag(ProxySettingsKey.socksEnable, false),
            .flag(ProxySettingsKey.pacEnable, false),
            .flag(ProxySettingsKey.autoDiscoveryEnable, false),
        ]

        writes += endpoint(
            target.http,
            enable: ProxySettingsKey.httpEnable,
            host: ProxySettingsKey.httpHost,
            port: ProxySettingsKey.httpPort
        )
        writes += endpoint(
            target.https,
            enable: ProxySettingsKey.httpsEnable,
            host: ProxySettingsKey.httpsHost,
            port: ProxySettingsKey.httpsPort
        )
        writes += endpoint(
            target.socks,
            enable: ProxySettingsKey.socksEnable,
            host: ProxySettingsKey.socksHost,
            port: ProxySettingsKey.socksPort
        )

        if target.pacEnabled {
            if !target.pacURL.isEmpty {
                writes.append(ProxyKeyWrite(key: ProxySettingsKey.pacURL, value: .string(target.pacURL)))
            }
            writes.append(.flag(ProxySettingsKey.pacEnable, true))
        }
        if target.autoDiscoveryEnabled {
            writes.append(.flag(ProxySettingsKey.autoDiscoveryEnable, true))
        }

        writes += bypass(target.bypassDomains)
        return writes
    }

    /// What `applyOverride` leaves behind: Rockxy's loopback endpoint on HTTP and HTTPS, and the
    /// other three modes off.
    static func override(port: Int) -> [ProxyKeyWrite] {
        let loopback = ProxyOverrideTransition.loopbackHost
        return [
            ProxyKeyWrite(key: ProxySettingsKey.httpHost, value: .string(loopback)),
            ProxyKeyWrite(key: ProxySettingsKey.httpPort, value: .number(port)),
            .flag(ProxySettingsKey.httpEnable, true),
            ProxyKeyWrite(key: ProxySettingsKey.httpsHost, value: .string(loopback)),
            ProxyKeyWrite(key: ProxySettingsKey.httpsPort, value: .number(port)),
            .flag(ProxySettingsKey.httpsEnable, true),
            .flag(ProxySettingsKey.socksEnable, false),
            .flag(ProxySettingsKey.pacEnable, false),
            .flag(ProxySettingsKey.autoDiscoveryEnable, false),
        ]
    }

    /// What `-setproxybypassdomains` stores. `networksetup` takes the word `Empty` for "no
    /// domains". Unverified without root: whether it stores `ExceptionsList = []` or removes the
    /// key. Services on a machine that has used it hold an empty array, which suggests the former,
    /// but the two read identically here (an absent list reads as empty), so nothing depends on it.
    static func bypass(_ domains: [String]) -> [ProxyKeyWrite] {
        [ProxyKeyWrite(key: ProxySettingsKey.exceptionsList, value: .strings(domains))]
    }

    /// Applies `writes` in order to a copy of `existing`, touching nothing else.
    static func apply(_ writes: [ProxyKeyWrite], to existing: [String: Any]) -> [String: Any] {
        var result = existing
        for write in writes {
            result[write.key] = write.value.foundationValue
        }
        return result
    }

    /// The settings `state` reads as after `writes` land, so a caller can recognise a write that
    /// already landed (a commit that outlived its deadline, say) without a second parser.
    static func expectedState(
        applying writes: [ProxyKeyWrite],
        to state: ProxyServiceRestorationState
    )
        -> ProxyServiceRestorationState?
    {
        let stored: [String: Any] = [
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
        return ProxyDictionaryReader.restorationState(
            service: state.service,
            from: apply(writes, to: stored)
        )
    }

    /// Why a write list must not go through SystemConfiguration, or nil when it may.
    ///
    /// This is a gate on the new path only. A list that fails it is handed to `networksetup`
    /// exactly as before, so a refusal here never widens what is written and never loses a write.
    static func rejection(of writes: [ProxyKeyWrite]) -> ProxyFallbackReason? {
        var seenKeys = Set<String>()
        for write in writes {
            seenKeys.insert(write.key)
            switch write.value {
            case let .number(value):
                guard isValid(number: value, forKey: write.key) else {
                    return .writeRejected
                }
            case let .string(value):
                guard isValid(text: value, limit: maximumTextBytes) else {
                    return .writeRejected
                }
            case let .strings(values):
                guard values.count <= maximumListEntries,
                      ProxyBypassDomainValidator.fitsTotalByteBound(values),
                      values.allSatisfy({ isValid(text: $0, limit: maximumListEntryBytes) }) else
                {
                    return .writeRejected
                }
            }
        }
        return knownKeys.isSuperset(of: seenKeys) ? nil : .writeRejected
    }

    // MARK: Private

    private static let maximumTextBytes = 8_192
    private static let maximumListEntries = 500
    private static let maximumListEntryBytes = 253

    private static let portKeys: Set<String> = [
        ProxySettingsKey.httpPort,
        ProxySettingsKey.httpsPort,
        ProxySettingsKey.socksPort,
    ]
    private static let flagKeys: Set<String> = [
        ProxySettingsKey.httpEnable,
        ProxySettingsKey.httpsEnable,
        ProxySettingsKey.socksEnable,
        ProxySettingsKey.pacEnable,
        ProxySettingsKey.autoDiscoveryEnable,
    ]
    private static let textKeys: Set<String> = [
        ProxySettingsKey.httpHost,
        ProxySettingsKey.httpsHost,
        ProxySettingsKey.socksHost,
        ProxySettingsKey.pacURL,
    ]
    private static let knownKeys: Set<String> = portKeys
        .union(flagKeys)
        .union(textKeys)
        .union([ProxySettingsKey.exceptionsList])

    private static func endpoint(
        _ state: ProxyEndpointState,
        enable: String,
        host: String,
        port: String
    )
        -> [ProxyKeyWrite]
    {
        guard state.isWritable else {
            return []
        }
        return [
            ProxyKeyWrite(key: host, value: .string(state.host)),
            ProxyKeyWrite(key: port, value: .number(state.port)),
            .flag(enable, state.enabled),
        ]
    }

    private static func isValid(number: Int, forKey key: String) -> Bool {
        if flagKeys.contains(key) {
            return number == 0 || number == 1
        }
        if portKeys.contains(key) {
            return (1 ... 65_535).contains(number)
        }
        return false
    }

    /// Text is stored verbatim, so it must be text a person could have typed: no NUL, no line
    /// break, no other control character, and bounded.
    private static func isValid(text: String, limit: Int) -> Bool {
        text.utf8.count <= limit
            && !text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}

// MARK: - ProxyDictionaryReader

/// Turns a stored `Proxies` dictionary into the same `ProxyServiceRestorationState` the
/// `networksetup` readers produce, so one policy can judge either.
///
/// It returns nil rather than guessing whenever a value has an unexpected type or range. A nil
/// is never treated as "unchanged": the caller declines the SystemConfiguration path for that
/// service and the authoritative `networksetup` read decides.
///
/// Whitespace is trimmed the way `networksetup`'s output is parsed. That matters: a PAC URL
/// holding a single space reads as an empty one on the old path, and as itself here unless trimmed.
enum ProxyDictionaryReader {
    // MARK: Internal

    static func restorationState(
        service: String,
        from dictionary: [String: Any]
    )
        -> ProxyServiceRestorationState?
    {
        guard let httpEnabled = flag(ProxySettingsKey.httpEnable, in: dictionary),
              let httpsEnabled = flag(ProxySettingsKey.httpsEnable, in: dictionary),
              let socksEnabled = flag(ProxySettingsKey.socksEnable, in: dictionary),
              let pacEnabled = flag(ProxySettingsKey.pacEnable, in: dictionary),
              let autoDiscovery = flag(ProxySettingsKey.autoDiscoveryEnable, in: dictionary),
              let httpHost = text(ProxySettingsKey.httpHost, in: dictionary),
              let httpsHost = text(ProxySettingsKey.httpsHost, in: dictionary),
              let socksHost = text(ProxySettingsKey.socksHost, in: dictionary),
              let pacURL = text(ProxySettingsKey.pacURL, in: dictionary),
              let httpPort = port(ProxySettingsKey.httpPort, in: dictionary),
              let httpsPort = port(ProxySettingsKey.httpsPort, in: dictionary),
              let socksPort = port(ProxySettingsKey.socksPort, in: dictionary),
              let bypass = list(ProxySettingsKey.exceptionsList, in: dictionary) else
        {
            return nil
        }

        return ProxyServiceRestorationState(
            service: service,
            http: ProxyEndpointState(enabled: httpEnabled, host: httpHost, port: httpPort),
            https: ProxyEndpointState(enabled: httpsEnabled, host: httpsHost, port: httpsPort),
            socks: ProxyEndpointState(enabled: socksEnabled, host: socksHost, port: socksPort),
            pacEnabled: pacEnabled,
            pacURL: pacURL,
            autoDiscoveryEnabled: autoDiscovery,
            bypassDomains: bypass
        )
    }

    // MARK: Private

    /// Absent reads as off, as `networksetup` prints it. Only 0 and 1 are flags.
    private static func flag(_ key: String, in dictionary: [String: Any]) -> Bool? {
        guard let raw = dictionary[key] else {
            return false
        }
        guard let number = raw as? NSNumber, number.intValue == 0 || number.intValue == 1 else {
            return nil
        }
        return number.intValue == 1
    }

    private static func text(_ key: String, in dictionary: [String: Any]) -> String? {
        guard let raw = dictionary[key] else {
            return ""
        }
        guard let value = raw as? String else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func port(_ key: String, in dictionary: [String: Any]) -> Int? {
        guard let raw = dictionary[key] else {
            return 0
        }
        guard let number = raw as? NSNumber, (0 ... 65_535).contains(number.intValue) else {
            return nil
        }
        return number.intValue
    }

    /// Same normalisation as `ProxyBypassDomainOutput.parse`, applied to the stored array.
    private static func list(_ key: String, in dictionary: [String: Any]) -> [String]? {
        guard let raw = dictionary[key] else {
            return []
        }
        guard let values = raw as? [String] else {
            return nil
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(ProxyBypassDomainOutput.emptyListPrefix) }
    }
}

// MARK: - ProxyServiceCandidate

/// One service as SystemConfiguration lists it: a stable identifier and the user-facing name.
struct ProxyServiceCandidate: Equatable {
    let id: String
    let name: String
}

// MARK: - ProxyServiceResolution

/// How a service name, the identity the rest of the helper and the recovery journal use, maps to
/// a SystemConfiguration service identifier.
///
/// Only an exact, unique name resolves. `networksetup` addresses services by name and has its own
/// way of choosing between two services that share one; rather than guess whether this layer
/// would choose the same one, an ambiguous or missing name is handed to `networksetup`, so the
/// service written is always the service that would have been written before. Unverified without
/// root: whether `networksetup` matches names case-insensitively. This layer is exact `==`, so a
/// name differing only in case is declined here and left to `networksetup` to resolve.
enum ProxyServiceResolution: Equatable {
    case resolved(id: String)
    case ambiguous
    case missing

    // MARK: Internal

    static func resolve(_ name: String, among candidates: [ProxyServiceCandidate]) -> ProxyServiceResolution {
        let matches = candidates.filter { $0.name == name }
        switch matches.count {
        case 0:
            return .missing
        case 1:
            return .resolved(id: matches[0].id)
        default:
            return .ambiguous
        }
    }
}

// MARK: - ProxyAdmission

/// The condition a service must still satisfy, read inside the locked transaction, for its write
/// to go ahead. The batch is prepared from reads taken earlier; this is the check made while no
/// other writer can commit.
enum ProxyAdmission {
    /// A restore: the live settings must still be ones the recorded step authorises writing over.
    case restoreContinuation(ProxyServiceRecoveryJournalEntry)
    /// An override or bypass update: the live settings must still equal what was read as baseline.
    case equals(ProxyServiceRestorationState)

    // MARK: Internal

    func admits(_ live: ProxyServiceRestorationState) -> Bool {
        switch self {
        case let .restoreContinuation(entry):
            ProxyServiceRecoveryPolicy.continuation(for: entry, live: live) == .restore
        case let .equals(baseline):
            live == baseline
        }
    }
}

// MARK: - ProxyTransactionItem

struct ProxyTransactionItem {
    let service: String
    let writes: [ProxyKeyWrite]
    let admission: ProxyAdmission
}

// MARK: - ProxyTransactionPlan

/// The part of a batch that can go through SystemConfiguration, and the part that cannot.
struct ProxyTransactionPlan {
    struct Ready {
        let item: ProxyTransactionItem
        let serviceID: String
    }

    let ready: [Ready]
    let declined: [String: ProxyFallbackReason]

    /// Splits `items` before any lock is taken. A service is declined, never silently dropped,
    /// when it is listed twice, has no unique SystemConfiguration identity, or carries a write
    /// the gate refuses.
    static func prepare(items: [ProxyTransactionItem], candidates: [ProxyServiceCandidate]) -> ProxyTransactionPlan {
        var ready: [Ready] = []
        var declined: [String: ProxyFallbackReason] = [:]
        var seen = Set<String>()

        for item in items {
            guard seen.insert(item.service).inserted else {
                // The first occurrence's own reason, if it had one, is the more specific answer.
                if declined[item.service] == nil {
                    declined[item.service] = .serviceAmbiguous
                }
                ready.removeAll { $0.item.service == item.service }
                continue
            }
            if let reason = ProxyWritePlan.rejection(of: item.writes) {
                declined[item.service] = reason
                continue
            }
            switch ProxyServiceResolution.resolve(item.service, among: candidates) {
            case let .resolved(id):
                ready.append(Ready(item: item, serviceID: id))
            case .ambiguous:
                declined[item.service] = .serviceAmbiguous
            case .missing:
                declined[item.service] = .serviceMissing
            }
        }
        return ProxyTransactionPlan(ready: ready, declined: declined)
    }

    /// The in-lock decision for one ready service given its stored `Proxies` dictionary: a
    /// reason to decline it, or nil to write it. A dictionary this layer cannot read, or settings
    /// the admission no longer accepts, both decline.
    static func decline(_ ready: Ready, storedConfiguration: [String: Any]) -> ProxyFallbackReason? {
        guard let live = ProxyDictionaryReader.restorationState(
            service: ready.item.service,
            from: storedConfiguration
        ) else {
            return .unexpectedSchema
        }
        return ready.item.admission.admits(live) ? nil : .stateChanged
    }
}

// MARK: - ProxyTransactionOutcome

/// What the SystemConfiguration shell reports.
enum ProxyTransactionOutcome: Equatable {
    /// The commit landed and was applied. `declined` services were left out before the commit.
    case committed(services: [String], declined: [String: ProxyFallbackReason])
    /// Nothing was written. The preferences on disk are exactly as they were.
    /// `declined` keeps the per-service reasons gathered before the batch-wide one applied; in the
    /// field it is the only record of why the fast path passed on a service.
    case notCommitted(reason: ProxyFallbackReason, declined: [String: ProxyFallbackReason] = [:])
    /// A commit or apply may have taken effect. The target values are idempotent, so the same
    /// services are written again by `networksetup`, which also settles the apply. `declined`
    /// names the services that were never part of the commit; they keep their own reasons.
    case indeterminate(reason: ProxyFallbackReason, declined: [String: ProxyFallbackReason] = [:])
}

// MARK: - ProxyBatchResolution

struct ProxyBatchResolution: Equatable {
    /// Services whose write is done: the commit included them.
    let written: [String]
    /// Services that must still go through `networksetup`, with why. Order follows the request.
    let fallback: [(service: String, reason: ProxyFallbackReason)]

    static func == (lhs: ProxyBatchResolution, rhs: ProxyBatchResolution) -> Bool {
        lhs.written == rhs.written
            && lhs.fallback.map(\.service) == rhs.fallback.map(\.service)
            && lhs.fallback.map(\.reason) == rhs.fallback.map(\.reason)
    }
}

// MARK: - ProxyFallbackPolicy

enum ProxyFallbackPolicy {
    /// The fallback trigger. A requested service is `written` only when a landed commit named
    /// it; every other outcome, and any service the commit did not name, goes to `networksetup`.
    /// Failure to account for a service is never read as success.
    static func resolve(requested: [String], outcome: ProxyTransactionOutcome) -> ProxyBatchResolution {
        switch outcome {
        case let .committed(services, declined):
            let committed = Set(services)
            var written: [String] = []
            var fallback: [(service: String, reason: ProxyFallbackReason)] = []
            for service in requested {
                if committed.contains(service) {
                    written.append(service)
                } else {
                    fallback.append((service, declined[service] ?? .notInCommit))
                }
            }
            return ProxyBatchResolution(written: written, fallback: fallback)

        case let .notCommitted(reason, declined),
             let .indeterminate(reason, declined):
            return ProxyBatchResolution(
                written: [],
                fallback: requested.map { ($0, declined[$0] ?? reason) }
            )
        }
    }

    /// When the fallback runs for a service whose settings already read as finished, the writes
    /// are normally skipped. After a refused apply, or a deadline that may have fallen between
    /// commit and apply, they are not: every reader here reads preferences, so a commit that was
    /// never applied is indistinguishable from a finished restore, and re-issuing the commands is
    /// what applies it.
    static func rewritesFinishedSettings(after reason: ProxyFallbackReason) -> Bool {
        reason == .applyRefused || reason == .timedOut
    }

    /// Whether a service whose live settings no longer equal `baseline` may still be written: only
    /// when the fallback follows a reason that can mean the write already landed, and the live
    /// settings are exactly what that write produces. Anything else is somebody else's change.
    static func mayWriteOver(
        live: ProxyServiceRestorationState?,
        baseline: ProxyServiceRestorationState,
        writes: [ProxyKeyWrite],
        after reason: ProxyFallbackReason
    )
        -> Bool
    {
        guard let live else {
            return false
        }
        if live == baseline {
            return true
        }
        guard rewritesFinishedSettings(after: reason) else {
            return false
        }
        return live == ProxyWritePlan.expectedState(applying: writes, to: baseline)
    }
}

// MARK: - ProxyApplyDebt

/// The durable fact that preferences were committed and the apply that makes `configd` adopt them
/// has not been confirmed.
///
/// It is a debt of the machine, not of one service: `SCPreferencesApplyChanges` applies the whole
/// stored configuration. So it lives in a record of its own rather than in a service's journal
/// entry, which is dropped the moment its settings read as restored (and they read as restored
/// the instant the commit lands). It is written before the commit and removed only after an apply
/// that returned success.
struct ProxyApplyDebt: Codable, Equatable {
    var id: String
    var services: [String]
    var ownedPort: Int?
}

// MARK: - ProxyApplyDebtState

enum ProxyApplyDebtState: Equatable {
    case none
    case owed(ProxyApplyDebt)
    /// A record exists but cannot be read. An apply is assumed owed.
    case unreadable
}

// MARK: - ProxyApplyDebtStore

protocol ProxyApplyDebtStore {
    func load() -> ProxyApplyDebtState
    func save(_ debt: ProxyApplyDebt) throws
    /// Removes the record. With an `id`, only if it still carries that id, so an orphaned job
    /// finishing late cannot erase a debt a newer transaction recorded.
    func clear(ifID id: String?) throws
}

// MARK: - ProxyApplySettlement

enum ProxyApplySettlement: Equatable {
    case nothingOwed
    case settled
    /// An apply was owed and could not be confirmed. The record is kept.
    case stillOwed
}

// MARK: - ProxyApplyDebtLedger

enum ProxyApplyDebtLedger {
    struct Recorded {
        let debt: ProxyApplyDebt
        let hadPriorDebt: Bool
    }

    /// Records the debt before the commit. Failure means no commit may follow: an apply nothing
    /// on disk remembers is the case this exists to prevent. A debt already on disk is merged, so
    /// one apply covers both.
    static func record(
        services: [String],
        ownedPort: Int?,
        in store: some ProxyApplyDebtStore
    )
        throws -> Recorded
    {
        var merged = Set(services)
        var port = ownedPort
        var hadPrior = false
        switch store.load() {
        case .none:
            break
        case let .owed(prior):
            hadPrior = true
            merged.formUnion(prior.services)
            port = port ?? prior.ownedPort
        case .unreadable:
            hadPrior = true
        }
        let debt = ProxyApplyDebt(id: UUID().uuidString, services: merged.sorted(), ownedPort: port)
        try store.save(debt)
        return Recorded(debt: debt, hadPriorDebt: hadPrior)
    }

    /// The commit never landed, so nothing is owed for it. A debt that predates it stays.
    static func discardUncommitted(_ recorded: Recorded, in store: some ProxyApplyDebtStore) {
        guard !recorded.hadPriorDebt else {
            return
        }
        try? store.clear(ifID: recorded.debt.id)
    }

    /// Called only after `SCPreferencesApplyChanges` returned success.
    static func confirmApplied(_ recorded: Recorded, in store: some ProxyApplyDebtStore) {
        try? store.clear(ifID: recorded.debt.id)
    }

    /// What recovery does when it finds the record: apply again, and forget the debt only if that
    /// apply is confirmed. A record that cannot be read is treated as owed and removed outright
    /// once the apply succeeds.
    static func settle(in store: some ProxyApplyDebtStore, apply: () -> Bool) -> ProxyApplySettlement {
        let id: String?
        switch store.load() {
        case .none:
            return .nothingOwed
        case let .owed(debt):
            id = debt.id
        case .unreadable:
            id = nil
        }
        guard apply() else {
            return .stillOwed
        }
        // A record that cannot be removed costs one more harmless apply later.
        try? store.clear(ifID: id)
        return .settled
    }
}

// MARK: - ProxyEffectiveSettings

/// A reader for what `configd` has actually adopted, as `SCDynamicStoreCopyProxies` returns it.
/// Preferences say what was committed; this says what is in force. It describes the primary
/// service, so it can only suggest that an override is still live, never prove a restore done.
enum ProxyEffectiveSettings {
    static func pointsAtLoopback(port: Int, effective: [String: Any]) -> Bool {
        func endpoint(enable: String, host: String, port key: String) -> Bool {
            (effective[enable] as? NSNumber)?.intValue == 1
                && effective[host] as? String == ProxyOverrideTransition.loopbackHost
                && (effective[key] as? NSNumber)?.intValue == port
        }
        return endpoint(
            enable: ProxySettingsKey.httpEnable,
            host: ProxySettingsKey.httpHost,
            port: ProxySettingsKey.httpPort
        )
            || endpoint(
                enable: ProxySettingsKey.httpsEnable,
                host: ProxySettingsKey.httpsHost,
                port: ProxySettingsKey.httpsPort
            )
    }
}
