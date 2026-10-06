import Foundation
@testable import Rockxy
import Testing

@MainActor
struct DeveloperSetupSnippetGenerationTests {
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
        #expect(snippet?.contains("https://<your-host>/<your-path>") == true)
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

    @Test("Generated Flutter Dio snippet includes proxy host choices and debug-only safety")
    func generatedFlutterDioSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .flutter,
            snippetID: .flutterDio5,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("IOHttpClientAdapter") == true)
        #expect(snippet?.contains("enum RockxyRuntime { localAppleRuntime, androidEmulator, physicalDevice }") == true)
        #expect(snippet?.contains("enum RockxyRuntime { case") == false)
        #expect(snippet?.contains("127.0.0.1:9090") == true)
        #expect(snippet?.contains("10.0.2.2:9090") == true)
        #expect(snippet?.contains("<LAN device proxy host>:9090") == true)
        #expect(snippet?.contains("/tmp/RockxyRootCA.pem") == true)
        #expect(snippet?.contains("Debug only") == true)
        #expect(snippet?.contains("https://<your-host>/<your-path>") == true)
    }

    @Test("Flutter snippets fill in the Mac's LAN host for physical devices when Rockxy has one")
    func flutterSnippetUsesReachableLANHost() {
        for snippetID in [SetupSnippetID.flutterHttpClient, .flutterHTTPPackage, .flutterDio5] {
            let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
                for: .flutter,
                snippetID: snippetID,
                port: 9_090,
                certificatePath: nil,
                deviceProxyHost: "192.168.1.20"
            )
            #expect(snippet?.contains("const rockxyProxyForPhysicalDevice = '192.168.1.20:9090';") == true)
            #expect(snippet?.contains("<LAN device proxy host>") == false)
            #expect(snippet?.contains("const rockxyProxyForSimulator = '127.0.0.1:9090';") == true)
        }
    }

    @Test("Generated Flutter HttpClient snippet sets findProxy and badCertificateCallback")
    func generatedFlutterHttpClientSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .flutter,
            snippetID: .flutterHttpClient,
            port: 9_191,
            certificatePath: nil
        )

        #expect(snippet?.contains("HttpClient") == true)
        #expect(snippet?.contains("findProxy") == true)
        #expect(snippet?.contains("badCertificateCallback") == true)
        #expect(snippet?.contains("10.0.2.2:9191") == true)
        #expect(snippet?.contains(DeveloperSetupWorkflowCatalog.certificatePathPlaceholder) == true)
        // A WebSocket only goes through Rockxy when it is given the proxied client.
        #expect(snippet?.contains("WebSocket.connect(url, customClient: client)") == true)
    }

    @Test("Generated Flutter package:http snippet wraps IOClient")
    func generatedFlutterHTTPPackageSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .flutter,
            snippetID: .flutterHTTPPackage,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("package:http/io_client.dart") == true)
        #expect(snippet?.contains("IOClient(httpClient)") == true)
        #expect(snippet?.contains("rockxyProxyHostPort") == true)
    }

    @Test("Generated Flutter Android XML snippet keeps user CA trust debug-only")
    func generatedFlutterAndroidNetworkSecurityConfigSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .flutter,
            snippetID: .flutterAndroidNetworkSecurityConfig,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("app/src/debug/res/xml/network_security_config.xml") == true)
        #expect(snippet?.contains("<debug-overrides>") == true)
        #expect(snippet?.contains("<certificates src=\"user\" />") == true)
        #expect(snippet?.contains("Do not ship this trust policy in release builds") == true)
    }

    @Test("Generated React Native fetch snippet points at the probe and platform hosts")
    func generatedReactNativeFetchSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .reactNative,
            snippetID: .reactNativeFetchProbe,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("runRockxyReactNativeProbe") == true)
        #expect(snippet?.contains("https://<your-host>/<your-path>") == true)
        #expect(snippet?.contains("127.0.0.1:9090") == true)
        #expect(snippet?.contains("10.0.2.2:9090") == true)
        #expect(snippet?.contains("/tmp/RockxyRootCA.pem") == true)
    }

    @Test("Generated React Native Android XML snippet keeps user CA trust debug-only")
    func generatedReactNativeAndroidNetworkSecurityConfigSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .reactNative,
            snippetID: .reactNativeAndroidNetworkSecurityConfig,
            port: 9_090,
            certificatePath: "/tmp/RockxyRootCA.pem"
        )

        #expect(snippet?.contains("android/app/src/debug/res/xml/network_security_config.xml") == true)
        #expect(snippet?.contains("<debug-overrides>") == true)
        #expect(snippet?.contains("<certificates src=\"user\" />") == true)
        #expect(snippet?.contains("Do not ship this trust policy in release builds") == true)
    }

    @Test("Generated React Native Metro checklist includes adb reverse and bypass guidance")
    func generatedReactNativeMetroChecklistSnippet() {
        let snippet = DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: .reactNative,
            snippetID: .reactNativeMetroChecklist,
            port: 9_191,
            certificatePath: nil
        )

        #expect(snippet?.contains("adb reverse tcp:8081 tcp:8081") == true)
        #expect(snippet?.contains("10.0.2.2") == true)
        #expect(snippet?.contains("localhost") == true)
        #expect(snippet?.contains("Mac LAN host") == true)
        #expect(snippet?.contains(DeveloperSetupWorkflowCatalog.certificatePathPlaceholder) == true)
    }
}
