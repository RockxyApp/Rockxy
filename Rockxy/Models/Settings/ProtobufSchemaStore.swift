import Foundation
import Observation
import os

// MARK: - ProtobufSchemaStore

@MainActor @Observable
final class ProtobufSchemaStore {
    // MARK: Lifecycle

    init(
        policy: any AppPolicy = DefaultAppPolicy(),
        fileStore: any ProtobufSchemaFileStoring = ProtobufSchemaFileStore()
    ) {
        self.policy = policy
        self.fileStore = fileStore
        do {
            self.schemas = try fileStore.loadDescriptors()
            self.storageState = .ready
        } catch {
            // Corrupt / unreadable descriptor metadata is recoverable: keep the list empty in
            // memory but flag storage as unavailable so we never overwrite the on-disk file.
            self.schemas = []
            self.storageState = .unavailable
            Self.logger.error("Failed to load Protobuf schema descriptors: \(error.localizedDescription)")
        }
    }

    // MARK: Internal

    enum StorageState: Equatable {
        case ready
        case unavailable
    }

    static let shared = ProtobufSchemaStore()

    private(set) var schemas: [ProtobufSchemaDescriptor]
    private(set) var storageState: StorageState

    /// Typed reason the local import path is (un)available, at model edge so views stay dumb.
    var importAvailability: ProtobufSchemaImportAvailability {
        guard storageState == .ready else {
            return .storageUnavailable
        }
        guard policy.protobufDecodingAllowsSchemaUpload else {
            return .policyUnavailable
        }
        guard schemas.count < policy.maxProtobufSchemas else {
            return .limitReached(limit: policy.maxProtobufSchemas)
        }
        return .available
    }

    var canUploadSchema: Bool {
        importAvailability.allowsImport
    }

    var schemasUsed: Int {
        schemas.count
    }

    var schemasLimit: Int {
        policy.maxProtobufSchemas
    }

    @discardableResult
    func uploadSchema(
        data: Data,
        fileName: String,
        hostPattern: String,
        urlPattern: String? = nil,
        defaultMessageType: String? = nil
    )
        throws -> ProtobufSchemaDescriptor
    {
        guard storageState == .ready else {
            throw ProtobufSchemaStoreError.storageUnavailable
        }
        guard policy.protobufDecodingAllowsSchemaUpload else {
            throw AppPolicyViolation.protobufSchemaUploadUnavailable
        }
        guard schemas.count < policy.maxProtobufSchemas else {
            throw AppPolicyViolation.protobufSchemaLimitReached(limit: policy.maxProtobufSchemas)
        }
        guard ProtobufSchemaSourceValidator.hasSupportedExtension(fileName) else {
            throw ProtobufSchemaImportError.invalidFileType
        }
        guard data.count <= ProxyLimits.maxProtobufSchemaFileSize else {
            throw ProtobufSchemaStoreError.fileTooLarge
        }
        try ProtobufSchemaSourceValidator.validate(data, fileName: fileName)
        guard HostPatternMatcher.isValid(pattern: hostPattern) else {
            throw ProtobufSchemaStoreError.invalidHostPattern(hostPattern)
        }
        let compiled = try ProtobufSchemaCompiler.compile(data, fileName: fileName)

        let descriptor = ProtobufSchemaDescriptor(
            fileName: fileName,
            parsedMessageNames: compiled.messageNames,
            hostPattern: hostPattern,
            urlPattern: urlPattern,
            defaultMessageType: defaultMessageType
        )
        var updated = schemas
        updated.append(descriptor)
        try fileStore.saveSchemaData(data, descriptorID: descriptor.id)
        do {
            try fileStore.saveDescriptors(updated)
        } catch {
            // Best-effort rollback so a failed descriptor write does not leave an orphaned blob.
            try? fileStore.removeSchemaData(descriptorID: descriptor.id)
            throw error
        }
        schemas = updated
        compiledCache[descriptor.id] = compiled
        combinedCache = nil
        Self.logger.info("Uploaded Protobuf schema descriptor")
        return descriptor
    }

    func removeSchema(id: UUID) throws {
        guard storageState == .ready else {
            throw ProtobufSchemaStoreError.storageUnavailable
        }
        var updated = schemas
        updated.removeAll { $0.id == id }
        let backup = try fileStore.loadSchemaData(descriptorID: id)
        try fileStore.removeSchemaData(descriptorID: id)
        do {
            try fileStore.saveDescriptors(updated)
        } catch {
            // Best-effort restore so a failed descriptor write does not lose the raw schema blob.
            if let backup {
                try? fileStore.saveSchemaData(backup, descriptorID: id)
            }
            throw error
        }
        schemas = updated
        compiledCache[id] = nil
        combinedCache = nil
    }

    /// Every stored schema merged, so a type defined in one import resolves from another.
    /// Files that no longer parse are skipped rather than blocking the rest.
    func combinedSchema() -> ProtobufSchema {
        if let combinedCache {
            return combinedCache
        }
        var combined = ProtobufSchema()
        for descriptor in schemas {
            if let compiled = compiledSchema(for: descriptor) {
                combined = combined.merged(with: compiled)
            }
        }
        let resolved = combined.resolvingReferences()
        combinedCache = resolved
        return resolved
    }

    /// Message types defined by one stored schema, for display.
    func messageNames(for descriptor: ProtobufSchemaDescriptor) -> [String] {
        if !descriptor.parsedMessageNames.isEmpty {
            return descriptor.parsedMessageNames
        }
        return compiledSchema(for: descriptor)?.messageNames ?? []
    }

