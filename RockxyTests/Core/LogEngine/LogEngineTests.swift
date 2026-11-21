import Foundation
@testable import Rockxy
import Testing

// Tests for the log engine: `LogCorrelator` (timestamp-based log-to-transaction matching
// within a 1-second window) and `LogFilterEngine` (level filtering, keyword search).

// MARK: - LogEngineTests

struct LogEngineTests {
    // MARK: - LogCorrelator Tests

    @Test("LogCorrelator correlates log entry with closest transaction within 1s window")
    func correlateWithinWindow() {
        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        let request = TestFixtures.makeRequest()
        let transaction = HTTPTransaction(
            timestamp: baseDate.addingTimeInterval(0.3), request: request
        )

        let logEntry = LogEntry(
            id: UUID(),
            timestamp: baseDate,
            level: .info,
            message: "Test log",
            source: .oslog(subsystem: "com.test"),
            processName: nil,
            subsystem: nil,
            category: nil,
            metadata: [:]
        )

        let result = LogCorrelator.correlate(
            logEntry: logEntry, with: [transaction]
        )

        #expect(result == transaction.id)
    }

    @Test("LogCorrelator returns nil when no transaction within time window")
    func correlateOutsideWindow() {
        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        let request = TestFixtures.makeRequest()
        let transaction = HTTPTransaction(
            timestamp: baseDate.addingTimeInterval(5.0), request: request
        )

        let logEntry = LogEntry(
            id: UUID(),
            timestamp: baseDate,
            level: .info,
            message: "Test log",
            source: .oslog(subsystem: "com.test"),
            processName: nil,
            subsystem: nil,
            category: nil,
            metadata: [:]
        )

        let result = LogCorrelator.correlate(
            logEntry: logEntry, with: [transaction]
        )

        #expect(result == nil)
    }

    @Test("LogCorrelator picks closest transaction when multiple are in window")
    func correlatePicksClosest() {
        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        let request1 = TestFixtures.makeRequest(url: "https://api.example.com/far")
        let farTransaction = HTTPTransaction(
            timestamp: baseDate.addingTimeInterval(0.8), request: request1
        )
        let request2 = TestFixtures.makeRequest(url: "https://api.example.com/close")
        let closeTransaction = HTTPTransaction(
            timestamp: baseDate.addingTimeInterval(0.1), request: request2
        )

        let logEntry = LogEntry(
            id: UUID(),
            timestamp: baseDate,
            level: .info,
            message: "Test log",
            source: .oslog(subsystem: "com.test"),
            processName: nil,
            subsystem: nil,
            category: nil,
            metadata: [:]
        )

        let result = LogCorrelator.correlate(
            logEntry: logEntry, with: [farTransaction, closeTransaction]
        )

        #expect(result == closeTransaction.id)
    }

    @Test("Correlation preserves first ties, exclusive boundaries, and out-of-order timestamps")
    func correlationEdgeCases() {
        let time = Date(timeIntervalSince1970: 1_000_000)
        func row(_ offset: TimeInterval) -> HTTPTransaction {
            HTTPTransaction(timestamp: time.addingTimeInterval(offset), request: TestFixtures.makeRequest())
        }
        let entry = LogEntry(
            id: UUID(), timestamp: time, level: .info, message: "Synthetic log",
            source: .custom(name: "fixture"), processName: nil, subsystem: nil, category: nil, metadata: [:]
        )
        let first = row(0.25)
        let equalDistance = row(-0.25)
        let exact = row(0)
        #expect(LogCorrelator.correlate(logEntry: entry, with: [first, equalDistance]) == first.id)
        #expect(LogCorrelator.correlate(logEntry: entry, with: [row(10), first, exact, row(-20)]) == exact.id)
        #expect(LogCorrelator.correlate(logEntry: entry, with: [row(1), row(-1)]) == nil)
        #expect(LogCorrelator.correlate(logEntry: entry, with: [exact], timeWindow: 0) == nil)
        #expect(LogCorrelator.correlate(logEntry: entry, with: [exact], timeWindow: .nan) == nil)
    }

    // MARK: - LogFilterEngine Tests

    @Test("LogFilterEngine filters by single level")
    func filterBySingleLevel() {
        let entries = [
            TestFixtures.makeLogEntry(level: .info, message: "Info message"),
            TestFixtures.makeLogEntry(level: .error, message: "Error message"),
            TestFixtures.makeLogEntry(level: .debug, message: "Debug message")
        ]

        let result = LogFilterEngine.filter(
            entries: entries, levels: [.error], keyword: nil, source: nil
        )

        #expect(result.count == 1)
        #expect(result[0].level == .error)
    }

    @Test("LogFilterEngine filters by multiple levels")
    func filterByMultipleLevels() {
        let entries = [
            TestFixtures.makeLogEntry(level: .info, message: "Info"),
            TestFixtures.makeLogEntry(level: .error, message: "Error"),
            TestFixtures.makeLogEntry(level: .warning, message: "Warning"),
            TestFixtures.makeLogEntry(level: .debug, message: "Debug")
        ]

        let result = LogFilterEngine.filter(
            entries: entries,
            levels: [.error, .warning],
            keyword: nil,
            source: nil
        )

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.level == .error || $0.level == .warning })
    }

    @Test("LogFilterEngine filters by keyword case-insensitively")
    func filterByKeyword() {
        let entries = [
            TestFixtures.makeLogEntry(level: .info, message: "Connection established"),
            TestFixtures.makeLogEntry(level: .error, message: "CONNECTION refused"),
            TestFixtures.makeLogEntry(level: .info, message: "Data received")
        ]

        let result = LogFilterEngine.filter(
            entries: entries, levels: [], keyword: "connection", source: nil
        )

        #expect(result.count == 2)
    }

    @Test("LogFilterEngine with empty levels returns all entries")
    func filterEmptyLevelsReturnsAll() {
        let entries = [
            TestFixtures.makeLogEntry(level: .info, message: "One"),
            TestFixtures.makeLogEntry(level: .error, message: "Two"),
            TestFixtures.makeLogEntry(level: .debug, message: "Three")
        ]

        let result = LogFilterEngine.filter(
            entries: entries, levels: [], keyword: nil, source: nil
        )

        #expect(result.count == 3)
    }

    @Test("LogFilterEngine returns empty when no matches")
    func filterNoMatches() {
        let entries = [
            TestFixtures.makeLogEntry(level: .info, message: "Normal log"),
            TestFixtures.makeLogEntry(level: .debug, message: "Debug log")
        ]

        let result = LogFilterEngine.filter(
            entries: entries,
            levels: [.info],
            keyword: "nonexistent",
            source: nil
        )

        #expect(result.isEmpty)
    }
}
