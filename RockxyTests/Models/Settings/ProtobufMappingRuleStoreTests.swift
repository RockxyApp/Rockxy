import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct ProtobufMappingRuleStoreTests {
    @Test("add, persist, reload, toggle, duplicate, and delete mapping rules")
    func mappingRuleLifecycle() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "protobuf.mapping.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProtobufMappingRuleStore(userDefaults: defaults)
        let rule = ProtobufMappingRule(
            urlPattern: "/v1/*",
            method: .post,
            messageType: "api.v1.Message",
            payloadEncoding: .singleMessage
        )

        try store.addRule(rule)

        #expect(store.rules == [rule])
        #expect(store.selectedRuleID == rule.id)

        let reloaded = ProtobufMappingRuleStore(userDefaults: defaults)
        #expect(reloaded.rules == [rule])

        reloaded.toggleRule(id: rule.id)
        #expect(reloaded.rules.first?.isEnabled == false)

        reloaded.duplicateSelectedRule()
        #expect(reloaded.rules.count == 1)

        reloaded.selectedRuleID = rule.id
        reloaded.duplicateSelectedRule()
        #expect(reloaded.rules.count == 2)
        #expect(reloaded.rules[1].id != rule.id)
        #expect(reloaded.rules[1].urlPattern == "/v1/*")
        #expect(reloaded.rules[1].messageType == "api.v1.Message")

        reloaded.removeSelectedRule()
        #expect(reloaded.rules.count == 1)
    }

    @Test("validation rejects empty rule and invalid message type")
    func validation() throws {
        #expect(throws: ProtobufMappingRuleValidationError.emptyPattern) {
            try ProtobufMappingRuleStore.validate(ProtobufMappingRule(urlPattern: "   "))
        }

        #expect(throws: ProtobufMappingRuleValidationError.invalidMessageType) {
            try ProtobufMappingRuleStore.validate(ProtobufMappingRule(
                urlPattern: "/v1/*",
                messageType: "api.Message<Bad>"
            ))
        }

        try ProtobufMappingRuleStore.validate(ProtobufMappingRule(
            urlPattern: "/v1/*",
            messageType: "api.v1.Message_Name$Nested"
        ))
    }

    @Test("schema reference distinguishes not-selected, missing, and selected")
    func schemaReferenceLabels() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "protobuf.mapping.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProtobufMappingRuleStore(userDefaults: defaults)
        let schema = ProtobufSchemaDescriptor(fileName: "service.proto", hostPattern: "*")

        #expect(store.schemaReference(for: nil, schemas: [schema]) == .notSelected)
        #expect(store.schemaReference(for: UUID(), schemas: [schema]) == .missing)
        #expect(store.schemaReference(for: schema.id, schemas: [schema]) == .selected("service.proto"))

        #expect(store.schemaLabel(for: nil, schemas: [schema]) == "Not selected")
        #expect(store.schemaLabel(for: UUID(), schemas: [schema]) == "Missing Schema")
        #expect(store.schemaLabel(for: schema.id, schemas: [schema]) == "service.proto")
    }

    @Test("editing a disabled definition preserves its saved-disabled state and identity")
    func editedFieldsPreserveDisabledStateAndIdentity() {
        let original = ProtobufMappingRule(
            isEnabled: false,
            urlPattern: "/v1/*",
            method: .get,
            messageType: "api.v1.Old"
        )

        let edited = original.withEditedFields(
            urlPattern: "/v2/*",
            method: .post,
            matchType: original.matchType,
            includeSubpaths: original.includeSubpaths,
            schemaID: nil,
            messageType: "api.v2.New",
            requestMessageType: nil,
            responseMessageType: nil,
            payloadEncoding: .singleMessage
        )

        #expect(edited.id == original.id)
        #expect(edited.isEnabled == false)
        #expect(edited.urlPattern == "/v2/*")
        #expect(edited.method == .post)
        #expect(edited.messageType == "api.v2.New")
    }

    @Test("updating a stored disabled rule keeps it disabled through persistence")
    func updateKeepsDisabledRuleDisabled() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "protobuf.mapping.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProtobufMappingRuleStore(userDefaults: defaults)
        let rule = ProtobufMappingRule(isEnabled: false, urlPattern: "/v1/*")
        try store.addRule(rule)

        let edited = rule.withEditedFields(
            urlPattern: "/v3/*",
            method: rule.method,
            matchType: rule.matchType,
            includeSubpaths: rule.includeSubpaths,
            schemaID: rule.schemaID,
            messageType: "api.v3.Message",
            requestMessageType: nil,
            responseMessageType: nil,
            payloadEncoding: rule.payloadEncoding
        )
        try store.updateRule(edited)

        #expect(store.rules.first?.isEnabled == false)
        let reloaded = ProtobufMappingRuleStore(userDefaults: defaults)
        #expect(reloaded.rules.first?.isEnabled == false)
        #expect(reloaded.rules.first?.messageType == "api.v3.Message")
    }

    @Test("detaching a schema clears references, counts them, and persists")
    func detachSchemaClearsAndPersistsReferences() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "protobuf.mapping.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let schemaID = UUID()
        let otherSchemaID = UUID()
        let store = ProtobufMappingRuleStore(userDefaults: defaults)
        try store.addRule(ProtobufMappingRule(urlPattern: "/a/*", schemaID: schemaID))
        try store.addRule(ProtobufMappingRule(urlPattern: "/b/*", schemaID: schemaID))
        try store.addRule(ProtobufMappingRule(urlPattern: "/c/*", schemaID: otherSchemaID))

        #expect(store.referenceCount(forSchema: schemaID) == 2)

        let detached = try store.detachSchema(id: schemaID)
        #expect(detached == 2)
        #expect(store.referenceCount(forSchema: schemaID) == 0)
        #expect(store.rules.filter { $0.schemaID == otherSchemaID }.count == 1)

        let reloaded = ProtobufMappingRuleStore(userDefaults: defaults)
        #expect(reloaded.referenceCount(forSchema: schemaID) == 0)
        #expect(reloaded.rules.filter { $0.schemaID == otherSchemaID }.count == 1)
    }

    @Test("updating a definition deleted elsewhere reports a conflict")
    func updateMissingRuleReportsConflict() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "protobuf.mapping.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProtobufMappingRuleStore(userDefaults: defaults)
        let missing = ProtobufMappingRule(urlPattern: "/deleted/*")

        #expect(throws: ProtobufMappingRuleStoreError.ruleNoLongerExists) {
            try store.updateRule(missing)
        }
    }

    @Test("message-type validation identifies each editor field")
    func messageTypeValidationPredicate() {
        #expect(ProtobufMappingRuleStore.isMessageTypeValid(""))
        #expect(ProtobufMappingRuleStore.isMessageTypeValid("api.v1.Message$Nested"))
        #expect(!ProtobufMappingRuleStore.isMessageTypeValid("api.Message<Bad>"))
    }
}
