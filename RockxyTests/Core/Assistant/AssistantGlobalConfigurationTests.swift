@testable import Rockxy
import Testing

struct AssistantGlobalConfigurationTests {
    @Test("App settings keep model profiles and switch one global default")
    func globalDefault() {
        let openAI = AssistantProviderConfiguration(kind: .openAI, model: "fixture-cloud")
        let ollama = AssistantProviderConfiguration(kind: .ollama, model: "fixture-local")
        var settings = AppSettings()

        settings.assistantProviderConfiguration = openAI
        settings.assistantProviderConfiguration = ollama

        #expect(settings.assistantProviderConfigurations == [openAI, ollama])
        #expect(settings.activeAssistantProviderID == ollama.id)
        #expect(settings.assistantProviderConfiguration == ollama)

        settings.activeAssistantProviderID = openAI.id
        #expect(settings.assistantProviderConfiguration == openAI)
    }

    @Test("Updating a profile preserves the other global choices")
    func updateProfile() {
        var first = AssistantProviderConfiguration(kind: .ollama, model: "model-a")
        let second = AssistantProviderConfiguration(kind: .ollama, model: "model-b")
        var settings = AppSettings()
        settings.assistantProviderConfiguration = first
        settings.assistantProviderConfiguration = second

        first.baseURL = "http://127.0.0.1:22434"
        settings.assistantProviderConfiguration = first

        #expect(settings.assistantProviderConfigurations.count == 2)
        #expect(settings.assistantProviderConfiguration == first)
        #expect(settings.assistantProviderConfigurations.contains(second))
    }
}
