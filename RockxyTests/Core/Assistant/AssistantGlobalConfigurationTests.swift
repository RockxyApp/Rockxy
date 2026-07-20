import Foundation
@testable import Rockxy
import Testing

struct AssistantGlobalConfigurationTests {
    @Test("Legacy provider profiles receive the bounded default output limit")
    func legacyTokenLimitMigration() throws {
        let id = UUID()
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "kind": "openAI",
              "baseURL": "https://api.openai.com/v1",
              "model": "fixture-model",
              "storeResponses": false,
              "redactSensitiveData": true
            }
            """.utf8
        )

        let configuration = try JSONDecoder().decode(AssistantProviderConfiguration.self, from: data)

        #expect(configuration.maxOutputTokens == AssistantProviderConfiguration.defaultMaxOutputTokens)
        #expect(configuration.id == id)
    }

    @Test("Output limits and endpoint security are bounded at the configuration edge")
    func tokenAndEndpointPolicy() {
        let excessive = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "https://models.example.com/v1",
            model: "fixture",
            maxOutputTokens: .max
        )
        let local = AssistantProviderConfiguration(
            kind: .ollama,
            baseURL: "http://127.0.0.2:11434",
            model: "fixture"
        )
        let insecure = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://models.example.com/v1",
            model: "fixture"
        )

        #expect(excessive.maxOutputTokens == AssistantProviderConfiguration.maxAllowedOutputTokens)
        #expect(excessive.endpointSecurity == .encrypted)
        #expect(local.endpointSecurity == .localLoopback)
        #expect(insecure.endpointSecurity == .insecureRemote)
        #expect(!insecure.endpointSecurity.permitsCapturedData)
    }

    @Test("Model family is independent from runtime and cloud provider")
    func modelFamilyIsRuntimeIndependent() {
        let modelID = "qwen3:4b"
        let ollama = AssistantProviderConfiguration(kind: .ollama, model: modelID)
        let lmStudioCompatible = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://127.0.0.1:1234/v1",
            model: modelID
        )
        let qwenCloud = AssistantProviderConfiguration(
            kind: .qwen,
            baseURL: "https://workspace.dashscope.aliyuncs.com/v1",
            model: modelID
        )

        #expect(ollama.model == lmStudioCompatible.model)
        #expect(lmStudioCompatible.model == qwenCloud.model)
        #expect(ollama.executionLocation == .localServer)
        #expect(lmStudioCompatible.executionLocation == .localServer)
        #expect(qwenCloud.executionLocation == .cloudService)
        #expect(ollama.kind.descriptor.apiDialect == .ollamaNative)
        #expect(lmStudioCompatible.kind.descriptor.apiDialect == .openAIChatCompletions)
        #expect(qwenCloud.kind.descriptor.apiDialect == .openAIChatCompletions)
    }

    @Test("China provider presets reuse a compatible dialect without hard-coded model IDs")
    func chinaProviderArchitecture() {
        let providers: [AssistantProviderKind] = [.deepSeek, .qwen, .kimi, .doubao, .glm]

        for provider in providers {
            #expect(provider.isImplemented)
            #expect(provider.requiresCredential)
            #expect(provider.group == .china)
            #expect(provider.descriptor.apiDialect == .openAIChatCompletions)
            #expect(provider.descriptor.costModel == .providerBilled)
            #expect(provider.defaultModel.isEmpty)
        }

        #expect(AssistantProviderKind.qwen.descriptor.modelCatalogStrategy == .manualEntry)
        #expect(AssistantProviderKind.qwen.capabilities?.modelDiscovery == false)
        #expect(AssistantProviderKind.qwen.defaultBaseURL.isEmpty)
    }

    @Test("Official providers stay pinned while configurable providers remain extensible")
    func providerEndpointPolicies() throws {
        let official = try #require(URL(string: "https://api.openai.com/v1"))
        let impersonating = try #require(URL(string: "https://models.example.com/v1"))
        let regionalQwen = try #require(URL(string: "https://workspace.dashscope.aliyuncs.com/v1"))

        #expect(AssistantProviderKind.openAI.descriptor.endpointPolicy.permits(
            official,
            security: .encrypted
        ))
        #expect(!AssistantProviderKind.openAI.descriptor.endpointPolicy.permits(
            impersonating,
            security: .encrypted
        ))
        #expect(AssistantProviderKind.qwen.descriptor.endpointPolicy.permits(
            regionalQwen,
            security: .encrypted
        ))
        #expect(!AssistantProviderKind.qwen.descriptor.endpointPolicy.permits(
            impersonating,
            security: .encrypted
        ))
    }

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
