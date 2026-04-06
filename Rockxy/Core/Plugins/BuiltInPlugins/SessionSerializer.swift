import Foundation
import os

// Implements session serializer behavior for the plugin and scripting subsystem.

// MARK: - SessionSerializerError

enum SessionSerializerError: LocalizedError {
    case serializationFailed(String)
    case deserializationFailed(String)
    case unsupportedFormatVersion(Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .serializationFailed(detail):
            "Session serialization failed: \(detail)"
        case let .deserializationFailed(detail):
            "Session deserialization failed: \(detail)"
        case let .unsupportedFormatVersion(version):
            "Unsupported session format version: \(version)"
        }
    }
}

// MARK: - SessionSerializer

enum SessionSerializer {
    // MARK: Internal

    static let currentFormatVersion = 1

    static func serialize(
        transactions: [HTTPTransaction],
        logEntries: [LogEntry] = [],
        metadata: SessionMetadata
    )
        throws -> Data
    {
        let codableTransactions = transactions.map { CodableTransaction(from: $0) }
        let codableLogEntries = logEntries.isEmpty ? nil : logEntries.map { CodableLogEntry(from: $0) }

        let session = CodableSession(
            metadata: metadata,
            transactions: codableTransactions,
            logEntries: codableLogEntries
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(session)
            logger.info("Serialized \(transactions.count) transactions, \(logEntries.count) log entries")
            return data
        } catch {
            throw SessionSerializerError.serializationFailed(error.localizedDescription)
        }
    }

    static func deserialize(from data: Data) throws -> CodableSession {
        let session: CodableSession
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            session = try decoder.decode(CodableSession.self, from: data)
        } catch {
            throw SessionSerializerError.deserializationFailed(error.localizedDescription)
        }

        if session.metadata.formatVersion > currentFormatVersion {
            throw SessionSerializerError.unsupportedFormatVersion(session.metadata.formatVersion)
        }

        let txCount = session.transactions.count
        let logCount = session.logEntries?.count ?? 0
        logger.info("Deserialized session: \(txCount) transactions, \(logCount) log entries")
        return session
    }

    static func makeMetadata(
        transactionCount: Int,
        captureStartDate: Date? = nil,
        captureEndDate: Date? = nil
    )
        -> SessionMetadata
    {
        SessionMetadata(
            rockxyVersion: appVersion,
            formatVersion: currentFormatVersion,
            captureStartDate: captureStartDate,
            captureEndDate: captureEndDate,
            transactionCount: transactionCount
        )
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "SessionSerializer"
    )

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
