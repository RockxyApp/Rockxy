import Foundation
@testable import Rockxy
import Security
import Testing

struct KeychainSecureDataWriterTests {
    // MARK: Internal

    @Test("A failed update preserves the previous credential and does not attempt insertion", arguments: [
        errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable, errSecParam
    ])
    func updateFailure(status: OSStatus) {
        let previous = Data("previous synthetic token".utf8)
        var stored = previous
        var events: [String] = []
        let result = KeychainSecureDataWriter.save(
            Data("replacement".utf8), service: "fixture.service", account: "fixture.account",
            updateItem: { query, attributes in
                events.append("update")
                expectScopedQuery(query)
                #expect(attributes[kSecAttrAccessible as String] == nil)
                return status
            },
            addItem: { _ in
                events.append("add")
                stored = Data("incorrect replacement".utf8)
                return errSecSuccess
            }
        )
        #expect(result == status)
        #expect(events == ["update"])
        #expect(stored == previous)
    }

    @Test("An existing credential is updated in place without resetting its access policy")
    func existingCredential() {
        let replacement = Data("replacement".utf8)
        var stored = Data("previous".utf8)
        var additions = 0
        let result = KeychainSecureDataWriter.save(
            replacement, service: "fixture.service", account: "fixture.account",
            updateItem: { query, attributes in
                expectScopedQuery(query)
                #expect(attributes.count == 1)
                stored = attributes[kSecValueData as String] as? Data ?? Data()
                return errSecSuccess
            },
            addItem: { _ in additions += 1
                return errSecSuccess
            }
        )
        #expect(result == errSecSuccess)
        #expect(stored == replacement)
        #expect(additions == 0)
    }

    @Test("Only confirmed absence inserts a new credential with the existing accessibility policy")
    func missingCredential() {
        let replacement = Data("replacement".utf8)
        var events: [String] = []
        let result = KeychainSecureDataWriter.save(
            replacement, service: "fixture.service", account: "fixture.account",
            updateItem: { query, _ in
                expectScopedQuery(query)
                events.append("update")
                return errSecItemNotFound
            },
            addItem: { attributes in
                events.append("add")
                #expect(attributes[kSecAttrService as String] as? String == "fixture.service")
                #expect(attributes[kSecAttrAccount as String] as? String == "fixture.account")
                #expect(attributes[kSecValueData as String] as? Data == replacement)
                #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlocked as String)
                return errSecSuccess
            }
        )
        #expect(result == errSecSuccess)
        #expect(events == ["update", "add"])
    }

    @Test("A creation race retries the update once and propagates its actual result", arguments: [
        errSecSuccess, errSecAuthFailed
    ])
    func concurrentCreation(finalStatus: OSStatus) {
        var events: [String] = []
        var updates = 0
        let result = KeychainSecureDataWriter.save(
            Data("replacement".utf8), service: "fixture.service", account: "fixture.account",
            updateItem: { query, _ in
                expectScopedQuery(query)
                events.append("update")
                updates += 1
                return updates == 1 ? errSecItemNotFound : finalStatus
            },
            addItem: { _ in events.append("add")
                return errSecDuplicateItem
            }
        )
        #expect(result == finalStatus)
        #expect(events == ["update", "add", "update"])
    }

    @Test("A failed insertion propagates the failure without an unbounded retry", arguments: [
        errSecAuthFailed, errSecNotAvailable
    ])
    func insertionFailure(status: OSStatus) {
        var events: [String] = []
        let result = KeychainSecureDataWriter.save(
            Data("replacement".utf8), service: "fixture.service", account: "fixture.account",
            updateItem: { _, _ in events.append("update")
                return errSecItemNotFound
            },
            addItem: { _ in events.append("add")
                return status
            }
        )
        #expect(result == status)
        #expect(events == ["update", "add"])
    }

    // MARK: Private

    private func expectScopedQuery(_ query: [String: Any]) {
        #expect(query.count == 3)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "fixture.service")
        #expect(query[kSecAttrAccount as String] as? String == "fixture.account")
    }
}
