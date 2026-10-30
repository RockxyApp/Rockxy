import Foundation

/// Optional local stage timings. Disabled by default; no traffic contents are recorded.
@MainActor
enum CaptureRetentionProfiler {
    enum Stage: String, Hashable {
        case observedDomains
        case assistantIndex
        case sidebarIndexes
        case filteredRows
        case errorCount
    }

    static var onMeasurement: (@MainActor (Stage, Duration) -> Void)?

    static func measure<T>(_ stage: Stage, operation: () -> T) -> T {
        guard let onMeasurement else {
            return operation()
        }
        let clock = ContinuousClock()
        let start = clock.now
        defer { onMeasurement(stage, start.duration(to: clock.now)) }
        return operation()
    }
}
