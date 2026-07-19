import Foundation

// MARK: - AssistantCredentialStorage

protocol AssistantCredentialStorage: Sendable {
    func save(_ credential: String, providerID: UUID) throws
    func load(providerID: UUID) throws -> String?
    func delete(providerID: UUID) throws
}

// MARK: - KeychainAssistantCredentialStorage

struct KeychainAssistantCredentialStorage: AssistantCredentialStorage {
    // MARK: Internal

    func save(_ credential: String, providerID: UUID) throws {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete(providerID: providerID)
            return
        }
        try KeychainHelper.saveSecureData(
            Data(trimmed.utf8),
            service: Self.service,
            account: providerID.uuidString
        )
    }

    func load(providerID: UUID) throws -> String? {
        guard let data = try KeychainHelper.loadSecureData(
            service: Self.service,
            account: providerID.uuidString
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(providerID: UUID) throws {
        try KeychainHelper.deleteSecureData(
            service: Self.service,
            account: providerID.uuidString
        )
    }

    // MARK: Private

    private static let service = "\(RockxyIdentity.current.defaultsPrefix).debug-assistant"
}
