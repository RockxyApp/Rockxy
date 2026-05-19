import Foundation
@testable import Rockxy
import Testing

@MainActor
struct BreakpointTemplateStoreTests {
    // MARK: Internal

    @Test("Store seeds valid request and response defaults")
    func storeSeedsValidDefaults() throws {
        let store = makeStore()

        #expect(store.requestTemplates.count == 1)
        #expect(store.responseTemplates.count == 1)
        #expect(store.requestTemplates.first?.validation.isValid == true)
        #expect(store.responseTemplates.first?.validation.isValid == true)
        #expect(store.selectedTemplate?.kind == .request)
    }

    @Test("Add and update request template persists")
    func addAndUpdateRequestTemplatePersists() throws {
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
        #expect(applied.url == "/v1/profile")
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
        let json = #"{"kind":"response"}"#.data(using: .utf8)!
        let template = try JSONDecoder().decode(BreakpointTemplate.self, from: json)

        #expect(template.kind == .response)
        #expect(template.name == "Untitled Response Template")
        #expect(template.rawMessage == BreakpointTemplateKind.response.sampleMessage)
        #expect(template.updatedAt >= template.createdAt)
        #expect(template.validation.isValid)
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
    func deleteSelectedTemplateFallsBackWithinSameKind() throws {
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

    // MARK: Private

    private let storageKey = "breakpointTemplates.tests"

    private func makeStore() -> BreakpointTemplateStore {
        BreakpointTemplateStore(defaults: makeDefaults(), storageKey: storageKey)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.amunx.rockxy.tests.breakpointTemplates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
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
