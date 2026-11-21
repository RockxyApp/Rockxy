import Foundation
import Security

/// Replaces one credential without deleting the last persisted value before a write succeeds.
enum KeychainSecureDataWriter {
    static func save(
        _ data: Data,
        service: String,
        account: String,
        updateItem: ([String: Any], [String: Any]) -> OSStatus = {
            SecItemUpdate($0 as CFDictionary, $1 as CFDictionary)
        },
        addItem: ([String: Any]) -> OSStatus = { SecItemAdd($0 as CFDictionary, nil) }
    )
        -> OSStatus
    {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Preserve an existing item's accessibility and access control when replacing its data.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = updateItem(query, attributes)
        guard updateStatus == errSecItemNotFound else {
            return updateStatus
        }

        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = addItem(insertion)
        if addStatus == errSecDuplicateItem {
            // Another writer may create the item between the absence check and insertion.
            return updateItem(query, attributes)
        }
        return addStatus
    }
}
