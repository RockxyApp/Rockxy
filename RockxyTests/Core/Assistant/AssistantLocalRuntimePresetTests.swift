import Foundation
@testable import Rockxy
import Testing

struct AssistantLocalRuntimePresetTests {
    @Test("Catalog covers every documented local runtime with stable identifiers")
    func catalogCoverage() {
        let presets = AssistantLocalRuntimePreset.all

        #expect(presets.map(\.id) == AssistantLocalRuntimePreset.ID.allCases)
        #expect(presets.map(\.id.rawValue) == [
            "ollama",
            "lmStudio",
            "llamaCppServer",
            "jan",
            "localAI",
            "mlxLMServer",
            "gpt4All",
            "openAICompatible",
        ])
        #expect(presets.allSatisfy { !$0.name.isEmpty && !$0.apiSurface.isEmpty && !$0.setupSummary.isEmpty })
        #expect(presets.filter { $0.id != .openAICompatible }.allSatisfy { $0.documentationURL != nil })
        #expect(presets.filter { $0.id != .openAICompatible }.allSatisfy { $0.defaultBaseURL != nil })
    }

    @Test("Only Ollama is managed; every other preset maps to the OpenAI-compatible adapter")
    func adapterAndTierMapping() {
        for preset in AssistantLocalRuntimePreset.all {
            switch preset.id {
            case .ollama:
                #expect(preset.providerKind == .ollama)
                #expect(preset.integrationTier == .managed)
                #expect(preset.managesModelDownloads)
            case .lmStudio,
                 .llamaCppServer:
                #expect(preset.providerKind == .openAICompatible)
                #expect(preset.integrationTier == .optimized)
                #expect(!preset.managesModelDownloads)
            case .jan,
                 .localAI,
                 .mlxLMServer,
                 .gpt4All,
                 .openAICompatible:
                #expect(preset.providerKind == .openAICompatible)
                #expect(preset.integrationTier == .compatible)
                #expect(!preset.managesModelDownloads)
            }
        }
        #expect(Set(AssistantProviderKind.allCases.map(\.rawValue)).count == 10)
    }

    @Test("Preset default endpoints are loopback and pass endpoint security")
    func defaultEndpointsAreLocal() {
        for preset in AssistantLocalRuntimePreset.all {
            let configuration = preset.makeConfiguration()
            #expect(configuration.kind == preset.providerKind)
            #expect(configuration.localRuntimePresetID == preset.id)
            #expect(configuration.model.isEmpty)
            #expect(configuration.endpointSecurity == .localLoopback, "\(preset.id)")
            #expect(configuration.executionLocation == .localServer, "\(preset.id)")
            let expectedBaseURL = preset.defaultBaseURL ?? preset.providerKind.defaultBaseURL
            #expect(configuration.baseURL == expectedBaseURL)
        }
    }

    @Test("Applying a preset only touches kind, base URL, and the model when the runtime changes")
    func applyPreset() {
        let original = AssistantProviderConfiguration(
            kind: .ollama,
            model: "qwen3.5:4b",
            maxOutputTokens: 1_024,
            redactSensitiveData: false
        )

        let lmStudio = AssistantLocalRuntimePreset.preset(id: .lmStudio).applied(to: original)
        #expect(lmStudio.id == original.id)
        #expect(lmStudio.kind == .openAICompatible)
        #expect(lmStudio.localRuntimePresetID == .lmStudio)
        #expect(lmStudio.baseURL == "http://127.0.0.1:1234/v1")
        #expect(lmStudio.model.isEmpty)
        #expect(lmStudio.maxOutputTokens == 1_024)
        #expect(!lmStudio.redactSensitiveData)

        let unchanged = AssistantLocalRuntimePreset.preset(id: .ollama).applied(to: original)
        #expect(unchanged.localRuntimePresetID == .ollama)
        #expect(unchanged.model == original.model)
        #expect(unchanged.maxOutputTokens == original.maxOutputTokens)
    }

    @Test("Configurations resolve to a preset only when the endpoint is unambiguous")
    func matching() {
        func configuration(_ kind: AssistantProviderKind, _ baseURL: String) -> AssistantProviderConfiguration {
            AssistantProviderConfiguration(kind: kind, baseURL: baseURL)
        }

        #expect(AssistantLocalRuntimePreset.matching(configuration(.ollama, "http://127.0.0.1:11434"))?.id == .ollama)
        #expect(AssistantLocalRuntimePreset.matching(configuration(.ollama, "http://localhost:11434/v1"))?
            .id == .ollama)
        #expect(
            AssistantLocalRuntimePreset.matching(configuration(.openAICompatible, "http://127.0.0.1:1234/v1"))?.id
                == .lmStudio
        )
        #expect(
            AssistantLocalRuntimePreset.matching(configuration(.openAICompatible, "http://localhost:1234/v1/"))?.id
                == .lmStudio
        )
        #expect(
            AssistantLocalRuntimePreset.matching(configuration(.openAICompatible, "http://[::1]:1337/v1"))?.id == .jan
        )
        #expect(
            AssistantLocalRuntimePreset.matching(configuration(.openAICompatible, "http://127.0.0.1:4891/v1"))?.id
                == .gpt4All
        )
        // Port 8080 is shared by llama.cpp, LocalAI, and MLX-LM.
        #expect(AssistantLocalRuntimePreset
            .matching(configuration(.openAICompatible, "http://127.0.0.1:8080/v1")) == nil)
        var persistedLlama = configuration(.openAICompatible, "http://127.0.0.1:8080/v1")
        persistedLlama.localRuntimePresetID = .llamaCppServer
        #expect(AssistantLocalRuntimePreset.matching(persistedLlama)?.id == .llamaCppServer)
        persistedLlama.baseURL = "http://127.0.0.1:9090/v1"
        #expect(AssistantLocalRuntimePreset.matching(persistedLlama)?.id == .llamaCppServer)
        #expect(
            AssistantLocalRuntimePreset.matching(configuration(.openAICompatible, "http://127.0.0.1:5000/v1"))?.id
                == .openAICompatible
        )
        #expect(
            AssistantLocalRuntimePreset.matching(configuration(.openAICompatible, "https://models.example.com/v1"))?.id
                == .openAICompatible
        )
        #expect(AssistantLocalRuntimePreset.matching(configuration(.openAI, "https://api.openai.com/v1")) == nil)
        #expect(AssistantLocalRuntimePreset.matching(configuration(.deepSeek, "http://127.0.0.1:1234/v1")) == nil)
    }

    @Test("Named runtime identity survives configuration persistence and endpoint editing")
    func presetIdentityRoundTrips() throws {
        var configuration = AssistantLocalRuntimePreset.preset(id: .mlxLMServer).makeConfiguration()
        configuration.baseURL = "http://127.0.0.1:9090/v1"
        configuration.model = "mlx-community/model"

        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AssistantProviderConfiguration.self, from: encoded)

        #expect(decoded.localRuntimePresetID == .mlxLMServer)
        #expect(AssistantLocalRuntimePreset.matching(decoded)?.id == .mlxLMServer)
        #expect(decoded.baseURL == "http://127.0.0.1:9090/v1")
    }

    @Test("Ark model and deployment identities persist independently")
    func arkDeploymentIdentityRoundTrips() throws {
        let configuration = AssistantProviderConfiguration(
            kind: .doubao,
            model: "doubao-seed-2-1-pro-260915",
            arkDeploymentID: "ep-example"
        )
        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AssistantProviderConfiguration.self, from: encoded)

        #expect(decoded.model == "doubao-seed-2-1-pro-260915")
        #expect(decoded.arkDeploymentID == "ep-example")
        #expect(decoded.apiModelIdentifier == "ep-example")

        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "arkDeploymentID")
        let legacyDecoded = try JSONDecoder().decode(
            AssistantProviderConfiguration.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        #expect(legacyDecoded.arkDeploymentID == nil)
        #expect(legacyDecoded.apiModelIdentifier == legacyDecoded.model)
    }

    @Test("Model picker presentation distinguishes local and remote destinations")
    func modelSelectionPresentation() {
        var local = AssistantLocalRuntimePreset.preset(id: .llamaCppServer).makeConfiguration()
        local.model = "traffic-model"
        let localPresentation = AssistantModelSelectionPresentation(
            configuration: local,
            isModelAccessEnabled: true,
            usesConfiguredModel: true
        )
        #expect(localPresentation.isConfiguredModelAvailable)
        #expect(localPresentation.selectionLabel.contains("llama.cpp server"))
        #expect(localPresentation.selectionSystemImage == "desktopcomputer")
        #expect(localPresentation.destinationSystemImage == "lock.fill")

        let remote = AssistantProviderConfiguration(kind: .openAI, model: "gpt-4.1")
        let remotePresentation = AssistantModelSelectionPresentation(
            configuration: remote,
            isModelAccessEnabled: true,
            usesConfiguredModel: true
        )
        #expect(remotePresentation.isConfiguredModelAvailable)
        #expect(remotePresentation.selectionSystemImage == "cloud")
        #expect(remotePresentation.destinationSystemImage == "arrow.up.forward.app")

        let builtInPresentation = AssistantModelSelectionPresentation(
            configuration: local,
            isModelAccessEnabled: true,
            usesConfiguredModel: false
        )
        #expect(builtInPresentation.selectionSystemImage == "cpu")
    }
}
