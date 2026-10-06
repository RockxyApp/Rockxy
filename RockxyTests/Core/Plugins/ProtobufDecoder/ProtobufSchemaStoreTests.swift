import Foundation
@testable import Rockxy
import Testing

// MARK: - ProtobufSchemaStoreTests

@MainActor
@Suite("ProtobufSchemaStore")
struct ProtobufSchemaStoreTests {
    // MARK: Internal

    @Test("rejects schema upload under DefaultAppPolicy")
    func defaultRejectsUpload() {
        let store = makeStore(policy: DefaultAppPolicy())
        #expect(!store.canUploadSchema)
        #expect(store.schemasLimit == 0)
        #expect(throws: AppPolicyViolation.protobufSchemaUploadUnavailable) {
            try store.uploadSchema(
                data: Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8),
                fileName: "test.proto",
                hostPattern: "*.example.com"
            )
        }
    }

    @Test("persists schema descriptors when policy allows")
    func persistenceWhenAllowed() throws {
        let directory = temporaryDirectory()
        let store = makeStore(policy: ProtobufPermissivePolicy(), directory: directory)
        let descriptor = try store.uploadSchema(
            data: Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8),
            fileName: "test.proto",
            hostPattern: "*.example.com",
            defaultMessageType: "Message"
        )

        let reloaded = makeStore(policy: ProtobufPermissivePolicy(), directory: directory)
        #expect(reloaded.schemas.count == 1)
        #expect(reloaded.schemas.first?.id == descriptor.id)
        #expect(reloaded.schemas.first?.hostPattern == "*.example.com")
    }

    @Test("enforces file size and schema count")
    func limits() throws {
        let store = makeStore(policy: OneSchemaPolicy())
        let data = Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8)
        _ = try store.uploadSchema(data: data, fileName: "one.proto", hostPattern: "*.example.com")
        #expect(throws: AppPolicyViolation.protobufSchemaLimitReached(limit: 1)) {
            try store.uploadSchema(data: data, fileName: "two.proto", hostPattern: "*.example.com")
        }

        let sizeStore = makeStore(policy: ProtobufPermissivePolicy())
        #expect(throws: ProtobufSchemaStoreError.fileTooLarge) {
            try sizeStore.uploadSchema(
                data: Data(repeating: 0x00, count: ProxyLimits.maxProtobufSchemaFileSize + 1),
                fileName: "huge.proto",
                hostPattern: "*.example.com"
            )
        }
    }

    @Test("import availability distinguishes policy lock from a full list")
    func importAvailabilityStates() throws {
        let locked = makeStore(policy: DefaultAppPolicy())
        #expect(locked.importAvailability == .policyUnavailable)
        #expect(!locked.canUploadSchema)

        let oneStore = makeStore(policy: OneSchemaPolicy())
        #expect(oneStore.importAvailability == .available)
        _ = try oneStore.uploadSchema(
            data: Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8),
            fileName: "one.proto",
            hostPattern: "*.example.com"
        )
        #expect(oneStore.importAvailability == .limitReached(limit: 1))
        #expect(!oneStore.canUploadSchema)
    }

    @Test("deleting a schema removes its persisted raw data")
    func deletionRemovesPersistedData() throws {
        let directory = temporaryDirectory()
        let fileStore = ProtobufSchemaFileStore(directoryURL: directory)
        let store = ProtobufSchemaStore(policy: ProtobufPermissivePolicy(), fileStore: fileStore)
        let descriptor = try store.uploadSchema(
            data: Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8),
            fileName: "one.proto",
            hostPattern: "*.example.com"
        )

        #expect(try fileStore.loadSchemaData(descriptorID: descriptor.id) != nil)

        try store.removeSchema(id: descriptor.id)
        #expect(store.schemas.isEmpty)
        #expect(try fileStore.loadSchemaData(descriptorID: descriptor.id) == nil)

        let reloaded = ProtobufSchemaStore(policy: ProtobufPermissivePolicy(), fileStore: fileStore)
        #expect(reloaded.schemas.isEmpty)
    }

    @Test("failed descriptor save rolls back a newly imported raw file")
    func importRollbackOnDescriptorFailure() {
        let fileStore = FaultingProtobufSchemaFileStore()
        fileStore.failDescriptorSave = true
        let store = ProtobufSchemaStore(policy: ProtobufPermissivePolicy(), fileStore: fileStore)

        #expect(throws: FaultingSchemaStoreError.descriptorSaveFailed) {
            try store.uploadSchema(
                data: Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8),
                fileName: "rollback.proto",
                hostPattern: "*"
            )
        }
        #expect(store.schemas.isEmpty)
        #expect(fileStore.rawData.isEmpty)
        #expect(fileStore.descriptors.isEmpty)
    }

    @Test("failed descriptor save restores raw data during deletion")
    func deleteRollbackOnDescriptorFailure() throws {
        let fileStore = FaultingProtobufSchemaFileStore()
        let store = ProtobufSchemaStore(policy: ProtobufPermissivePolicy(), fileStore: fileStore)
        let source = Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8)
        let descriptor = try store.uploadSchema(
            data: source,
            fileName: "keep.proto",
            hostPattern: "*"
        )

        fileStore.failDescriptorSave = true
        #expect(throws: FaultingSchemaStoreError.descriptorSaveFailed) {
            try store.removeSchema(id: descriptor.id)
        }
        #expect(store.schemas == [descriptor])
        #expect(fileStore.rawData[descriptor.id] == source)
        #expect(fileStore.descriptors == [descriptor])
    }

    @Test("raw-data read failure aborts deletion before any file is removed")
    func deleteAbortsOnBackupReadFailure() throws {
        let fileStore = FaultingProtobufSchemaFileStore()
        let store = ProtobufSchemaStore(policy: ProtobufPermissivePolicy(), fileStore: fileStore)
        let descriptor = try store.uploadSchema(
            data: Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8),
            fileName: "unreadable.proto",
            hostPattern: "*"
        )

        fileStore.failRawRead = true
        #expect(throws: FaultingSchemaStoreError.rawReadFailed) {
            try store.removeSchema(id: descriptor.id)
        }
        #expect(store.schemas == [descriptor])
        #expect(fileStore.rawData[descriptor.id] != nil)
        #expect(fileStore.removeRawCallCount == 0)
    }

    @Test("corrupt descriptor metadata blocks import and is not overwritten")
    func corruptMetadataBlocksImport() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schemasURL = directory.appendingPathComponent("schemas.json")
        let corrupt = Data("{ not valid json".utf8)
        try corrupt.write(to: schemasURL)

        let store = ProtobufSchemaStore(
            policy: ProtobufPermissivePolicy(),
            fileStore: ProtobufSchemaFileStore(directoryURL: directory)
        )

        #expect(store.storageState == .unavailable)
        #expect(store.importAvailability == .storageUnavailable)
        #expect(store.schemas.isEmpty)
        #expect(throws: ProtobufSchemaStoreError.storageUnavailable) {
            try store.uploadSchema(
                data: Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8),
                fileName: "x.proto",
                hostPattern: "*.example.com"
            )
        }

        let afterAttempt = try Data(contentsOf: schemasURL)
        #expect(afterAttempt == corrupt)
    }

    @Test("storage failure takes precedence over a policy lock")
    func storageFailurePrecedesPolicyLock() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ corrupt".utf8).write(to: directory.appendingPathComponent("schemas.json"))

        let store = ProtobufSchemaStore(
            policy: DefaultAppPolicy(),
            fileStore: ProtobufSchemaFileStore(directoryURL: directory)
        )

        #expect(store.importAvailability == .storageUnavailable)
    }

    @Test("source validator enforces extension, non-empty UTF-8, and a bounded read")
    func sourceValidatorEnforcesRules() throws {
        #expect(throws: ProtobufSchemaImportError.invalidFileType) {
            _ = try ProtobufSchemaSourceValidator.loadValidatedSource(
                at: temporaryDirectory().appendingPathComponent("schema.txt"),
                fileName: "schema.txt"
            )
        }

        let emptyURL = try writeTempFile(Data(), fileName: "empty.proto")
        #expect(throws: ProtobufSchemaImportError.emptySource) {
            _ = try ProtobufSchemaSourceValidator.loadValidatedSource(at: emptyURL, fileName: "empty.proto")
        }

        let invalidURL = try writeTempFile(Data([0xFF, 0xFE, 0xFF]), fileName: "bad.proto")
        #expect(throws: ProtobufSchemaImportError.invalidEncoding) {
            _ = try ProtobufSchemaSourceValidator.loadValidatedSource(at: invalidURL, fileName: "bad.proto")
        }

        let hugeURL = try writeTempFile(
            Data(repeating: 0x41, count: ProxyLimits.maxProtobufSchemaFileSize + 1),
            fileName: "huge.proto"
        )
        #expect(throws: ProtobufSchemaImportError.fileTooLarge) {
            _ = try ProtobufSchemaSourceValidator.read(contentsOf: hugeURL)
        }

        let goodURL = try writeTempFile(Data("syntax = \"proto3\"; message Ping { int32 id = 1; }".utf8), fileName: "ok.proto")
        let data = try ProtobufSchemaSourceValidator.loadValidatedSource(at: goodURL, fileName: "ok.proto")
        #expect(!data.isEmpty)
    }

    // MARK: Private

    private func makeStore(
        policy: any AppPolicy,
        directory: URL? = nil
    )
        -> ProtobufSchemaStore
    {
        ProtobufSchemaStore(
            policy: policy,
            fileStore: ProtobufSchemaFileStore(directoryURL: directory ?? temporaryDirectory())
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Rockxy.ProtobufSchemaStoreTests.\(UUID().uuidString)", isDirectory: true)
    }

    private func writeTempFile(_ data: Data, fileName: String) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }
}

