import Foundation
@testable import Rockxy
import Testing

@MainActor
struct BreakpointTemplateStoreTests {
    // MARK: Internal

    @Test("Store seeds valid request and response defaults")
    func storeSeedsValidDefaults() {
        let store = makeStore()

        #expect(store.requestTemplates.count == 1)
        #expect(store.responseTemplates.count == 1)
        #expect(store.requestTemplates.first?.validation.isValid == true)
        #expect(store.responseTemplates.first?.validation.isValid == true)
        #expect(store.selectedTemplate?.kind == .request)
    }

    @Test("Add and update request template persists")
    func addAndUpdateRequestTemplatePersists() {
        let defaults = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        let template = store.addTemplate(kind: .request)

        store.updateTemplate(
            id: template.id,
            name: "Auth Request",
            rawMessage: """
            POST https://example.com/login HTTP/1.1
            Content-Type: application/json

            {"email":"a@example.com"}
            """
        )

        let fresh = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)

        #expect(fresh.requestTemplates.count == 1)
        #expect(fresh.requestTemplates.first?.name == "Auth Request")
        #expect(fresh.requestTemplates.first?.validation.isValid == true)
    }

    @Test("Delete selected template removes it from storage")
    func deleteSelectedTemplatePersists() {
        let defaults = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        let request = store.addTemplate(kind: .request)
        store.addTemplate(kind: .response)
        store.selectedKind = .request
        store.selectedTemplateID = request.id

        store.deleteSelectedTemplate()
        let fresh = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)

        #expect(fresh.requestTemplates.isEmpty)
        #expect(fresh.responseTemplates.count == 1)
    }

    @Test("Validation rejects malformed request headers")
    func validationRejectsMalformedRequestHeaders() {
        let validation = BreakpointTemplateValidator.validate(
            rawMessage: """
            GET / HTTP/1.1
            Bad Header

            """,
            kind: .request
        )

        #expect(!validation.isValid)
        #expect(validation.message.contains("colon"))
    }

    @Test("Validation rejects response without HTTP status line")
    func validationRejectsMalformedResponseLine() {
        let validation = BreakpointTemplateValidator.validate(
            rawMessage: """
            200 OK
            Content-Type: text/plain

            body
            """,
            kind: .response
        )

        #expect(!validation.isValid)
        #expect(validation.message.contains("HTTP"))
    }

    @Test("Validation rejects malformed JSON request body when content type is JSON")
    func validationRejectsMalformedJSONRequestBody() {
        let validation = BreakpointTemplateValidator.validate(
            rawMessage: """
            POST /profile HTTP/1.1
            Content-Type: application/json

            {"token":"expired" "missingComma":true}
            """,
            kind: .request
        )

        #expect(!validation.isValid)
        #expect(validation.message.contains("Invalid JSON body"))
    }

    @Test("Validation accepts malformed-looking text body when content type is not JSON")
    func validationDoesNotParseNonJSONBody() {
        let validation = BreakpointTemplateValidator.validate(
            rawMessage: """
            POST /profile HTTP/1.1
            Content-Type: text/plain

            {"token":"expired" "missingComma":true}
            """,
            kind: .request
        )

        #expect(validation.isValid)
    }

    @Test("Selected application payload applies request fields to breakpoint draft")
    func requestApplicationPayloadAppliesToDraft() throws {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        let template = store.addTemplate(kind: .request)
        store.updateTemplate(
            id: template.id,
            rawMessage: """
            PUT /v1/profile HTTP/1.1
            X-Test: yes

            updated
            """
        )

        let payload = try #require(store.selectedApplicationPayload())
        let applied = payload.applying(to: makeDraft())

        #expect(applied.phase == .request)
        #expect(applied.method == "PUT")
        #expect(applied.url == "https://example.com/v1/profile")
        #expect(applied.headers.map(\.name) == ["X-Test"])
        #expect(applied.body == "updated")
    }

    @Test("Response application payload preserves request identity and applies response fields")
    func responseApplicationPayloadAppliesToDraft() throws {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        let template = store.addTemplate(kind: .response)
        store.updateTemplate(
            id: template.id,
            rawMessage: """
            HTTP/1.1 404 Not Found
            Content-Type: text/plain

            missing
            """
        )

        let payload = try #require(store.selectedApplicationPayload())
        let applied = payload.applying(to: makeDraft())

        #expect(applied.phase == .response)
        #expect(applied.method == "GET")
        #expect(applied.url == "https://example.com/current")
        #expect(applied.statusCode == 404)
        #expect(applied.headers.first?.name == "Content-Type")
        #expect(applied.body == "missing")
    }

    @Test("Codable legacy template fills missing defaults")
    func codableLegacyTemplateDefaults() throws {
        let json = Data(#"{"kind":"response"}"#.utf8)
        let template = try JSONDecoder().decode(BreakpointTemplate.self, from: json)

        #expect(template.kind == .response)
        #expect(template.name == "Untitled Response Template")
        #expect(template.rawMessage == BreakpointTemplateKind.response.sampleMessage)
        #expect(template.updatedAt >= template.createdAt)
        #expect(template.validation.isValid)
    }

    @Test("Codable preserves an explicitly empty raw message as an editable draft")
    func codablePreservesExplicitlyEmptyRawMessage() throws {
        let json = Data(#"{"kind":"request","rawMessage":""}"#.utf8)
        let template = try JSONDecoder().decode(BreakpointTemplate.self, from: json)

        #expect(template.rawMessage.isEmpty)
        #expect(!template.validation.isValid)
        #expect(template.applicationPayload == nil)
    }

    @Test("Duplicate selected template creates persisted copy")
    func duplicateSelectedTemplatePersists() throws {
        let defaults = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        store.addTemplate(kind: .request)

        let duplicate = try #require(store.duplicateSelectedTemplate())
        let fresh = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)

        #expect(fresh.requestTemplates.count == 2)
        #expect(fresh.requestTemplates.contains { $0.id == duplicate.id })
        #expect(duplicate.name.contains("Copy of"))
    }

    @Test("Add template uses selected kind and generates unique names")
    func addTemplateUsesSelectedKindAndUniqueNames() {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        store.selectedKind = .response

        let first = store.addTemplate()
        let second = store.addTemplate()

        #expect(first.kind == .response)
        #expect(second.kind == .response)
        #expect(store.selectedTemplateID == second.id)
        #expect(store.responseTemplates.map(\.name) == [
            "Untitled Response Template",
            "Untitled Response Template 2"
        ])
    }

    @Test("Deleting selected template falls back within the same kind")
    func deleteSelectedTemplateFallsBackWithinSameKind() {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        let first = store.addTemplate(kind: .request)
        let second = store.addTemplate(kind: .request)
        store.addTemplate(kind: .response)
        store.selectedKind = .request
        store.selectedTemplateID = first.id

        store.deleteSelectedTemplate()

        #expect(store.requestTemplates.map(\.id) == [second.id])
        #expect(store.selectedKind == .request)
        #expect(store.selectedTemplateID == second.id)
    }

    @Test("Deleting last template clears selection")
    func deleteLastTemplateClearsSelection() {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        store.addTemplate(kind: .request)

        store.deleteSelectedTemplate()

        #expect(store.templates.isEmpty)
        #expect(store.selectedTemplateID == nil)
        #expect(!store.selectedValidation.isValid)
    }

    @Test("Deleted default templates are not re-seeded on reload")
    func deletedDefaultTemplatesAreNotReseededOnReload() {
        let defaults = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey)
        for template in store.templates {
            store.deleteTemplate(id: template.id)
        }

        let fresh = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey)

        #expect(fresh.templates.isEmpty)
        #expect(fresh.selectedTemplateID == nil)
    }

    @Test("Update selected sanitizes blank names and reset restores sample")
    func updateSelectedSanitizesNameAndResetRestoresSample() throws {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        let template = store.addTemplate(kind: .request)
        store.updateSelected(
            name: "   ",
            rawMessage: """
            PATCH /custom HTTP/1.1
            X-Trace: yes

            custom
            """
        )

        #expect(store.selectedTemplate?.name == "Untitled Request Template")
        #expect(store.selectedTemplate?.rawMessage.contains("PATCH /custom") == true)

        store.resetSelectedTemplate()

        let resetTemplate = try #require(store.selectedTemplate)
        #expect(resetTemplate.id == template.id)
        #expect(resetTemplate.rawMessage == BreakpointTemplateKind.request.sampleMessage)
    }

    @Test("Malformed selected template does not create application payload")
    func malformedSelectedTemplateHasNoApplicationPayload() {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        let template = store.addTemplate(kind: .response)

        store.updateTemplate(id: template.id, rawMessage: "not a response")

        #expect(!store.selectedValidation.isValid)
        #expect(store.selectedApplicationPayload() == nil)
        #expect(store.applicationPayload(for: UUID()) == nil)
    }

    @Test("Raw message helper serializes request target and rejects invalid edits")
    func rawMessageHelperSerializesAndRejectsInvalidEdits() throws {
        let draft = BreakpointRequestData(
            method: "GET",
            url: "https://example.com/v1/users?page=2",
            headers: [EditableHeader(name: "Accept", value: "application/json")],
            body: "",
            statusCode: 200,
            phase: .request
        )

        let raw = BreakpointRawMessage.rawMessage(from: draft, kind: .request)
        #expect(raw.hasPrefix("GET /v1/users?page=2 HTTP/1.1"))
        #expect(raw.contains("Accept: application/json"))

        do {
            _ = try BreakpointRawMessage.applying("GET /missing-version", kind: .request, to: draft)
            Issue.record("Expected invalid raw message to throw")
        } catch {
            #expect(String(describing: error).contains("invalid"))
        }
    }

    @Test("Selecting a template synchronizes selectedKind so addTemplate matches the visible kind")
    func selectingTemplateSynchronizesSelectedKind() {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        let request = store.addTemplate(kind: .request)
        let response = store.addTemplate(kind: .response)

        store.selectedTemplateID = request.id
        #expect(store.selectedKind == .request)

        store.selectedTemplateID = response.id
        #expect(store.selectedKind == .response)
        #expect(store.selectedTemplate?.kind == .response)

        let created = store.addTemplate()
        #expect(created.kind == .response)
    }

    @Test("reload keeps the current selection when the selected template still exists")
    func reloadKeepsSelectionWhenTemplateStillExists() {
        let store = BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey, seedDefaults: false)
        let first = store.addTemplate(kind: .request)
        store.addTemplate(kind: .request)
        store.selectedTemplateID = first.id

        store.reload()

        #expect(store.selectedTemplateID == first.id)
        #expect(store.selectedKind == .request)
    }

    @Test("reload repairs a stale selection by falling back to the first template of the selected kind")
    func reloadRepairsStaleSelectionWithinSameKind() {
        let defaults = makeDefaults()
        let writer = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        let first = writer.addTemplate(kind: .request)
        let second = writer.addTemplate(kind: .request)
        writer.addTemplate(kind: .response)

        let reader = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        reader.selectedKind = .request
        reader.selectedTemplateID = first.id

        writer.deleteTemplate(id: first.id)
        reader.reload()

        #expect(reader.selectedKind == .request)
        #expect(reader.selectedTemplateID == second.id)
    }

    @Test("reload falls back across kinds and synchronizes when the selected kind becomes empty")
    func reloadFallsBackAcrossKindWhenSelectedKindBecomesEmpty() {
        let defaults = makeDefaults()
        let writer = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        let request = writer.addTemplate(kind: .request)
        let response = writer.addTemplate(kind: .response)

        let reader = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        reader.selectedKind = .request
        reader.selectedTemplateID = request.id

        writer.deleteTemplate(id: request.id)
        reader.reload()

        #expect(reader.selectedTemplateID == response.id)
        #expect(reader.selectedKind == .response)
    }

    @Test("reload clears the selection when no templates remain")
    func reloadClearsSelectionWhenNoTemplatesRemain() {
        let defaults = makeDefaults()
        let writer = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        let request = writer.addTemplate(kind: .request)

        let reader = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        reader.selectedTemplateID = request.id

        writer.deleteTemplate(id: request.id)
        reader.reload()

        #expect(reader.templates.isEmpty)
        #expect(reader.selectedTemplateID == nil)
    }

    @Test("Invalid raw template persists as an editable draft but produces no application payload")
    func invalidRawTemplatePersistsAsDraftWithoutApplicationPayload() {
        let defaults = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        let template = store.addTemplate(kind: .response)
        store.updateTemplate(id: template.id, rawMessage: "not a response")

        #expect(store.applicationPayload(for: template.id) == nil)

        let fresh = BreakpointTemplateStore(defaults: defaults, storageKey: storageKey, seedDefaults: false)
        #expect(fresh.responseTemplates.first?.rawMessage == "not a response")
        #expect(fresh.responseTemplates.first?.validation.isValid == false)
        #expect(fresh.applicationPayload(for: template.id) == nil)
    }

    // MARK: Private

    private let storageKey = "breakpointTemplates.tests"

    private func makeStore() -> BreakpointTemplateStore {
        BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "com.amunx.rockxy.tests.breakpointTemplates.")
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated Breakpoint template test defaults.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeDraft() -> BreakpointRequestData {
        BreakpointRequestData(
            method: "GET",
            url: "https://example.com/current",
            headers: [EditableHeader(name: "Accept", value: "application/json")],
            body: "",
            statusCode: 200,
            phase: .request
        )
    }
}
