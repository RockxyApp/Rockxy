import Foundation
@testable import Rockxy
import Testing

// MARK: - AssistantProductHelpTests

struct AssistantProductHelpTests {
    @Test("Representative prompts map to the expected handoff and exact window IDs")
    func promptsMapToExactWindowIDs() {
        let catalog = AssistantProductHelpCatalog.shared
        let cases: [(prompt: String, handoff: AssistantProductHandoff, windowID: String)] = [
            ("How do I set up my Node app?", .developerSetup, "developerSetupHub"),
            ("Why can't I read the HTTPS response body?", .httpsDecryption, "sslProxyingList"),
            ("How do I mock a response with a local file?", .mapLocal, "mapLocal"),
            ("Can I redirect a request to a different server?", .mapRemote, "mapRemote"),
            ("How do I block a domain?", .blockList, "blockList"),
            ("I only want to capture certain hosts, an allow list?", .allowList, "allowList"),
            ("How do I add a header to every request?", .modifyHeaders, "modifyHeaders"),
            ("Can I throttle the network to simulate slow 3g?", .networkConditions, "networkConditions"),
            ("How do I pause a request to edit it?", .breakpointRules, "breakpointRules"),
            ("How do I route through an upstream SOCKS proxy?", .externalProxy, "externalProxySettings"),
            ("Can I write a script to modify requests?", .scripting, "scriptingList"),
        ]
        for testCase in cases {
            let matched = catalog.match(prompt: testCase.prompt)
            #expect(matched?.handoff == testCase.handoff, "\(testCase.prompt)")
            #expect(matched?.handoff.windowID == testCase.windowID, "\(testCase.prompt)")
        }
    }

    @Test("A recognized prompt returns catalog text plus its handoff")
    func recognizedDeterministicResponse() {
        let response = AssistantProductHelpCatalog.shared.deterministicResponse(
            for: "How do I map local to a file?"
        )
        #expect(response.handoff == .mapLocal)
        #expect(!response.text.isEmpty)
    }

    @Test("A general external-proxy answer never claims SOCKS5 support")
    func externalProxyAnswerDoesNotClaimSOCKS5() {
        let response = AssistantProductHelpCatalog.shared.deterministicResponse(
            for: "How do I route through an upstream proxy?"
        )
        #expect(response.handoff == .externalProxy)
        #expect(response.handoff?.windowID == "externalProxySettings")
        #expect(!response.text.localizedCaseInsensitiveContains("SOCKS"))
    }

    @Test("An explicit SOCKS5 question is answered honestly with the External Proxy handoff")
    func socks5QuestionIsAnsweredHonestly() {
        let response = AssistantProductHelpCatalog.shared.deterministicResponse(
            for: "Can I route through an upstream SOCKS5 proxy?"
        )
        #expect(response.handoff == .externalProxy)
        #expect(response.handoff?.windowID == "externalProxySettings")
        #expect(response.text.localizedCaseInsensitiveContains("SOCKS5"))
        #expect(response.text.localizedCaseInsensitiveContains("available"))
    }

    @Test("An unrecognized prompt returns an honest fallback with no handoff")
    func unknownDeterministicResponse() {
        let response = AssistantProductHelpCatalog.shared.deterministicResponse(
            for: "Tell me a joke about penguins"
        )
        #expect(response.handoff == nil)
        #expect(response.text.contains("Rockxy"))
    }

    @Test("Every handoff maps to a non-empty, unique window ID")
    func handoffWindowIDsAreValid() {
        let ids = AssistantProductHandoff.allCases.map(\.windowID)
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(Set(ids).count == ids.count)
        #expect(AssistantProductHandoff.allCases.allSatisfy { $0.actionTitle.hasPrefix("Open") })
    }

    @Test("Grounding text lists capabilities without any captured traffic")
    func groundingTextIsTrafficFree() {
        let grounding = AssistantProductHelpCatalog.shared.groundingText()
        #expect(grounding.contains("Map Local"))
        #expect(grounding.contains("HTTPS Decryption"))
        #expect(grounding.localizedCaseInsensitiveContains("application or host"))
        #expect(!grounding.contains("api.example.com"))
    }

    @Test("HTTPS Decryption help explains application and host scopes")
    func httpsDecryptionAnswerExplainsBothScopes() {
        let response = AssistantProductHelpCatalog.shared.deterministicResponse(
            for: "How do I decrypt HTTPS?"
        )

        #expect(response.handoff == .httpsDecryption)
        #expect(response.text.localizedCaseInsensitiveContains("application"))
        #expect(response.text.localizedCaseInsensitiveContains("host"))
        #expect(response.text.localizedCaseInsensitiveContains("root certificate"))
    }

    @Test("The product-help request carries the question and grounding but no traffic")
    func promptBuilderExcludesTraffic() {
        let configuration = AssistantProviderConfiguration(
            kind: .doubao,
            model: "doubao-seed-2-1-pro-260915",
            arkDeploymentID: "ep-product-help"
        )
        let conversation: [DebugAssistantMessage] = [
            .user("How do I decrypt HTTPS?"),
        ]
        let request = AssistantProductHelpPromptBuilder().build(
            question: "How do I decrypt HTTPS?",
            conversation: conversation,
            configuration: configuration
        )
        #expect(request.input == "How do I decrypt HTTPS?")
        #expect(request.model == "ep-product-help")
        #expect(request.instructions.contains("No captured network traffic"))
        #expect(request.instructions.contains("<rockxy_capabilities>"))
        #expect(!request.reviewedContentPreview.contains("Retry-After"))
    }

