import Foundation
import Observation

// MARK: - BabylonRuntimeEvent

struct BabylonRuntimeEvent: Identifiable {
    // MARK: Lifecycle

    init(package: BabylonRuntimePackageDTO, source: BabylonCaptureIdentity) {
        id = package.id
        kind = package.kind
        sessionID = package.sessionID
        traceID = package.traceID
        stepID = package.stepID
        parentStepID = package.parentStepID
        name = String(package.name.prefix(512))
        createdAt = Date(timeIntervalSince1970: package.createdAt)
        startedAt = package.startedAt.map(Date.init(timeIntervalSince1970:))
        endedAt = package.endedAt.map(Date.init(timeIntervalSince1970:))
        duration = package.duration
        metadata = Dictionary(
            package.metadata.prefix(100).map {
                (String($0.key.prefix(256)), String($0.value.prefix(4_096)))
            },
            uniquingKeysWith: { first, _ in first }
        )
        errorMessage = package.error.map { String($0.message.prefix(4_096)) }
        self.source = source
    }

    // MARK: Internal

    let id: String
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
    let metadata: [String: String]
    let errorMessage: String?
    let source: BabylonCaptureIdentity
}

// MARK: - BabylonRuntimeEventStore

@MainActor @Observable
final class BabylonRuntimeEventStore {
    // MARK: Internal

    static let shared = BabylonRuntimeEventStore()

    private(set) var events: [BabylonRuntimeEvent] = []

    func append(_ event: BabylonRuntimeEvent) {
        while events.count >= maximumEventCount {
            events.removeFirst()
        }
        events.append(event)
    }

    func clear() {
        events.removeAll()
    }

    // MARK: Private

    private let maximumEventCount = 10_000
}
