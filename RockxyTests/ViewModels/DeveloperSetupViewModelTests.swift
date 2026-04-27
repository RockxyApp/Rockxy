import Foundation
@testable import Rockxy
import Testing

@MainActor
struct DeveloperSetupViewModelTests {
    @Test("Developer Setup defaults to Python")
    func defaultsToPython() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())

        #expect(viewModel.selectedTarget.id == .python)
        #expect(viewModel.selectedTab == .overview)
        #expect(viewModel.selectedSnippetID == .pythonRequests)
    }

    @Test("Sidebar taxonomy keeps pinned, runtime, browser, device, framework, and environment targets visible")
    func sidebarTaxonomy() {
        let pinned = SetupTarget.allSections.first(where: { $0.category == .pinned })?.targets ?? []
        let runtimes = SetupTarget.allSections.first(where: { $0.category == .runtime })?.targets ?? []
        let browsers = SetupTarget.allSections.first(where: { $0.category == .browserClient })?.targets ?? []
        let devices = SetupTarget.allSections.first(where: { $0.category == .device })?.targets ?? []
        let frameworks = SetupTarget.allSections.first(where: { $0.category == .framework })?.targets ?? []
        let environments = SetupTarget.allSections.first(where: { $0.category == .environment })?.targets ?? []

        #expect(pinned.map(\.id) == SetupTarget.defaultPinnedTargetIDs)
        #expect(runtimes.map(\.id) == [.python, .nodeJS, .ruby, .golang, .rust, .javaVMs, .curl])
        #expect(browsers.map(\.id) == [.firefox, .postman, .insomnia, .paw])
        #expect(devices.map(\.id) == [
            .iosDevice,
            .iosSimulator,
            .androidDevice,
            .androidEmulator,
            .tvOSWatchOS,
            .visionPro,
        ])
        #expect(frameworks.map(\.id) == [.flutter, .reactNative, .nextJS, .electronJS])
        #expect(environments.map(\.id) == [.docker])
    }

    @Test("Pinned targets can be added and removed from the source list")
    func pinnedTargetsCanBeToggled() throws {
        let suiteName = "DeveloperSetupPinnedStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let pinnedStore = DeveloperSetupPinnedStore(
            defaults: defaults,
            defaultsKey: "developerSetup.pinnedTargets"
        )
        let viewModel = DeveloperSetupViewModel(
            coordinator: MainContentCoordinator(),
            pinnedStore: pinnedStore
        )

        #expect(viewModel.isPinned(.python))
        #expect(viewModel.isPinned(.ruby) == false)

        viewModel.togglePinned(.ruby)
        let pinnedAfterAdd = viewModel.filteredTargetSections.first(where: { $0.category == .pinned })?.targets
            .map(\.id) ?? []
        #expect(viewModel.isPinned(.ruby))
        #expect(pinnedAfterAdd.contains(.ruby))

        viewModel.togglePinned(.python)
        let pinnedAfterRemove = viewModel.filteredTargetSections.first(where: { $0.category == .pinned })?.targets
            .map(\.id) ?? []
        #expect(viewModel.isPinned(.python) == false)
        #expect(pinnedAfterRemove.contains(.python) == false)
    }

    @Test("Runtime targets advertise terminal automation separately from manual support")
    func automationSupportForValidatedRuntimes() {
        #expect(SetupTarget.python.manualSupport == .availableNow)
        #expect(SetupTarget.python.automationSupport == .runtimeTerminal)
        #expect(SetupTarget.nodeJS.manualSupport == .availableNow)
        #expect(SetupTarget.nodeJS.automationSupport == .runtimeTerminal)
        #expect(SetupTarget.postman.automationSupport == .none)
    }

    @Test("Automation preview exists for terminal runtime targets")
    func automationPreviewForRuntimeTargets() {
        let preview = SetupTarget.automationPreview(for: .python)

        #expect(preview?.title == "Automatic Setup")
        #expect(preview?.primaryActionTitle == "Open New Terminal")
        #expect(preview?.steps.count == 4)
    }

    @Test("Source list filter narrows targets by environment name")
    func sourceListFilterByTargetName() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.sourceListSearchText = "docker"

        let sections = viewModel.filteredTargetSections

        #expect(sections.count == 1)
        #expect(sections.first?.category == .environment)
        #expect(sections.first?.targets.map(\.id) == [.docker])
    }

    @Test("Source list filter matches new category names")
    func sourceListFilterByCategoryName() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.sourceListSearchText = "Browsers & Clients"

        let sections = viewModel.filteredTargetSections

        #expect(sections.count == 1)
        #expect(sections.first?.category == .browserClient)
        #expect(sections.first?.targets.map(\.id) == [.firefox, .postman, .insomnia, .paw])
    }

    @Test("Source list filter finds Postman by name")
    func sourceListFilterFindsPostman() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.sourceListSearchText = "postman"

        let sections = viewModel.filteredTargetSections

        #expect(sections.count == 1)
        #expect(sections.first?.category == .browserClient)
        #expect(sections.first?.targets.map(\.id) == [.postman])
    }

    @Test("Source list filter finds Vision Pro by name")
    func sourceListFilterFindsVisionPro() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.sourceListSearchText = "vision"

        let sections = viewModel.filteredTargetSections

        #expect(sections.count == 1)
        #expect(sections.first?.category == .device)
        #expect(sections.first?.targets.map(\.id) == [.visionPro])
    }

    @Test("Source list filter finds runtime targets by automation support text")
    func sourceListFilterFindsAutomationTargets() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.sourceListSearchText = "automatic setup"

        let sections = viewModel.filteredTargetSections
        let runtimeIDs = sections.first(where: { $0.category == .runtime })?.targets.map(\.id) ?? []

        #expect(runtimeIDs.contains(.python))
        #expect(runtimeIDs.contains(.nodeJS))
        #expect(runtimeIDs.contains(.curl))
        #expect(runtimeIDs.contains(.javaVMs) == false)
    }

    @Test("Source list filter keeps pinned results in sync with the user's pinned set")
    func sourceListFilterRespectsPinnedTargets() throws {
        let suiteName = "DeveloperSetupPinnedFilterTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let pinnedStore = DeveloperSetupPinnedStore(
            defaults: defaults,
            defaultsKey: "developerSetup.pinnedTargets"
        )
        let viewModel = DeveloperSetupViewModel(
            coordinator: MainContentCoordinator(),
            pinnedStore: pinnedStore
        )

        viewModel.togglePinned(.ruby)
        viewModel.sourceListSearchText = "ruby"

        let pinnedIDs = viewModel.filteredTargetSections.first(where: { $0.category == .pinned })?.targets
            .map(\.id) ?? []
        let runtimeIDs = viewModel.filteredTargetSections.first(where: { $0.category == .runtime })?.targets
            .map(\.id) ?? []

        #expect(pinnedIDs == [.ruby])
        #expect(runtimeIDs == [.ruby])
    }

    @Test("Source list filter returns no sections when nothing matches")
    func sourceListFilterNoResults() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.sourceListSearchText = "zz-unmatched-query"

        #expect(viewModel.filteredTargetSections.isEmpty)
    }

    @Test("Automation sheet state only opens for supported targets and resets on target change")
    func automationSheetStateFollowsTargetSupport() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())

        #expect(viewModel.supportsAutomation == true)
        viewModel.openAutomationSheet()
        #expect(viewModel.showsAutomationSheet == true)

        viewModel.selectTarget(.postman)
        #expect(viewModel.showsAutomationSheet == false)
        #expect(viewModel.supportsAutomation == false)

        viewModel.openAutomationSheet()
        #expect(viewModel.showsAutomationSheet == false)
    }

    @Test("Node.js workflow exposes runtime snippets and validation")
    func nodeWorkflow() {
        let workflow = DeveloperSetupWorkflowCatalog.workflow(for: .nodeJS)

        #expect(workflow.snippets.map(\.id) == [.nodeAxios, .nodeHTTPS, .nodeGot])
        #expect(workflow.validation?.host == "httpbin.org")
        #expect(workflow.validation?.path == "/anything/rockxy/nodeJS")
    }

    @Test("Postman, Insomnia, and Paw ship manual config snippets + the generic httpbin capture check")
    func httpClientWorkflows() {
        let postman = DeveloperSetupWorkflowCatalog.workflow(for: .postman)
        let insomnia = DeveloperSetupWorkflowCatalog.workflow(for: .insomnia)
        let paw = DeveloperSetupWorkflowCatalog.workflow(for: .paw)

        #expect(postman.snippets.map(\.id) == [.postmanConfig])
        #expect(postman.validation?.host == "httpbin.org")
        #expect(postman.validation?.path == "/anything/rockxy/postman")

        #expect(insomnia.snippets.map(\.id) == [.insomniaConfig])
        #expect(insomnia.validation?.host == "httpbin.org")
        #expect(insomnia.validation?.path == "/anything/rockxy/insomnia")

        #expect(paw.snippets.map(\.id) == [.pawConfig])
        #expect(paw.validation?.host == "httpbin.org")
        #expect(paw.validation?.path == "/anything/rockxy/paw")
    }

    @Test("Java VMs, Docker, ElectronJS, Next.js, and Firefox ship manual workflows with the generic capture check")
    func promotedRuntimeAndEnvironmentWorkflows() {
        let javaWorkflow = DeveloperSetupWorkflowCatalog.workflow(for: .javaVMs)
        #expect(javaWorkflow.snippets.map(\.id) == [.javaKeytool, .javaHttpClient])
        #expect(javaWorkflow.validation?.host == "httpbin.org")

        let firefoxWorkflow = DeveloperSetupWorkflowCatalog.workflow(for: .firefox)
        #expect(firefoxWorkflow.snippets.map(\.id) == [.firefoxConfig])
        #expect(firefoxWorkflow.validation?.host == "httpbin.org")

        let dockerWorkflow = DeveloperSetupWorkflowCatalog.workflow(for: .docker)
        #expect(dockerWorkflow.snippets.map(\.id) == [.dockerRun])
        #expect(dockerWorkflow.validation?.host == "httpbin.org")

        let electronWorkflow = DeveloperSetupWorkflowCatalog.workflow(for: .electronJS)
        #expect(electronWorkflow.snippets.map(\.id) == [.electronCommand, .electronSession])
        #expect(electronWorkflow.validation?.host == "httpbin.org")

        let nextWorkflow = DeveloperSetupWorkflowCatalog.workflow(for: .nextJS)
        #expect(nextWorkflow.snippets.map(\.id) == [.nextJSRouteHandler])
        #expect(nextWorkflow.validation?.host == "httpbin.org")
    }

    @Test("Manual-snippet targets no longer return guide-only content")
    func promotedTargetsSkipGuideCatalog() {
        let promoted: [SetupTarget.ID] = [
            .javaVMs, .firefox, .postman, .insomnia, .paw, .docker, .electronJS, .nextJS,
        ]
        for targetID in promoted {
            #expect(
                DeveloperSetupGuideCatalog.content(for: targetID) == nil,
                "\(targetID.rawValue) should use the manual snippet workflow, not the guide catalog"
            )
        }
    }

    @Test("iOS Simulator guide explains loopback reachability and certificate trust")
    func iosSimulatorGuideContent() {
        let guide = DeveloperSetupGuideCatalog.content(for: .iosSimulator)

        #expect(guide?.setupTips.contains(where: { $0.message.contains("loopback") }) == true)
        #expect(guide?.setupTips
            .contains(where: { $0.message.contains("Trust") || $0.message.contains("trust") }) == true)
    }

    @Test("Android Emulator guide calls out 10.0.2.2 and network-security-config")
    func androidEmulatorGuideContent() {
        let guide = DeveloperSetupGuideCatalog.content(for: .androidEmulator)

        #expect(guide?.setupTips.contains(where: { $0.message.contains("10.0.2.2") }) == true)
        #expect(guide?.setupTips.contains(where: { $0.message.contains("network-security-config") }) == true)
    }

    @Test("Vision Pro guide treats the headset as an iOS-class device")
    func visionProGuideContent() {
        let guide = DeveloperSetupGuideCatalog.content(for: .visionPro)

        #expect(guide?.setupTips.contains(where: { $0.message.contains("iOS") }) == true)
        #expect(guide?.troubleshootingTips.isEmpty == false)
    }

    @Test("Snippet port uses active proxy port when capture is running")
    func snippetPortPrefersActivePort() {
        let port = DeveloperSetupViewModel.resolveSnippetPort(
            isProxyRunning: true,
            activePort: 9_191,
            configuredPort: 9_090
        )

        #expect(port == 9_191)
    }

    @Test("Snippet port falls back to configured port when proxy is stopped")
    func snippetPortFallsBackToConfiguredPort() {
        let port = DeveloperSetupViewModel.resolveSnippetPort(
            isProxyRunning: false,
            activePort: 9_191,
            configuredPort: 9_090
        )

        #expect(port == 9_090)
    }

    @Test("Validation preflight reports the first blocking issue for available manual targets")
    func validationIssuePriority() {
        let snapshot = SetupSnapshot(
            supportStatus: .availableNow,
            proxyRunning: false,
            recordingEnabled: false,
            activePort: 9_090,
            effectiveListenAddress: "127.0.0.1",
            certificateGenerated: false,
            certificateTrusted: false,
            certificateExportable: false,
            proxyMode: .unavailable,
            readinessWarningMessage: nil,
            selectedSnippetID: .pythonRequests,
            verificationState: .idle,
            matchedTransactionID: nil,
            matchedHost: nil,
            matchedMethod: nil,
            matchedPath: nil
        )

        let issue = DeveloperSetupViewModel.validationIssue(
            for: .python,
            snapshot: snapshot,
            workflow: DeveloperSetupWorkflowCatalog.workflow(for: .python)
        )

        #expect(issue == .proxyStopped)
    }

    @Test("Unavailable guide workflows surface guide-only validation state")
    func unavailableGuideWorkflowValidationIssue() {
        let snapshot = SetupSnapshot(
            supportStatus: .guideOnly,
            proxyRunning: true,
            recordingEnabled: true,
            activePort: 9_090,
            effectiveListenAddress: "127.0.0.1",
            certificateGenerated: true,
            certificateTrusted: true,
            certificateExportable: true,
            proxyMode: .direct,
            readinessWarningMessage: nil,
            selectedSnippetID: nil,
            verificationState: .idle,
            matchedTransactionID: nil,
            matchedHost: nil,
            matchedMethod: nil,
            matchedPath: nil
        )

        let guideOnlyTarget = SetupTarget(
            id: .androidDevice,
            title: String(localized: "Android Device"),
            category: .device,
            iconName: "iphone.gen2.radiowaves.left.and.right",
            manualSupport: .guideOnly,
            automationSupport: .none,
            shortSummary: "",
            manualSummary: "",
            currentSupportSummary: ""
        )

        let issue = DeveloperSetupViewModel.validationIssue(
            for: guideOnlyTarget,
            snapshot: snapshot,
            workflow: DeveloperSetupWorkflowCatalog.workflow(for: .androidDevice)
        )

        #expect(issue == .targetIsGuideOnly)
    }

    @Test("Available guide workflows surface manual validation state")
    func availableGuideWorkflowValidationIssue() {
        let snapshot = SetupSnapshot(
            supportStatus: .availableNow,
            proxyRunning: true,
            recordingEnabled: true,
            activePort: 9_090,
            effectiveListenAddress: "0.0.0.0",
            reachableLANAddress: "192.168.1.57",
            certificateGenerated: true,
            certificateTrusted: true,
            certificateExportable: true,
            proxyMode: .direct,
            readinessWarningMessage: nil,
            selectedSnippetID: nil,
            verificationState: .idle,
            matchedTransactionID: nil,
            matchedHost: nil,
            matchedMethod: nil,
            matchedPath: nil
        )

        let issue = DeveloperSetupViewModel.validationIssue(
            for: .iosDevice,
            snapshot: snapshot,
            workflow: DeveloperSetupWorkflowCatalog.workflow(for: .iosDevice)
        )

        #expect(issue == .manualValidationOnly)
    }

    @Test("Physical device guides block localhost-only proxy setup")
    func physicalDeviceGuideRequiresReachableLANProxy() {
        let snapshot = SetupSnapshot(
            supportStatus: .availableNow,
            proxyRunning: true,
            recordingEnabled: true,
            activePort: 9_090,
            effectiveListenAddress: "127.0.0.1",
            certificateGenerated: true,
            certificateTrusted: true,
            certificateExportable: true,
            proxyMode: .direct,
            readinessWarningMessage: nil,
            selectedSnippetID: nil,
            verificationState: .idle,
            matchedTransactionID: nil,
            matchedHost: nil,
            matchedMethod: nil,
            matchedPath: nil
        )

        let issue = DeveloperSetupViewModel.validationIssue(
            for: .iosDevice,
            snapshot: snapshot,
            workflow: DeveloperSetupWorkflowCatalog.workflow(for: .iosDevice)
        )

        #expect(issue == .deviceProxyUnreachable)
    }

    @Test("Validation matcher ignores old requests and matches the expected probe")
    func validationMatcher() throws {
        let validation = try #require(DeveloperSetupWorkflowCatalog.workflow(for: .python).validation)
        let validationURL = try #require(URL(string: "https://\(validation.host)\(validation.path)"))

        let oldRequest = try HTTPTransaction(
            request: HTTPRequestData(
                method: "GET",
                url: validationURL,
                httpVersion: "HTTP/1.1",
                headers: []
            )
        )
        oldRequest.sequenceNumber = 8

        let newRequest = try HTTPTransaction(
            request: HTTPRequestData(
                method: "GET",
                url: validationURL,
                httpVersion: "HTTP/1.1",
                headers: []
            )
        )
        newRequest.sequenceNumber = 12

        #expect(
            DeveloperSetupViewModel.matchesValidationTransaction(
                oldRequest,
                baselineSequenceNumber: 10,
                validation: validation
            ) == false
        )
        #expect(
            DeveloperSetupViewModel.matchesValidationTransaction(
                newRequest,
                baselineSequenceNumber: 10,
                validation: validation
            )
        )
    }

    @Test("Validation instruction clarifies the generic capture-check scope")
    func validationInstructionClarifiesGenericCaptureCheck() throws {
        let validation = try #require(DeveloperSetupWorkflowCatalog.workflow(for: .python).validation)

        #expect(validation.instruction.contains("does not attribute the request") == true)
        #expect(validation.instruction.contains("specific app or process") == true)
    }

    @Test("Available targets use manual setup language instead of validated claims")
    func availableTargetsUseManualSetupLanguage() {
        let availableTargets: [SetupTarget] = [
            .python,
            .nodeJS,
            .ruby,
            .golang,
            .rust,
            .javaVMs,
            .curl,
            .firefox,
            .postman,
            .insomnia,
            .paw,
            .iosDevice,
            .iosSimulator,
            .androidDevice,
            .androidEmulator,
            .tvOSWatchOS,
            .visionPro,
            .flutter,
            .reactNative,
            .nextJS,
            .electronJS,
            .docker,
        ]

        for target in availableTargets {
            #expect(target.shortSummary.localizedCaseInsensitiveContains("validated") == false)
            #expect(target.shortSummary.localizedCaseInsensitiveContains("fully supported") == false)
            #expect(target.currentSupportSummary.localizedCaseInsensitiveContains("validated") == false)
        }

        #expect(SetupSupportStatus.availableNow.bannerTitle == "Manual setup available")
    }

    @Test("Generated Python requests snippet points to loopback proxy and certificate path")
    func generatedPythonSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .python,
            snippetID: .pythonRequests,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("http://127.0.0.1:9090") == true)
        #expect(snippet?.contains("verify=\"/tmp/RockxyRootCA.pem\"") == true)
        #expect(snippet?.contains("https://httpbin.org/get") == true)
    }

    @Test("Generated Node.js snippet includes proxy and certificate wiring")
    func generatedNodeSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .nodeJS,
            snippetID: .nodeAxios,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("127.0.0.1") == true)
        #expect(snippet?.contains("/tmp/RockxyRootCA.pem") == true)
        #expect(snippet?.contains("https://httpbin.org/get") == true)
    }

    @Test("Generated Node.js https snippet passes proxyEnv as an environment object")
    func generatedNodeHTTPSSnippetUsesEnvironmentObject() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .nodeJS,
            snippetID: .nodeHTTPS,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("proxyEnv: {") == true)
        #expect(snippet?.contains("HTTP_PROXY: process.env.HTTP_PROXY") == true)
        #expect(snippet?.contains("HTTPS_PROXY: process.env.HTTPS_PROXY") == true)
    }

    @Test("Generated cURL snippet includes proxy flag and CA bundle")
    func generatedCurlSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .curl,
            snippetID: .curlCommand,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("--proxy 'http://127.0.0.1:9090'") == true)
        #expect(snippet?.contains("--cacert '/tmp/RockxyRootCA.pem'") == true)
    }

    @Test("Generated Ruby snippet includes proxy and CA file")
    func generatedRubySnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .ruby,
            snippetID: .rubyFaraday,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("proxy: \"http://127.0.0.1:9090\"") == true)
        #expect(snippet?.contains("ca_file: \"/tmp/RockxyRootCA.pem\"") == true)
    }

    @Test("Generated Golang snippet includes proxy and root CA")
    func generatedGoSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .golang,
            snippetID: .goNetHTTP,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("http://127.0.0.1:9090") == true)
        #expect(snippet?.contains("/tmp/RockxyRootCA.pem") == true)
    }

    @Test("Generated Rust snippet includes proxy and certificate loading")
    func generatedRustSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .rust,
            snippetID: .rustReqwest,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("Proxy::all(\"http://127.0.0.1:9090\")") == true)
        #expect(snippet?.contains("Certificate::from_pem") == true)
    }

    @Test("Generated snippets use an explicit export placeholder when no certificate path is known")
    func generatedSnippetUsesExportPlaceholderWhenPathUnknown() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .python,
            snippetID: .pythonRequests,
            port: 9_090,
            certificatePath: nil
        )

        #expect(snippet?.contains(DeveloperSetupWorkflowCatalog.certificatePathPlaceholder) == true)
    }

    @Test("View model uses the last exported certificate path when it still exists")
    func certificatePathHintUsesStoredExportPath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let certificateURL = tempDirectory.appendingPathComponent("RockxyRootCA-\(UUID().uuidString).pem")
        try Data("pem".utf8).write(to: certificateURL)
        defer { try? FileManager.default.removeItem(at: certificateURL) }

        let cleanup = installSettingsTestGuard()
        defer {
            cleanup()
            AppSettingsManager.shared.settings = AppSettingsStorage.load()
        }

        var settings = AppSettingsStorage.load()
        settings.lastExportedRootCAPath = certificateURL.path
        AppSettingsStorage.save(settings)
        AppSettingsManager.shared.settings = AppSettingsStorage.load()

        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.snapshot.certificateGenerated = true

        #expect(viewModel.certificatePathHint == certificateURL.path)
        #expect(viewModel.certificatePathStatusText == certificateURL.lastPathComponent)
    }

    @Test("Generated Java keytool snippet references the certificate path and cacerts keystore")
    func generatedJavaKeytoolSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .javaVMs,
            snippetID: .javaKeytool,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("keytool -importcert") == true)
        #expect(snippet?.contains("/tmp/RockxyRootCA.pem") == true)
        #expect(snippet?.contains("keystore=\"$( [ -n \"$JAVA_HOME\" ]") == true)
        #expect(snippet?.contains("-keystore \"$keystore\"") == true)
        #expect(snippet?.contains("prefer a dedicated") == true)
    }

    @Test("Generated Java HttpClient snippet references the proxy host and port")
    func generatedJavaHttpClientSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .javaVMs,
            snippetID: .javaHttpClient,
            port: 9_191,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("HttpClient.newBuilder()") == true)
        #expect(snippet?.contains("127.0.0.1") == true)
        #expect(snippet?.contains("9191") == true)
        #expect(snippet?.contains("https://httpbin.org/get") == true)
    }

    @Test("Generated Firefox snippet includes settings values and cURL preflight")
    func generatedFirefoxSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .firefox,
            snippetID: .firefoxConfig,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("Network Settings") == true)
        #expect(snippet?.contains("127.0.0.1") == true)
        #expect(snippet?.contains("9090") == true)
        #expect(snippet?.contains("curl --proxy http://127.0.0.1:9090") == true)
        #expect(snippet?.contains("/tmp/RockxyRootCA.pem") == true)
    }

    @Test("Generated Postman snippet carries proxy settings + cURL preflight")
    func generatedPostmanSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .postman,
            snippetID: .postmanConfig,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("Postman > Settings > Proxy") == true)
        #expect(snippet?.contains("127.0.0.1") == true)
        #expect(snippet?.contains("curl --proxy http://127.0.0.1:9090") == true)
    }

    @Test("Generated Insomnia snippet carries proxy settings + cURL preflight")
    func generatedInsomniaSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .insomnia,
            snippetID: .insomniaConfig,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("Insomnia > Preferences > Proxy") == true)
        #expect(snippet?.contains("127.0.0.1:9090") == true)
        #expect(snippet?.contains("curl --proxy http://127.0.0.1:9090") == true)
    }

    @Test("Generated Paw snippet points at macOS system proxy + cURL preflight")
    func generatedPawSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .paw,
            snippetID: .pawConfig,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("System Settings > Network") == true)
        #expect(snippet?.contains("127.0.0.1") == true)
        #expect(snippet?.contains("curl --proxy http://127.0.0.1:9090") == true)
    }

    @Test("Generated Docker snippet mounts the CA and hits host.docker.internal")
    func generatedDockerSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .docker,
            snippetID: .dockerRun,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("docker run") == true)
        #expect(snippet?.contains("host.docker.internal:9090") == true)
        #expect(snippet?.contains("'/tmp/RockxyRootCA.pem':/etc/ssl/certs/rockxy.pem:ro") == true)
        #expect(snippet?.contains("https://httpbin.org/get") == true)
    }

    @Test("Generated Electron CLI snippet uses --proxy-server + NODE_EXTRA_CA_CERTS")
    func generatedElectronCommandSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .electronJS,
            snippetID: .electronCommand,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("--proxy-server=http://127.0.0.1:9090") == true)
        #expect(snippet?.contains("NODE_EXTRA_CA_CERTS='/tmp/RockxyRootCA.pem'") == true)
    }

    @Test("Generated Electron session snippet calls session.setProxy with proxyRules")
    func generatedElectronSessionSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .electronJS,
            snippetID: .electronSession,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("NODE_EXTRA_CA_CERTS='/tmp/RockxyRootCA.pem' npx electron .") == true)
        #expect(snippet?.contains("session.defaultSession.setProxy") == true)
        #expect(snippet?.contains("proxyRules: \"http=127.0.0.1:9090;https=127.0.0.1:9090\"") == true)
    }

    @Test("Generated Next.js snippet provides a route handler + env var hints")
    func generatedNextJSSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .nextJS,
            snippetID: .nextJSRouteHandler,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("app/api/rockxy-check/route.ts") == true)
        #expect(snippet?.contains("NODE_USE_ENV_PROXY=1") == true)
        #expect(snippet?.contains("NODE_EXTRA_CA_CERTS='/tmp/RockxyRootCA.pem'") == true)
        #expect(snippet?.contains("HTTP_PROXY='http://127.0.0.1:9090'") == true)
        #expect(snippet?.contains("HTTPS_PROXY='http://127.0.0.1:9090'") == true)
        #expect(snippet?.contains("https://httpbin.org/get") == true)
    }

    @Test("Validation snippet swaps in a target-specific probe path")
    func generatedValidationSnippetUsesTargetSpecificProbe() {
        let workflow = DeveloperSetupWorkflowCatalog.workflow(for: .python)
        let snippet = DeveloperSetupWorkflowCatalog.generatedValidationSnippet(
            for: .python,
            workflow: workflow,
            selectedSnippetID: .pythonRequests,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("https://httpbin.org/anything/rockxy/python") == true)
        #expect(snippet?.contains("https://httpbin.org/get") == false)
    }

    @Test("Firefox validation snippet falls back to the cURL preflight probe")
    func generatedFirefoxValidationSnippetUsesCurlPreflight() {
        let workflow = DeveloperSetupWorkflowCatalog.workflow(for: .firefox)
        let snippet = DeveloperSetupWorkflowCatalog.generatedValidationSnippet(
            for: .firefox,
            workflow: workflow,
            selectedSnippetID: .firefoxConfig,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("curl --proxy 'http://127.0.0.1:9090'") == true)
        #expect(snippet?.contains("https://httpbin.org/anything/rockxy/firefox") == true)
    }

    @Test("Electron validation snippet falls back to the cURL preflight probe")
    func generatedElectronValidationSnippetUsesCurlPreflight() {
        let workflow = DeveloperSetupWorkflowCatalog.workflow(for: .electronJS)
        let snippet = DeveloperSetupWorkflowCatalog.generatedValidationSnippet(
            for: .electronJS,
            workflow: workflow,
            selectedSnippetID: .electronCommand,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("curl --proxy 'http://127.0.0.1:9090'") == true)
        #expect(snippet?.contains("https://httpbin.org/anything/rockxy/electronJS") == true)
    }

    @Test("View model falls back when the stored certificate export path is missing")
    func certificatePathHintFallsBackWhenStoredExportPathMissing() {
        let cleanup = installSettingsTestGuard()
        defer {
            cleanup()
            AppSettingsManager.shared.settings = AppSettingsStorage.load()
        }

        var settings = AppSettingsStorage.load()
        settings.lastExportedRootCAPath = "/tmp/does-not-exist-\(UUID().uuidString).pem"
        AppSettingsStorage.save(settings)
        AppSettingsManager.shared.settings = AppSettingsStorage.load()

        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.snapshot.certificateGenerated = true

        #expect(viewModel.certificatePathHint == nil)
        #expect(viewModel.certificatePathStatusText == "Export required")
    }

    @Test("refreshSnapshot preserves terminal verification states")
    func refreshSnapshotPreservesTerminalState() async {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())
        viewModel.snapshot.verificationState = .success
        viewModel.activeIssue = nil

        await viewModel.refreshSnapshot()

        #expect(viewModel.snapshot.verificationState == .success)
    }
}