// MARK: - FaultingProtobufSchemaFileStore

private final class FaultingProtobufSchemaFileStore: ProtobufSchemaFileStoring {
    var descriptors: [ProtobufSchemaDescriptor] = []
    var rawData: [UUID: Data] = [:]
    var failDescriptorSave = false
    var failRawRead = false
    var removeRawCallCount = 0

    func loadDescriptors() throws -> [ProtobufSchemaDescriptor] {
        descriptors
    }

    func saveDescriptors(_ descriptors: [ProtobufSchemaDescriptor]) throws {
        if failDescriptorSave {
            throw FaultingSchemaStoreError.descriptorSaveFailed
        }
        self.descriptors = descriptors
    }

    func saveSchemaData(_ data: Data, descriptorID: UUID) throws {
        rawData[descriptorID] = data
    }

    func loadSchemaData(descriptorID: UUID) throws -> Data? {
        if failRawRead {
            throw FaultingSchemaStoreError.rawReadFailed
        }
        return rawData[descriptorID]
    }

    func removeSchemaData(descriptorID: UUID) throws {
        removeRawCallCount += 1
        rawData.removeValue(forKey: descriptorID)
    }
}

private enum FaultingSchemaStoreError: Error {
    case descriptorSaveFailed
    case rawReadFailed
}

// MARK: - OneSchemaPolicy

private struct OneSchemaPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
    let upstreamProxyAllowsSOCKS5 = true
    let upstreamProxyAllowsAuthentication = true
    let maxUpstreamProxyBypassEntries = 100
    let protobufDecodingAllowsSchemaUpload = true
    let maxProtobufSchemas = 1
}

// MARK: - ProtobufPermissivePolicy

private struct ProtobufPermissivePolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
    let upstreamProxyAllowsSOCKS5 = true
    let upstreamProxyAllowsAuthentication = true
    let maxUpstreamProxyBypassEntries = 100
    let protobufDecodingAllowsSchemaUpload = true
    let maxProtobufSchemas = 100
}
