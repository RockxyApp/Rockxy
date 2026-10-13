import Foundation
import Observation

// MARK: - BabylonRuntimeValidationError

/// Reasons a decoded runtime package is rejected before retention. Thrown from
/// the receiver's existing runtime path so an invalid package fails the frame
/// exactly like any other malformed payload — without weakening authentication
/// or protocol guards.
enum BabylonRuntimeValidationError: LocalizedError {
    case invalidPackageIdentifier
    case invalidRuntimeIdentifier
    case nonFiniteTiming

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidPackageIdentifier: "The Babylon runtime package identifier is invalid."
        case .invalidRuntimeIdentifier: "A Babylon runtime correlation identifier is invalid."
        case .nonFiniteTiming: "The Babylon runtime timing values are not finite."
        }
    }
}

// MARK: - BabylonRuntimeTruncatedField

enum BabylonRuntimeTruncatedField: Hashable, Sendable {
    case name
    case error
    case metadata

    // MARK: Internal

    var title: String {
        switch self {
        case .name: String(localized: "Name", bundle: RockxyLocalization.bundle)
        case .error: String(localized: "Error", bundle: RockxyLocalization.bundle)
        case .metadata: String(localized: "Metadata", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - BabylonRuntimeEvent

/// A retained, bounded projection of one decoded runtime package.
///
/// Identity is composite — authenticated source client + transport session +
/// runtime package ID — so identical package IDs delivered by different clients
/// or sessions stay independently selectable, while an exact composite duplicate
/// can be ignored. The producer's own package ID is preserved separately.
struct BabylonRuntimeEvent: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    init(
        validating package: BabylonRuntimePackageDTO,
        source: BabylonCaptureIdentity,
        receivedAt: Date = Date()
    )
        throws
    {
        let packageID = package.id
        guard Self.isValidIdentifier(packageID) else {
            throw BabylonRuntimeValidationError.invalidPackageIdentifier
        }
        guard Self.isValidIdentifier(package.sessionID),
              Self.isValidOptionalIdentifier(package.traceID),
              Self.isValidOptionalIdentifier(package.stepID),
              Self.isValidOptionalIdentifier(package.parentStepID),
              Self.hasRequiredCorrelationIdentifiers(package) else
        {
            throw BabylonRuntimeValidationError.invalidRuntimeIdentifier
        }
        guard package.createdAt.isFinite,
              Self.isFiniteOrNil(package.startedAt),
              Self.isFiniteOrNil(package.endedAt),
              Self.isFiniteOrNil(package.duration),
              package.duration.map({ $0 >= 0 }) ?? true,
              Self.isChronologicallyValid(startedAt: package.startedAt, endedAt: package.endedAt) else
        {
            throw BabylonRuntimeValidationError.nonFiniteTiming
        }

        let boundedName = Self.boundedUTF8(package.name, maximumByteCount: Self.maximumNameByteCount)
        let boundedError = package.error.map {
            Self.boundedUTF8($0.message, maximumByteCount: Self.maximumErrorByteCount)
        }
        let boundedMetadata = Self.boundedMetadata(package.metadata)
        self.packageID = packageID
        id = Identity(
            clientID: source.clientID,
            transportSessionID: source.sessionID,
            packageID: packageID
        )
        kind = package.kind
        sessionID = package.sessionID
        traceID = package.traceID
        stepID = package.stepID
        parentStepID = package.parentStepID
        name = boundedName.value
        createdAt = Date(timeIntervalSince1970: package.createdAt)
        startedAt = package.startedAt.map(Date.init(timeIntervalSince1970:))
        endedAt = package.endedAt.map(Date.init(timeIntervalSince1970:))
        duration = package.duration
        self.receivedAt = receivedAt
        metadata = boundedMetadata.values
        errorMessage = boundedError?.value
        var truncatedFields = Set<BabylonRuntimeTruncatedField>()
        if boundedName.wasTruncated {
            truncatedFields.insert(.name)
        }
        if boundedError?.wasTruncated == true {
            truncatedFields.insert(.error)
        }
        if boundedMetadata.wasTruncated {
            truncatedFields.insert(.metadata)
        }
        self.truncatedFields = truncatedFields
        self.source = source
        byteCount = Self.retainedByteCount(
            packageID: packageID,
            name: name,
            sessionID: sessionID,
            traceID: traceID,
            stepID: stepID,
            parentStepID: parentStepID,
            errorMessage: errorMessage,
            metadata: metadata,
            source: source
        )
    }

    // MARK: Internal

    struct Identity: Hashable, Sendable {
        let clientID: String
        let transportSessionID: String
        let packageID: String
    }

    static let maximumIdentifierByteCount = 256
    static let maximumNameByteCount = 512
    static let maximumErrorByteCount = 4_096
    static let maximumMetadataPairs = 64
    static let maximumMetadataKeyByteCount = 128
    static let maximumMetadataValueByteCount = 4_096

    /// Composite identity used for `Identifiable`, selection, and deduplication.
    let id: Identity
    /// The producer's own package identifier, preserved unmodified.
    let packageID: String
    let kind: BabylonRuntimePackageDTO.Kind
    let sessionID: String
    let traceID: String?
    let stepID: String?
    let parentStepID: String?
    let name: String
    let createdAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let duration: TimeInterval?
    /// Local arrival time. This is the ordering clock used by the newest-first table.
    let receivedAt: Date
    let metadata: [String: String]
    let errorMessage: String?
    /// Fields shortened by display-safe in-memory limits.
    let truncatedFields: Set<BabylonRuntimeTruncatedField>
    let source: BabylonCaptureIdentity
    /// Approximate retained payload size in bytes, used for byte-bounded retention.
    let byteCount: Int

    var isContentTruncated: Bool {
        !truncatedFields.isEmpty
    }

    // MARK: Private

    private static func isFiniteOrNil(_ value: TimeInterval?) -> Bool {
        guard let value else {
            return true
        }
        return value.isFinite
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= maximumIdentifierByteCount
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func isValidOptionalIdentifier(_ value: String?) -> Bool {
        value.map(isValidIdentifier) ?? true
    }

    private static func isChronologicallyValid(startedAt: TimeInterval?, endedAt: TimeInterval?) -> Bool {
        guard let startedAt, let endedAt else {
            return true
        }
        return endedAt >= startedAt
    }

    private static func hasRequiredCorrelationIdentifiers(_ package: BabylonRuntimePackageDTO) -> Bool {
        switch package.kind {
        case .traceStarted,
             .traceFinished:
            package.traceID != nil
        case .stepStarted,
             .stepFinished:
            package.traceID != nil && package.stepID != nil
        case .sessionStarted,
             .sessionFinished,
             .mark,
             .event,
             .error:
            true
        }
    }

    private static func boundedUTF8(_ value: String, maximumByteCount: Int) -> (value: String, wasTruncated: Bool) {
        guard value.utf8.count > maximumByteCount else {
            return (value, false)
        }
        var result = String.UnicodeScalarView()
        var retainedByteCount = 0
        for scalar in value.unicodeScalars {
            let scalarByteCount = scalar.utf8.count
            guard retainedByteCount + scalarByteCount <= maximumByteCount else {
                break
            }
            result.append(scalar)
            retainedByteCount += scalarByteCount
        }
        return (String(result), true)
    }

    private static func boundedMetadata(
        _ metadata: [String: String]
    )
        -> (values: [String: String], wasTruncated: Bool)
    {
        // Deterministic key ordering makes the retained subset stable and testable
        // when a producer sends more than the retained-pair budget.
        let retainedPairs = metadata.sorted { $0.key < $1.key }.prefix(maximumMetadataPairs)
        var result: [String: String] = [:]
        var wasTruncated = metadata.count > maximumMetadataPairs
        for pair in retainedPairs {
            let key = boundedUTF8(pair.key, maximumByteCount: maximumMetadataKeyByteCount)
            let value = boundedUTF8(pair.value, maximumByteCount: maximumMetadataValueByteCount)
            wasTruncated = wasTruncated || key.wasTruncated || value.wasTruncated
            if result[key.value] == nil {
                result[key.value] = value.value
            }
        }
        return (result, wasTruncated)
    }

    private static func retainedByteCount(
        packageID: String,
        name: String,
        sessionID: String,
        traceID: String?,
        stepID: String?,
        parentStepID: String?,
        errorMessage: String?,
        metadata: [String: String],
        source: BabylonCaptureIdentity
    )
        -> Int
    {
        var total = packageID.utf8.count + name.utf8.count + sessionID.utf8.count
        total += traceID?.utf8.count ?? 0
        total += stepID?.utf8.count ?? 0
        total += parentStepID?.utf8.count ?? 0
        total += errorMessage?.utf8.count ?? 0
        for (key, value) in metadata {
            total += key.utf8.count + value.utf8.count
        }
        total += source.clientID.utf8.count + source.sessionID.utf8.count
            + source.projectName.utf8.count + source.bundleIdentifier.utf8.count
            + source.deviceName.utf8.count + source.deviceModel.utf8.count
        return total
    }
}

// MARK: - BabylonRuntimeOutcome

/// Presentation-only classification of an event's result. Derived purely from
/// the retained event — it never claims hierarchical completeness or that a
/// started step actually finished.
enum BabylonRuntimeOutcome: Equatable, Sendable {
    case finished
    case failed
    case started
    case informational

    // MARK: Internal

    var title: String {
        switch self {
        case .finished: String(localized: "Finished", bundle: RockxyLocalization.bundle)
        case .failed: String(localized: "Error", bundle: RockxyLocalization.bundle)
        case .started: String(localized: "Started", bundle: RockxyLocalization.bundle)
        case .informational: String(localized: "Info", bundle: RockxyLocalization.bundle)
        }
    }
}

extension BabylonRuntimeEvent {
    var outcome: BabylonRuntimeOutcome {
        if errorMessage != nil || kind == .error {
            return .failed
        }
        switch kind {
        case .sessionFinished,
             .traceFinished,
             .stepFinished:
            return .finished
        case .sessionStarted,
             .traceStarted,
             .stepStarted:
            return .started
        case .mark,
             .event:
            return .informational
        case .error:
            return .failed
        }
    }

    /// Lower-cased haystack for Cmd-F across names, source, IDs, errors, and metadata.
    var searchableText: String {
        var parts = [name, source.displayName, source.clientID, packageID, sessionID]
        if let traceID {
            parts.append(traceID)
        }
        if let stepID {
            parts.append(stepID)
        }
        if let parentStepID {
            parts.append(parentStepID)
        }
        if let errorMessage {
            parts.append(errorMessage)
        }
        for (key, value) in metadata {
            parts.append(key)
            parts.append(value)
        }
        return parts.joined(separator: "\u{1F}").lowercased()
    }

    var sortedMetadata: [(key: String, value: String)] {
        metadata.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

// MARK: - BabylonRuntimePackageDTO.Kind + presentation

extension BabylonRuntimePackageDTO.Kind {
    /// Fixed presentation order for the exact-kind filter.
    static var displayOrder: [BabylonRuntimePackageDTO.Kind] {
        [
            .sessionStarted,
            .sessionFinished,
            .traceStarted,
            .traceFinished,
            .stepStarted,
            .stepFinished,
            .mark,
            .event,
            .error,
        ]
    }

    var displayTitle: String {
        switch self {
        case .sessionStarted: String(localized: "Session Started", bundle: RockxyLocalization.bundle)
        case .sessionFinished: String(localized: "Session Finished", bundle: RockxyLocalization.bundle)
        case .traceStarted: String(localized: "Trace Started", bundle: RockxyLocalization.bundle)
        case .traceFinished: String(localized: "Trace Finished", bundle: RockxyLocalization.bundle)
        case .stepStarted: String(localized: "Step Started", bundle: RockxyLocalization.bundle)
        case .stepFinished: String(localized: "Step Finished", bundle: RockxyLocalization.bundle)
        case .mark: String(localized: "Mark", bundle: RockxyLocalization.bundle)
        case .event: String(localized: "Event", bundle: RockxyLocalization.bundle)
        case .error: String(localized: "Error", bundle: RockxyLocalization.bundle)
        }
    }

    var symbolName: String {
        switch self {
        case .sessionStarted,
             .sessionFinished: "play.rectangle"
        case .traceStarted,
             .traceFinished: "point.3.connected.trianglepath.dotted"
        case .stepStarted,
             .stepFinished: "arrow.turn.down.right"
        case .mark: "flag"
        case .event: "dot.radiowaves.left.and.right"
        case .error: "exclamationmark.triangle"
        }
    }
}

// MARK: - BabylonRuntimeEventFilter

/// Pure, testable projection combining an exact-kind filter, a source filter,
/// and free-text search. Order of the input is preserved so newest-first
/// presentation survives filtering.
struct BabylonRuntimeEventFilter: Equatable {
    // MARK: Lifecycle

    init(
        kind: BabylonRuntimePackageDTO.Kind? = nil,
        sourceClientID: String? = nil,
        traceID: String? = nil,
        searchText: String = ""
    ) {
        self.kind = kind
        self.sourceClientID = sourceClientID
        self.traceID = traceID
        self.searchText = searchText
    }

    // MARK: Internal

    var kind: BabylonRuntimePackageDTO.Kind?
    var sourceClientID: String?
    /// Limits the list to one trace, matched exactly.
    var traceID: String?
    var searchText = ""

    var isActive: Bool {
        kind != nil || sourceClientID != nil || traceID != nil || !trimmedSearch.isEmpty
    }

    func apply(to events: [BabylonRuntimeEvent]) -> [BabylonRuntimeEvent] {
        events.filter(matches)
    }

    func matches(_ event: BabylonRuntimeEvent) -> Bool {
        if let kind, event.kind != kind {
            return false
        }
        if let sourceClientID, event.source.clientID != sourceClientID {
            return false
        }
        if let traceID, event.traceID != traceID {
            return false
        }
        let needle = trimmedSearch.lowercased()
        guard !needle.isEmpty else {
            return true
        }
        return event.searchableText.contains(needle)
    }

    // MARK: Private

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - BabylonRuntimeIntakeBuffer

/// Serial-queue-owned accumulator that turns a stream of runtime events into
/// bounded FIFO batches. Extracted so the receiver never spawns one unstructured
/// MainActor task per event, and so its batching/discard semantics are testable
/// without opening the live network listener.
struct BabylonRuntimeIntakeBuffer {
    // MARK: Lifecycle

    init(batchSize: Int = 128) {
        self.batchSize = max(1, batchSize)
    }

    // MARK: Internal

    let batchSize: Int

    private(set) var pending: [BabylonRuntimeEvent] = []

    var hasPending: Bool {
        !pending.isEmpty
    }

    var isReadyForImmediateFlush: Bool {
        pending.count >= batchSize
    }

    mutating func enqueue(_ event: BabylonRuntimeEvent) {
        pending.append(event)
    }

    /// Returns the pending events in FIFO order and empties the buffer.
    mutating func drain() -> [BabylonRuntimeEvent] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending
    }

    /// Drop every accumulated-but-unflushed event. Used by the clear barrier so
    /// events accepted before a clear never reappear after it.
    mutating func discardPending() {
        pending.removeAll(keepingCapacity: false)
    }
}

// MARK: - BabylonRuntimePublicationGate

/// Thread-safe generation gate for runtime batches already submitted to MainActor.
/// Advancing it at Clear or Stop invalidates older submissions before they mutate
/// the store, while new batches use the new generation.
final class BabylonRuntimePublicationGate: @unchecked Sendable {
    // MARK: Internal

    func snapshot() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    @discardableResult
    func advance() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    func isCurrent(_ snapshot: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == snapshot
    }

    // MARK: Private

    private let lock = NSLock()
    private var generation: UInt64 = 0
}

// MARK: - BabylonRuntimeEventStore

/// Global, in-memory, `@MainActor`-observable retention store for runtime events.
///
/// Bounded by both event count and approximate retained bytes, deduplicated by
/// composite identity, and evicted from the front in a single array shift rather
/// than one `removeFirst()` per event. Retention evictions are tracked truthfully
/// and reset by `clear()`.
@MainActor @Observable
final class BabylonRuntimeEventStore {
    // MARK: Lifecycle

    init(
        maximumEventCount: Int = 5_000,
        maximumRetainedByteCount: Int = 32 * 1_024 * 1_024
    ) {
        self.maximumEventCount = max(1, maximumEventCount)
        self.maximumRetainedByteCount = max(1, maximumRetainedByteCount)
        maximumSeenIDCount = maximumEventCount > Int.max / 2
            ? Int.max
            : max(2, maximumEventCount * 2)
    }

    // MARK: Internal

    static let shared = BabylonRuntimeEventStore()

    /// Retained events in arrival (oldest-first) order. Presentation reverses this.
    private(set) var events: [BabylonRuntimeEvent] = []
    private(set) var retainedByteCount = 0
    private(set) var evictedEventCount = 0

    func append(_ event: BabylonRuntimeEvent) {
        appendBatch([event])
    }

    /// Append a FIFO batch, ignoring recently seen composite duplicates and
    /// enforcing the count/byte bounds once at the end.
    func appendBatch(_ incoming: [BabylonRuntimeEvent]) {
        guard !incoming.isEmpty else {
            return
        }
        var accepted: [BabylonRuntimeEvent] = []
        accepted.reserveCapacity(incoming.count)
        for event in incoming {
            guard recentlySeenIDs.insert(event.id).inserted else {
                continue
            }
            recentlySeenIDOrder.append(event.id)
            accepted.append(event)
            retainedByteCount += event.byteCount
        }
        guard !accepted.isEmpty else {
            return
        }
        trimRecentlySeenIDs()
        events.append(contentsOf: accepted)
        enforceBounds()
    }

    func clear() {
        events.removeAll()
        recentlySeenIDs.removeAll()
        recentlySeenIDOrder.removeAll()
        retainedByteCount = 0
        evictedEventCount = 0
    }

    // MARK: Private

    private let maximumEventCount: Int
    private let maximumRetainedByteCount: Int
    private let maximumSeenIDCount: Int
    private var recentlySeenIDs: Set<BabylonRuntimeEvent.ID> = []
    private var recentlySeenIDOrder: [BabylonRuntimeEvent.ID] = []

    private func trimRecentlySeenIDs() {
        let excess = recentlySeenIDOrder.count - maximumSeenIDCount
        guard excess > 0 else {
            return
        }
        for id in recentlySeenIDOrder.prefix(excess) {
            recentlySeenIDs.remove(id)
        }
        recentlySeenIDOrder.removeFirst(excess)
    }

    private func enforceBounds() {
        var dropCount = 0
        var reclaimedBytes = 0
        while dropCount < events.count {
            let remaining = events.count - dropCount
            let overCount = remaining > maximumEventCount
            let overBytes = retainedByteCount - reclaimedBytes > maximumRetainedByteCount
            guard overCount || overBytes else {
                break
            }
            let victim = events[dropCount]
            reclaimedBytes += victim.byteCount
            dropCount += 1
        }
        guard dropCount > 0 else {
            return
        }
        events.removeFirst(dropCount)
        retainedByteCount -= reclaimedBytes
        evictedEventCount += dropCount
    }
}