    @Test("Prior conversation turns are bounded into the instructions, excluding the current question")
    func promptBuilderBoundsPriorConversation() {
        let configuration = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://127.0.0.1:1234/v1",
            model: "fixture-model"
        )
        let conversation: [DebugAssistantMessage] = [
            .user("How do I block a domain?"),
            .assistant("The Block List returns 403 for matching requests."),
            .user("And how do I allow only some hosts?"),
        ]
        let request = AssistantProductHelpPromptBuilder().build(
            question: "And how do I allow only some hosts?",
            conversation: conversation,
            configuration: configuration
        )
        #expect(request.instructions.contains("block a domain"))
        #expect(request.input == "And how do I allow only some hosts?")
    }

    // MARK: Workspace summary

    @Test("Equal retained and visible counts produce a single clear current count")
    func equalCountsGiveSingleCount() {
        let summary = AssistantWorkspaceSummary(
            retainedRequestCount: 12,
            visibleRequestCount: 12,
            selectedRequestCount: 0,
            isScopeNarrowingResults: false,
            captureState: .running
        )
        let answer = summary.deterministicAnswer
        #expect(answer == "There are 12 requests currently retained in this session.")
        #expect(!answer.contains("(s)"))
        #expect(!answer.localizedCaseInsensitiveContains("out of"))
        #expect(!answer.localizedCaseInsensitiveContains("lifetime"))
    }

    @Test("A single retained request reads with singular grammar")
    func singleRetainedRequestUsesSingularCopy() {
        let summary = AssistantWorkspaceSummary(
            retainedRequestCount: 1,
            visibleRequestCount: 1,
            selectedRequestCount: 0,
            isScopeNarrowingResults: false,
            captureState: .running
        )
        let answer = summary.deterministicAnswer
        #expect(answer == "There is 1 request currently retained in this session.")
        #expect(!answer.contains("(s)"))
    }

    @Test("A visible count that differs from the retained total reports both numbers")
    func differingCountsReportVisibleAndRetained() {
        let summary = AssistantWorkspaceSummary(
            retainedRequestCount: 40,
            visibleRequestCount: 7,
            selectedRequestCount: 0,
            isScopeNarrowingResults: true,
            captureState: .running
        )
        let answer = summary.deterministicAnswer
        #expect(answer == "7 requests are showing with the current filters, out of 40 retained in this session.")
        #expect(!answer.contains("(s)"))
    }

    @Test("A single narrowed request reads with singular grammar")
    func singleNarrowedVisibleRequestUsesSingularCopy() {
        let summary = AssistantWorkspaceSummary(
            retainedRequestCount: 40,
            visibleRequestCount: 1,
            selectedRequestCount: 0,
            isScopeNarrowingResults: true,
            captureState: .running
        )
        let answer = summary.deterministicAnswer
        #expect(answer == "1 request is showing with the current filters, out of 40 retained in this session.")
        #expect(!answer.contains("(s)"))
    }

    @Test("Zero retained mentions capture state for stopped and running sessions")
    func zeroRetainedMentionsCaptureState() {
        let stopped = AssistantWorkspaceSummary(
            retainedRequestCount: 0,
            visibleRequestCount: 0,
            selectedRequestCount: 0,
            isScopeNarrowingResults: false,
            captureState: .stopped
        )
        #expect(stopped.deterministicAnswer.localizedCaseInsensitiveContains("no requests"))
        #expect(stopped.deterministicAnswer.localizedCaseInsensitiveContains("stopped"))

        let running = AssistantWorkspaceSummary(
            retainedRequestCount: 0,
            visibleRequestCount: 0,
            selectedRequestCount: 0,
            isScopeNarrowingResults: false,
            captureState: .running
        )
        #expect(running.deterministicAnswer.localizedCaseInsensitiveContains("no requests"))
        #expect(running.deterministicAnswer.localizedCaseInsensitiveContains("running"))
    }

    @Test("Natural current-count phrases are recognized, including singular grammar")
    func currentCountPhrasesRecognized() {
        let recognized = [
            "how many requests do we have now?",
            "how many requests?",
            "number of requests",
            "request count",
            "transaction count",
            "how many API calls",
            "how much traffic is showing",
            "how many request we have now?",
            "How many requests can I see now?",
        ]
        for phrase in recognized {
            #expect(AssistantWorkspaceSummary.isCurrentCountQuestion(phrase), "\(phrase)")
        }
    }

    @Test("Capability-limit questions are not treated as current-count questions")
    func capabilityQuestionsNotMisrouted() {
        let rejected = [
            "What is the maximum request limit?",
            "How many requests can Rockxy handle?",
            "How many requests can I capture?",
            "How many requests can Rockxy process?",
            "How many transactions are supported?",
        ]
        for phrase in rejected {
            #expect(!AssistantWorkspaceSummary.isCurrentCountQuestion(phrase), "\(phrase)")
        }
    }

    @Test("The model request carries aggregate workspace facts but no request content")
    func promptBuilderCarriesAggregateFacts() {
        let configuration = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://127.0.0.1:1234/v1",
            model: "fixture-model"
        )
        let summary = AssistantWorkspaceSummary(
            retainedRequestCount: 3,
            visibleRequestCount: 1,
            selectedRequestCount: 0,
            isScopeNarrowingResults: true,
            captureState: .running
        )
        let request = AssistantProductHelpPromptBuilder().build(
            question: "how many requests do we have now?",
            conversation: [.user("how many requests do we have now?")],
            configuration: configuration,
            workspaceSummary: summary
        )
        #expect(request.instructions.contains("<workspace_facts>"))
        #expect(request.instructions.contains("retained_requests: 3"))
        #expect(request.instructions.contains("visible_requests: 1"))
        #expect(request.instructions.contains("capture_state: running"))
        #expect(request.instructions.contains("no request content or identifiers"))
        #expect(!request.instructions.contains("api.example.com"))
    }
}
