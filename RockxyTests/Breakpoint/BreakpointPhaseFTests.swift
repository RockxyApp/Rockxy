import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct BreakpointPhaseFTests {
    // MARK: Internal

    /// BP_F1a
    @Test("templateStorePersistsToDisk")
    func templateStorePersistsToDisk() {
        let (defaults, key) = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        let template = store.addTemplate(kind: .request)
        store.updateTemplate(id: template.id, name: "Persisted", rawMessage: "GET /get HTTP/1.1\n\n")

        let fresh = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        #expect(fresh.requestTemplates.first?.name == "Persisted")
    }

    /// BP_F1b
    @Test("templateRoundTripFieldsIntact")
    func templateRoundTripFieldsIntact() throws {
        let template = BreakpointTemplate(
            kind: .response,
            name: "Response",
            rawMessage: "HTTP/1.1 202 Accepted\nX-A: B\n\nok"
        )
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(BreakpointTemplate.self, from: data)
        #expect(decoded.id == template.id)
        #expect(decoded.kind == .response)
        #expect(decoded.name == "Response")
        #expect(decoded.rawMessage == template.rawMessage)
    }

    /// BP_F2
    @Test("createNewTemplateOfSelectedKind")
    func createNewTemplateOfSelectedKind() {
        let (defaults, key) = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        store.selectedKind = .response
        let template = store.addTemplate()
        #expect(template.kind == .response)
        #expect(store.selectedTemplateID == template.id)
    }

    /// BP_F3
    @Test("editTemplateName")
    func editTemplateName() {
        let (defaults, key) = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        let template = store.addTemplate(kind: .request)
        store.updateTemplate(id: template.id, name: "Renamed")
        #expect(store.selectedTemplate?.name == "Renamed")
    }

    /// BP_F4a
    @Test("validationRunsOnEachRawChange")
    func validationRunsOnEachRawChange() {
        let valid = BreakpointTemplateValidator.validate(rawMessage: "GET /get HTTP/1.1\n\n", kind: .request)
        let invalid = BreakpointTemplateValidator.validate(rawMessage: "wrong", kind: .request)
        #expect(valid.isValid)
        #expect(!invalid.isValid)
    }

    /// BP_F4b
    /// Invalid raw templates remain persistable editable drafts; only the application payload is withheld.
    @Test("invalidTemplateProducesNoApplicationPayload")
    func invalidTemplateProducesNoApplicationPayload() {
        let template = BreakpointTemplate(kind: .response, name: "Bad", rawMessage: "not a response")
        #expect(template.validation.isValid == false)
        #expect(template.applicationPayload == nil)
    }

    /// BP_F5
    @Test("deleteTemplate")
    func deleteTemplate() {
        let (defaults, key) = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        let template = store.addTemplate(kind: .request)
        store.deleteTemplate(id: template.id)
        #expect(store.templates.isEmpty)
    }

    /// BP_F6
    @Test("duplicateTemplate")
    func duplicateTemplate() throws {
        let (defaults, key) = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        let template = store.addTemplate(kind: .request)
        store.updateTemplate(id: template.id, name: "Base", rawMessage: "POST /post HTTP/1.1\n\nbody")
        let duplicate = try #require(store.duplicateSelectedTemplate())
        #expect(duplicate.id != template.id)
        #expect(duplicate.rawMessage == "POST /post HTTP/1.1\n\nbody")
    }

    /// BP_F7
    @Test("resetRawMessage")
    func resetRawMessage() throws {
        let (defaults, key) = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        let template = store.addTemplate(kind: .response)
        store.updateTemplate(id: template.id, rawMessage: "HTTP/1.1 404 Not Found\n\n")
        store.resetSelectedTemplateToSample()
        let reset = try #require(store.selectedTemplate)
        #expect(reset.rawMessage == BreakpointTemplateKind.response.sampleMessage)
    }

    /// BP_F8
    @Test("persistAcrossSimulatedRestart")
    func persistAcrossSimulatedRestart() {
        let (defaults, key) = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        let template = store.addTemplate(kind: .request)
        store.updateTemplate(id: template.id, name: "Restart", rawMessage: "GET /restart HTTP/1.1\n\n")
        let fresh = BreakpointTemplateStore(defaults: defaults, storageKey: key, seedDefaults: false)
        #expect(fresh.requestTemplates.map(\.name) == ["Restart"])
    }

    /// BP_F9
    @Test("applyTemplateDuringPauseAtomic")
    func applyTemplateDuringPauseAtomic() throws {
        let template = BreakpointTemplate(
            kind: .response,
            name: "OK",
            rawMessage: "HTTP/1.1 200 OK\nContent-Type: application/json\n\n{\"ok\":true}"
        )
        let payload = try #require(template.applicationPayload)
        let updated = payload.applying(to: .test(statusCode: 401, phase: .response))
        #expect(updated.statusCode == 200)
        #expect(updated.headers.first?.name == "Content-Type")
        #expect(updated.body == "{\"ok\":true}")
    }

    /// BP_F10
    @Test("seedTemplatesNotRecreatedAfterDeletion")
    func seedTemplatesNotRecreatedAfterDeletion() {
        let (defaults, key) = makeDefaults()
        let store = BreakpointTemplateStore(defaults: defaults, storageKey: key)
        for template in store.templates {
            store.deleteTemplate(id: template.id)
        }
        let fresh = BreakpointTemplateStore(defaults: defaults, storageKey: key)
        #expect(fresh.templates.isEmpty)
    }

    // MARK: Private

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "com.amunx.rockxy.tests.breakpoint.phasef.")
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated Breakpoint Phase F test defaults.")
        }
        return (defaults, "breakpoint.templates.phasef")
    }
}