    func reload() {
        compiledCache.removeAll()
        combinedCache = nil
        do {
            schemas = try fileStore.loadDescriptors()
            storageState = .ready
        } catch {
            schemas = []
            storageState = .unavailable
            Self.logger.error("Failed to reload Protobuf schema descriptors: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProtobufDecoder")

    private let policy: any AppPolicy
    private let fileStore: any ProtobufSchemaFileStoring
    private var compiledCache: [UUID: ProtobufSchema] = [:]
    private var combinedCache: ProtobufSchema?

    private func compiledSchema(for descriptor: ProtobufSchemaDescriptor) -> ProtobufSchema? {
        if let cached = compiledCache[descriptor.id] {
            return cached
        }
        do {
            guard let data = try fileStore.loadSchemaData(descriptorID: descriptor.id) else {
                return nil
            }
            let compiled = try ProtobufSchemaCompiler.compile(data, fileName: descriptor.fileName)
            compiledCache[descriptor.id] = compiled
            return compiled
        } catch {
            Self.logger.error("Stored Protobuf schema could not be compiled: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - ProtobufSchemaStoreError

enum ProtobufSchemaStoreError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidHostPattern(String)
    case storageUnavailable

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            String(localized: "Protobuf schema file must be 1 MB or smaller.", bundle: RockxyLocalization.bundle)
        case let .invalidHostPattern(pattern):
            String(localized: "Protobuf schema host pattern is invalid: \(pattern)", bundle: RockxyLocalization.bundle)
        case .storageUnavailable:
            String(
                localized: "The local schema storage could not be read. Retry before changing local schema files.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - ProtobufSchemaImportAvailability

/// Whether the local schema list can accept a new `.proto` import, and why not when it cannot.
///
/// The states are distinct on purpose so the UI can explain a policy lock differently from a
/// full list or unreadable on-disk metadata, instead of collapsing everything into one boolean.
enum ProtobufSchemaImportAvailability: Equatable {
    case available
    /// The current app policy does not permit local schema imports.
    case policyUnavailable
    /// The stored schema count has reached the policy limit.
    case limitReached(limit: Int)
    /// The on-disk descriptor metadata could not be read, so importing would risk overwriting it.
    case storageUnavailable

    // MARK: Internal

    var allowsImport: Bool {
        self == .available
    }
}

// MARK: - ProtobufSchemaImportError

enum ProtobufSchemaImportError: LocalizedError, Equatable {
    case invalidFileType
    case emptySource
    case invalidEncoding
    case fileTooLarge

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            String(
                localized: "Select a .proto source file or a .desc descriptor set compiled with protoc.",
                bundle: RockxyLocalization.bundle
            )
        case .emptySource:
            String(localized: "The selected .proto file is empty.", bundle: RockxyLocalization.bundle)
        case .invalidEncoding:
            String(localized: "The selected .proto file is not valid UTF-8 text.", bundle: RockxyLocalization.bundle)
        case .fileTooLarge:
            String(localized: "Protobuf schema file must be 1 MB or smaller.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ProtobufSchemaSourceValidator

/// Side-effect-free checks for local schema imports: the file type, a bounded on-disk read,
/// and non-empty bytes within the size limit (UTF-8 for `.proto` sources). Parsing happens in
/// `ProtobufSchemaCompiler` when the schema is stored.
enum ProtobufSchemaSourceValidator {
    static var maxBytes: Int {
        ProxyLimits.maxProtobufSchemaFileSize
    }

    static func hasProtoExtension(_ fileName: String) -> Bool {
        (fileName as NSString).pathExtension.lowercased() == "proto"
    }

    /// `.proto` sources or compiled descriptor sets (`.desc`, `.pb`, `.protoset`, `.binpb`).
    static func hasSupportedExtension(_ fileName: String) -> Bool {
        ProtobufSchemaCompiler.isSupported(fileName: fileName)
    }

    /// Reads at most `maxBytes + 1` bytes so an oversized file is rejected without ever growing
    /// a `Data` buffer past the limit. Throws `.fileTooLarge` when the source exceeds the cap.
    static func read(contentsOf url: URL, maxBytes: Int = maxBytes) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maxBytes {
            let remaining = maxBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }
        guard data.count <= maxBytes else {
            throw ProtobufSchemaImportError.fileTooLarge
        }
        return data
    }

    /// Validates bytes for the file's kind: descriptor sets are binary, sources must be UTF-8.
    static func validate(_ data: Data, fileName: String, maxBytes: Int = maxBytes) throws {
        if ProtobufSchemaCompiler.isDescriptorSet(fileName: fileName) {
            guard !data.isEmpty else {
                throw ProtobufSchemaImportError.emptySource
            }
            guard data.count <= maxBytes else {
                throw ProtobufSchemaImportError.fileTooLarge
            }
            return
        }
        try validate(data, maxBytes: maxBytes)
    }

    /// Validates already-loaded bytes: non-empty and decodable as UTF-8 within the size limit.
    static func validate(_ data: Data, maxBytes: Int = maxBytes) throws {
        guard !data.isEmpty else {
            throw ProtobufSchemaImportError.emptySource
        }
        guard data.count <= maxBytes else {
            throw ProtobufSchemaImportError.fileTooLarge
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw ProtobufSchemaImportError.invalidEncoding
        }
    }

    /// Convenience: validates the file name extension, performs the bounded read, and validates
    /// the bytes. Returns the validated source data ready for `ProtobufSchemaStore.uploadSchema`.
    static func loadValidatedSource(at url: URL, fileName: String, maxBytes: Int = maxBytes) throws -> Data {
        guard hasSupportedExtension(fileName) else {
            throw ProtobufSchemaImportError.invalidFileType
        }
        let data = try read(contentsOf: url, maxBytes: maxBytes)
        try validate(data, fileName: fileName, maxBytes: maxBytes)
        return data
    }
}
