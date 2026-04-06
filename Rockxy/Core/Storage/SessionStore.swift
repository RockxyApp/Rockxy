import Foundation
import os
import SQLite

/// Bodies larger than 1 MB are stored as individual files on disk rather than
/// inline in SQLite, to keep the database size manageable and avoid large BLOB I/O.
private let bodySizeThreshold = 1_048_576

// MARK: - SessionStoreError

enum SessionStoreError: Error {
    case directoryNotFound
}

// MARK: - SessionStore

/// SQLite-backed persistence layer for HTTP transactions, log entries, and WebSocket frames.
///
/// Data lives at `~/Library/Application Support/com.amunx.rockxy.community/rockxy.sqlite3`.
/// Request/response bodies exceeding 1 MB are stored as separate files under
/// `~/Library/Application Support/com.amunx.rockxy.community/bodies/` and referenced by path in the DB.
/// Log entries are foreign-keyed to transactions (SET NULL on delete) for correlation.
/// WebSocket frames cascade-delete with their parent transaction.
actor SessionStore {
    // MARK: Lifecycle

    // MARK: - Init

    init() throws {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw SessionStoreError.directoryNotFound
        }
        let rockxyDir = appSupport.appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
        try self.init(directory: rockxyDir)
    }

    init(directory: URL) throws {
        let bodiesDir = directory.appendingPathComponent("bodies", isDirectory: true)
        self.bodiesDirectory = bodiesDir

        try FileManager.default.createDirectory(at: bodiesDir, withIntermediateDirectories: true)

        let dbPath = directory.appendingPathComponent("rockxy.sqlite3").path
        self.db = try Connection(dbPath)

        try createTablesIfNeeded()
        try migrateSchemaIfNeeded()
        Self.logger.info("SessionStore initialized at \(dbPath)")
    }

    // MARK: Internal

    // MARK: - Save Transaction

    func saveTransaction(_ transaction: HTTPTransaction) throws {
        let requestHeaders = encodeHeaders(transaction.request.headers)
        let (requestBody, requestBodyPath) = processBody(transaction.request.body, existingPath: nil)

        var responseHeaders: String?
        var responseBody: Data?
        var responseBodyPath: String?

        if let response = transaction.response {
            responseHeaders = encodeHeaders(response.headers)
            let (body, path) = processBody(response.body, existingPath: nil)
            responseBody = body
            responseBodyPath = path
        }

        let insert = Self.transactions.insert(
            or: .replace,
            Self.txId <- transaction.id.uuidString,
            Self.txTimestamp <- transaction.timestamp.timeIntervalSince1970,
            Self.txMethod <- transaction.request.method,
            Self.txUrl <- transaction.request.url.absoluteString,
            Self.txHttpVersion <- transaction.request.httpVersion,
            Self.txRequestHeaders <- requestHeaders,
            Self.txRequestBody <- requestBody,
            Self.txRequestBodyPath <- requestBodyPath,
            Self.txRequestContentType <- transaction.request.contentType?.rawValue,
            Self.txStatusCode <- transaction.response?.statusCode,
            Self.txStatusMessage <- transaction.response?.statusMessage,
            Self.txResponseHeaders <- responseHeaders,
            Self.txResponseBody <- responseBody,
            Self.txResponseBodyPath <- responseBodyPath,
            Self.txResponseContentType <- transaction.response?.contentType?.rawValue,
            Self.txState <- transaction.state.rawValue,
            Self.txTimingDns <- transaction.timingInfo?.dnsLookup,
            Self.txTimingTcp <- transaction.timingInfo?.tcpConnection,
            Self.txTimingTls <- transaction.timingInfo?.tlsHandshake,
            Self.txTimingTtfb <- transaction.timingInfo?.timeToFirstByte,
            Self.txTimingTransfer <- transaction.timingInfo?.contentTransfer,
            Self.txGraphqlOpName <- transaction.graphQLInfo?.operationName,
            Self.txGraphqlOpType <- transaction.graphQLInfo?.operationType.rawValue,
            Self.txGraphqlQuery <- transaction.graphQLInfo?.query,
            Self.txIsPinned <- (transaction.isPinned ? 1 : 0),
            Self.txIsSaved <- (transaction.isSaved ? 1 : 0),
            Self.txComment <- transaction.comment,
            Self.txHighlightColor <- transaction.highlightColor?.rawValue,
            Self.txClientApp <- transaction.clientApp
        )

        try db.run(insert)

        if let wsConnection = transaction.webSocketConnection {
            try saveWebSocketFrameDatas(wsConnection.frames, transactionId: transaction.id)
        }

        Self.logger.debug("Saved transaction: \(transaction.id)")
    }

    // MARK: - Load Transactions

    func loadTransactions(limit: Int = 100, offset: Int = 0) throws -> [HTTPTransaction] {
        let query = Self.transactions
            .order(Self.txTimestamp.desc)
            .limit(limit, offset: offset)

        var results: [HTTPTransaction] = []
        for row in try db.prepare(query) {
            if let transaction = try deserializeTransaction(from: row) {
                results.append(transaction)
            }
        }
        return results
    }

    // MARK: - Load Pinned & Saved

    func loadPinnedAndSavedTransactions() throws -> [HTTPTransaction] {
        let query = Self.transactions
            .filter(Self.txIsPinned == 1 || Self.txIsSaved == 1)
            .order(Self.txTimestamp.desc)

        var results: [HTTPTransaction] = []
        for row in try db.prepare(query) {
            if let transaction = try deserializeTransaction(from: row) {
                results.append(transaction)
            }
        }
        return results
    }

    // MARK: - Save Log Entry

    func saveLogEntry(_ entry: LogEntry) throws {
        let (sourceType, sourceValue) = encodeLogSource(entry.source)
        let metadataJSON = encodeMetadata(entry.metadata)

        let insert = Self.logEntries.insert(
            or: .replace,
            Self.logId <- entry.id.uuidString,
            Self.logTimestamp <- entry.timestamp.timeIntervalSince1970,
            Self.logLevel <- logLevelToString(entry.level),
            Self.logMessage <- entry.message,
            Self.logSourceType <- sourceType,
            Self.logSourceValue <- sourceValue,
            Self.logProcessName <- entry.processName,
            Self.logSubsystem <- entry.subsystem,
            Self.logCategory <- entry.category,
            Self.logMetadata <- metadataJSON,
            Self.logCorrelatedTxId <- entry.correlatedTransactionId?.uuidString
        )

        try db.run(insert)
        Self.logger.debug("Saved log entry: \(entry.id)")
    }

    // MARK: - Load Log Entries

    func loadLogEntries(transactionId: UUID? = nil) throws -> [LogEntry] {
        var query = Self.logEntries.order(Self.logTimestamp.desc)

        if let txId = transactionId {
            query = query.filter(Self.logCorrelatedTxId == txId.uuidString)
        }

        var results: [LogEntry] = []
        for row in try db.prepare(query) {
            if let entry = deserializeLogEntry(from: row) {
                results.append(entry)
            }
        }
        return results
    }

    // MARK: - Delete Transactions

    func deleteTransactions(olderThan date: Date) throws {
        let cutoff = date.timeIntervalSince1970
        let oldTransactions = Self.transactions.filter(Self.txTimestamp < cutoff)

        let bodyPaths = try db.prepare(
            oldTransactions.select(Self.txRequestBodyPath, Self.txResponseBodyPath)
        )
        for row in bodyPaths {
            deleteBodyFile(at: row[Self.txRequestBodyPath])
            deleteBodyFile(at: row[Self.txResponseBodyPath])
        }

        try db.run(oldTransactions.delete())
        Self.logger.info("Deleted transactions older than \(date)")
    }

    func deleteTransactions(byIDs ids: Set<UUID>) throws {
        let idStrings = ids.map(\.uuidString)
        let matching = Self.transactions.filter(idStrings.contains(Self.txId))

        let bodyPaths = try db.prepare(
            matching.select(Self.txRequestBodyPath, Self.txResponseBodyPath)
        )
        for row in bodyPaths {
            deleteBodyFile(at: row[Self.txRequestBodyPath])
            deleteBodyFile(at: row[Self.txResponseBodyPath])
        }

        let deletedCount = try db.run(matching.delete())
        Self.logger.info("Deleted \(deletedCount) of \(ids.count) requested transactions by ID")
    }

    // MARK: - Transaction Count

    func transactionCount() throws -> Int {
        try db.scalar(Self.transactions.count)
    }

    // MARK: - Schema Migration

    func schemaVersion() throws -> Int32 {
        guard let version = try db.scalar("PRAGMA user_version") as? Int64 else {
            return 0
        }
        return Int32(version)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "SessionStore")

    // MARK: - Transaction Table

    private static let transactions = Table("transactions")
    private static let txId = SQLite.Expression<String>("id")
    private static let txTimestamp = SQLite.Expression<Double>("timestamp")
    private static let txMethod = SQLite.Expression<String>("method")
    private static let txUrl = SQLite.Expression<String>("url")
    private static let txHttpVersion = SQLite.Expression<String>("http_version")
    private static let txRequestHeaders = SQLite.Expression<String>("request_headers")
    private static let txRequestBody = SQLite.Expression<Data?>("request_body")
    private static let txRequestBodyPath = SQLite.Expression<String?>("request_body_path")
    private static let txRequestContentType = SQLite.Expression<String?>("request_content_type")
    private static let txStatusCode = SQLite.Expression<Int?>("status_code")
    private static let txStatusMessage = SQLite.Expression<String?>("status_message")
    private static let txResponseHeaders = SQLite.Expression<String?>("response_headers")
    private static let txResponseBody = SQLite.Expression<Data?>("response_body")
    private static let txResponseBodyPath = SQLite.Expression<String?>("response_body_path")
    private static let txResponseContentType = SQLite.Expression<String?>("response_content_type")
    private static let txState = SQLite.Expression<String>("state")
    private static let txTimingDns = SQLite.Expression<Double?>("timing_dns")
    private static let txTimingTcp = SQLite.Expression<Double?>("timing_tcp")
    private static let txTimingTls = SQLite.Expression<Double?>("timing_tls")
    private static let txTimingTtfb = SQLite.Expression<Double?>("timing_ttfb")
    private static let txTimingTransfer = SQLite.Expression<Double?>("timing_transfer")
    private static let txGraphqlOpName = SQLite.Expression<String?>("graphql_op_name")
    private static let txGraphqlOpType = SQLite.Expression<String?>("graphql_op_type")
    private static let txGraphqlQuery = SQLite.Expression<String?>("graphql_query")
    private static let txIsPinned = SQLite.Expression<Int>("is_pinned")
    private static let txIsSaved = SQLite.Expression<Int>("is_saved")
    private static let txComment = SQLite.Expression<String?>("comment")
    private static let txHighlightColor = SQLite.Expression<String?>("highlight_color")
    private static let txClientApp = SQLite.Expression<String?>("client_app")

    // MARK: - Log Entries Table

    private static let logEntries = Table("log_entries")
    private static let logId = SQLite.Expression<String>("id")
    private static let logTimestamp = SQLite.Expression<Double>("timestamp")
    private static let logLevel = SQLite.Expression<String>("level")
    private static let logMessage = SQLite.Expression<String>("message")
    private static let logSourceType = SQLite.Expression<String>("source_type")
    private static let logSourceValue = SQLite.Expression<String?>("source_value")
    private static let logProcessName = SQLite.Expression<String?>("process_name")
    private static let logSubsystem = SQLite.Expression<String?>("subsystem")
    private static let logCategory = SQLite.Expression<String?>("category")
    private static let logMetadata = SQLite.Expression<String>("metadata")
    private static let logCorrelatedTxId = SQLite.Expression<String?>("correlated_transaction_id")

    // MARK: - WebSocket Frames Table

    private static let wsFrames = Table("websocket_frames")
    private static let wsId = SQLite.Expression<String>("id")
    private static let wsTransactionId = SQLite.Expression<String>("transaction_id")
    private static let wsTimestamp = SQLite.Expression<Double>("timestamp")
    private static let wsDirection = SQLite.Expression<String>("direction")
    private static let wsOpcode = SQLite.Expression<Int>("opcode")
    private static let wsPayload = SQLite.Expression<Data>("payload")
    private static let wsIsFinal = SQLite.Expression<Int>("is_final")

    private let db: Connection

    // MARK: - Paths

    private let bodiesDirectory: URL

    // MARK: - Schema

    private func createTablesIfNeeded() throws {
        try db.run(Self.transactions.create(ifNotExists: true) { table in
            table.column(Self.txId, primaryKey: true)
            table.column(Self.txTimestamp)
            table.column(Self.txMethod)
            table.column(Self.txUrl)
            table.column(Self.txHttpVersion)
            table.column(Self.txRequestHeaders)
            table.column(Self.txRequestBody)
            table.column(Self.txRequestBodyPath)
            table.column(Self.txRequestContentType)
            table.column(Self.txStatusCode)
            table.column(Self.txStatusMessage)
            table.column(Self.txResponseHeaders)
            table.column(Self.txResponseBody)
            table.column(Self.txResponseBodyPath)
            table.column(Self.txResponseContentType)
            table.column(Self.txState)
            table.column(Self.txTimingDns)
            table.column(Self.txTimingTcp)
            table.column(Self.txTimingTls)
            table.column(Self.txTimingTtfb)
            table.column(Self.txTimingTransfer)
            table.column(Self.txGraphqlOpName)
            table.column(Self.txGraphqlOpType)
            table.column(Self.txGraphqlQuery)
        })

        try db.run(Self.logEntries.create(ifNotExists: true) { table in
            table.column(Self.logId, primaryKey: true)
            table.column(Self.logTimestamp)
            table.column(Self.logLevel)
            table.column(Self.logMessage)
            table.column(Self.logSourceType)
            table.column(Self.logSourceValue)
            table.column(Self.logProcessName)
            table.column(Self.logSubsystem)
            table.column(Self.logCategory)
            table.column(Self.logMetadata)
            table.column(Self.logCorrelatedTxId)
            table.foreignKey(
                Self.logCorrelatedTxId,
                references: Self.transactions, Self.txId,
                delete: .setNull
            )
        })

        try db.run(Self.wsFrames.create(ifNotExists: true) { table in
            table.column(Self.wsId, primaryKey: true)
            table.column(Self.wsTransactionId)
            table.column(Self.wsTimestamp)
            table.column(Self.wsDirection)
            table.column(Self.wsOpcode)
            table.column(Self.wsPayload)
            table.column(Self.wsIsFinal)
            table.foreignKey(
                Self.wsTransactionId,
                references: Self.transactions, Self.txId,
                delete: .cascade
            )
        })
    }

    private func setSchemaVersion(_ version: Int32) throws {
        try db.run("PRAGMA user_version = \(version)")
    }

    private func existingColumnNames(table: String) throws -> Set<String> {
        let allowedTables: Set = ["transactions", "log_entries", "websocket_frames"]
        guard allowedTables.contains(table) else {
            Self.logger.error("SECURITY: Unexpected table name in schema check: \(table)")
            return []
        }
        var names = Set<String>()
        let statement = try db.prepare("PRAGMA table_info(\(table))")
        for row in statement {
            if let name = row[1] as? String {
                names.insert(name)
            }
        }
        return names
    }

    private func migrateSchemaIfNeeded() throws {
        let currentVersion = try schemaVersion()

        if currentVersion == 0 {
            let columns = try existingColumnNames(table: "transactions")
            if columns.contains("is_pinned") {
                try setSchemaVersion(1)
                Self.logger.info("Schema version bootstrapped to v1 (columns already present)")
                return
            }
        }

        let migrations: [(version: Int32, statements: [String])] = [
            (1, [
                "ALTER TABLE transactions ADD COLUMN is_pinned INTEGER DEFAULT 0",
                "ALTER TABLE transactions ADD COLUMN is_saved INTEGER DEFAULT 0",
                "ALTER TABLE transactions ADD COLUMN comment TEXT",
                "ALTER TABLE transactions ADD COLUMN highlight_color TEXT",
                "ALTER TABLE transactions ADD COLUMN client_app TEXT",
            ]),
        ]

        let pending = migrations.filter { $0.version > currentVersion }
        guard !pending.isEmpty else {
            Self.logger.debug("Schema up to date (v\(currentVersion))")
            return
        }

        for migration in pending {
            for sql in migration.statements {
                try db.run(sql)
            }
            try setSchemaVersion(migration.version)
        }

        if let newVersion = pending.last?.version {
            Self.logger.info("Schema migrated from v\(currentVersion) to v\(newVersion)")
        }
    }

    // MARK: - WebSocket Frames

    private func saveWebSocketFrameDatas(_ frames: [WebSocketFrameData], transactionId: UUID) throws {
        let txIdString = transactionId.uuidString
        let deleteExisting = Self.wsFrames.filter(Self.wsTransactionId == txIdString)
        try db.run(deleteExisting.delete())

        for frame in frames {
            let insert = Self.wsFrames.insert(
                Self.wsId <- frame.id.uuidString,
                Self.wsTransactionId <- txIdString,
                Self.wsTimestamp <- frame.timestamp.timeIntervalSince1970,
                Self.wsDirection <- frame.direction.rawValue,
                Self.wsOpcode <- Int(frame.opcode.rawValue),
                Self.wsPayload <- frame.payload,
                Self.wsIsFinal <- (frame.isFinal ? 1 : 0)
            )
            try db.run(insert)
        }
    }

    private func loadWebSocketFrameDatas(transactionId: UUID) throws -> [WebSocketFrameData] {
        let query = Self.wsFrames
            .filter(Self.wsTransactionId == transactionId.uuidString)
            .order(Self.wsTimestamp.asc)

        var frames: [WebSocketFrameData] = []
        for row in try db.prepare(query) {
            guard let frameId = UUID(uuidString: row[Self.wsId]),
                  let direction = FrameDirection(rawValue: row[Self.wsDirection]),
                  let opcode = FrameOpcode(rawValue: UInt8(row[Self.wsOpcode])) else
            {
                continue
            }

            let frame = WebSocketFrameData(
                id: frameId,
                timestamp: Date(timeIntervalSince1970: row[Self.wsTimestamp]),
                direction: direction,
                opcode: opcode,
                payload: row[Self.wsPayload],
                isFinal: row[Self.wsIsFinal] != 0
            )
            frames.append(frame)
        }
        return frames
    }

    // MARK: - Body Storage

    private func processBody(_ body: Data?, existingPath: String?) -> (Data?, String?) {
        guard let body else {
            return (nil, existingPath)
        }

        if body.count > bodySizeThreshold {
            let filename = "\(UUID().uuidString).bin"
            let filePath = bodiesDirectory.appendingPathComponent(filename)
            do {
                try body.write(to: filePath)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)
                return (nil, filePath.path)
            } catch {
                Self.logger.error("Failed to write body to disk: \(error.localizedDescription)")
                return (body, nil)
            }
        }
        return (body, nil)
    }

    private func loadBody(inlineData: Data?, diskPath: String?) -> Data? {
        if let inlineData {
            return inlineData
        }
        guard let diskPath else {
            return nil
        }
        let resolvedPath = URL(fileURLWithPath: diskPath).standardizedFileURL.path
        let bodiesPath = bodiesDirectory.standardizedFileURL.path
        guard resolvedPath.hasPrefix(bodiesPath + "/") else {
            Self.logger.error("SECURITY: Path traversal blocked in body load: \(diskPath)")
            return nil
        }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: resolvedPath))
        } catch {
            Self.logger.error("Failed to read body from disk at \(diskPath): \(error.localizedDescription)")
            return nil
        }
    }

    private func deleteBodyFile(at path: String?) {
        guard let path else {
            return
        }
        let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let bodiesPath = bodiesDirectory.standardizedFileURL.path
        guard resolvedPath.hasPrefix(bodiesPath + "/") else {
            Self.logger.error("SECURITY: Path traversal blocked in body delete: \(path)")
            return
        }
        do {
            try FileManager.default.removeItem(atPath: resolvedPath)
        } catch {
            Self.logger.warning("Failed to delete body file at \(path): \(error.localizedDescription)")
        }
    }

    // MARK: - Transaction Deserialization

    private func deserializeTransaction(from row: Row) throws -> HTTPTransaction? {
        guard let id = UUID(uuidString: row[Self.txId]),
              let url = URL(string: row[Self.txUrl]),
              let state = TransactionState(rawValue: row[Self.txState]) else
        {
            Self.logger.warning("Failed to deserialize transaction row")
            return nil
        }

        let requestHeaders = decodeHeaders(row[Self.txRequestHeaders])
        let requestBody = loadBody(inlineData: row[Self.txRequestBody], diskPath: row[Self.txRequestBodyPath])
        let requestContentType = row[Self.txRequestContentType].flatMap { ContentType(rawValue: $0) }

        let request = HTTPRequestData(
            method: row[Self.txMethod],
            url: url,
            httpVersion: row[Self.txHttpVersion],
            headers: requestHeaders,
            body: requestBody,
            contentType: requestContentType
        )

        var response: HTTPResponseData?
        if let statusCode = row[Self.txStatusCode], let statusMessage = row[Self.txStatusMessage] {
            let responseHeaders = row[Self.txResponseHeaders].map { decodeHeaders($0) } ?? []
            let responseBody = loadBody(
                inlineData: row[Self.txResponseBody],
                diskPath: row[Self.txResponseBodyPath]
            )
            let responseContentType = row[Self.txResponseContentType].flatMap { ContentType(rawValue: $0) }

            response = HTTPResponseData(
                statusCode: statusCode,
                statusMessage: statusMessage,
                headers: responseHeaders,
                body: responseBody,
                contentType: responseContentType
            )
        }

        var timingInfo: TimingInfo?
        if let dns = row[Self.txTimingDns],
           let tcp = row[Self.txTimingTcp],
           let tls = row[Self.txTimingTls],
           let ttfb = row[Self.txTimingTtfb],
           let transfer = row[Self.txTimingTransfer]
        {
            timingInfo = TimingInfo(
                dnsLookup: dns,
                tcpConnection: tcp,
                tlsHandshake: tls,
                timeToFirstByte: ttfb,
                contentTransfer: transfer
            )
        }

        var graphQLInfo: GraphQLInfo?
        if let opType = row[Self.txGraphqlOpType],
           let graphQLOpType = GraphQLOperationType(rawValue: opType),
           let query = row[Self.txGraphqlQuery]
        {
            graphQLInfo = GraphQLInfo(
                operationName: row[Self.txGraphqlOpName],
                operationType: graphQLOpType,
                query: query,
                variables: nil
            )
        }

        let transaction = HTTPTransaction(
            id: id,
            timestamp: Date(timeIntervalSince1970: row[Self.txTimestamp]),
            request: request,
            state: state
        )
        transaction.response = response
        transaction.timingInfo = timingInfo
        transaction.graphQLInfo = graphQLInfo
        transaction.isPinned = row[Self.txIsPinned] != 0
        transaction.isSaved = row[Self.txIsSaved] != 0
        transaction.comment = row[Self.txComment]
        transaction.highlightColor = row[Self.txHighlightColor].flatMap { HighlightColor(rawValue: $0) }
        transaction.clientApp = row[Self.txClientApp]

        let wsFrames = try loadWebSocketFrameDatas(transactionId: id)
        if !wsFrames.isEmpty {
            transaction.webSocketConnection = WebSocketConnection(
                upgradeRequest: request,
                frames: wsFrames
            )
        }

        return transaction
    }

    // MARK: - Log Entry Deserialization

    private func deserializeLogEntry(from row: Row) -> LogEntry? {
        guard let id = UUID(uuidString: row[Self.logId]),
              let level = logLevelFromString(row[Self.logLevel]),
              let source = decodeLogSource(type: row[Self.logSourceType], value: row[Self.logSourceValue]) else
        {
            Self.logger.warning("Failed to deserialize log entry row")
            return nil
        }

        let correlatedTxId = row[Self.logCorrelatedTxId].flatMap { UUID(uuidString: $0) }
        let metadata = decodeMetadata(row[Self.logMetadata])

        return LogEntry(
            id: id,
            timestamp: Date(timeIntervalSince1970: row[Self.logTimestamp]),
            level: level,
            message: row[Self.logMessage],
            source: source,
            processName: row[Self.logProcessName],
            subsystem: row[Self.logSubsystem],
            category: row[Self.logCategory],
            metadata: metadata,
            correlatedTransactionId: correlatedTxId
        )
    }

    // MARK: - Header Encoding

    private func encodeHeaders(_ headers: [HTTPHeader]) -> String {
        let dicts = headers.map { ["name": $0.name, "value": $0.value] }
        guard let data = try? JSONSerialization.data(withJSONObject: dicts),
              let json = String(data: data, encoding: .utf8) else
        {
            return "[]"
        }
        return json
    }

    private func decodeHeaders(_ json: String) -> [HTTPHeader] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else
        {
            return []
        }
        return array.compactMap { dict in
            guard let name = dict["name"], let value = dict["value"] else {
                return nil
            }
            return HTTPHeader(name: name, value: value)
        }
    }

    // MARK: - LogSource Encoding

    private func encodeLogSource(_ source: LogSource) -> (type: String, value: String?) {
        switch source {
        case let .oslog(subsystem):
            ("oslog", subsystem)
        case let .processStdout(pid):
            ("processStdout", String(pid))
        case let .processStderr(pid):
            ("processStderr", String(pid))
        case let .custom(name):
            ("custom", name)
        }
    }

    private func decodeLogSource(type: String, value: String?) -> LogSource? {
        switch type {
        case "oslog":
            guard let subsystem = value else {
                return nil
            }
            return .oslog(subsystem: subsystem)
        case "processStdout":
            guard let value, let pid = Int32(value) else {
                return nil
            }
            return .processStdout(pid: pid)
        case "processStderr":
            guard let value, let pid = Int32(value) else {
                return nil
            }
            return .processStderr(pid: pid)
        case "custom":
            guard let name = value else {
                return nil
            }
            return .custom(name: name)
        default:
            return nil
        }
    }

    // MARK: - LogLevel Encoding

    private func logLevelToString(_ level: LogLevel) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .warning: "warning"
        case .error: "error"
        case .fault: "fault"
        }
    }

    private func logLevelFromString(_ string: String) -> LogLevel? {
        switch string {
        case "debug": .debug
        case "info": .info
        case "notice": .notice
        case "warning": .warning
        case "error": .error
        case "fault": .fault
        default: nil
        }
    }

    // MARK: - Metadata Encoding

    private func encodeMetadata(_ metadata: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: metadata),
              let json = String(data: data, encoding: .utf8) else
        {
            return "{}"
        }
        return json
    }

    private func decodeMetadata(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else
        {
            return [:]
        }
        return dict
    }
}
