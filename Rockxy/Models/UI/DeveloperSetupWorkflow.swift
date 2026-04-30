import Foundation

// MARK: - SetupSnippetID

enum SetupSnippetID: String, CaseIterable, Identifiable, Equatable {
    case pythonRequests
    case pythonHTTPX
    case pythonAIOHTTP
    case pythonURLLib3
    case nodeAxios
    case nodeHTTPS
    case nodeGot
    case curlCommand
    case curlEnvironment
    case rubyNetHTTP
    case rubyHTTP
    case rubyFaraday
    case goNetHTTP
    case goResty
    case rustReqwest
    case javaKeytool
    case javaHttpClient
    case firefoxConfig
    case postmanConfig
    case insomniaConfig
    case pawConfig
    case dockerRun
    case electronCommand
    case electronSession
    case nextJSRouteHandler
    case flutterHttpClient
    case flutterHTTPPackage
    case flutterDio5
    case flutterAndroidNetworkSecurityConfig
    case reactNativeFetchProbe
    case reactNativeAndroidNetworkSecurityConfig
    case reactNativeMetroChecklist

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pythonRequests:
            "requests"
        case .pythonHTTPX:
            "httpx"
        case .pythonAIOHTTP:
            "aiohttp"
        case .pythonURLLib3:
            "urllib3"
        case .nodeAxios:
            "axios"
        case .nodeHTTPS:
            "https"
        case .nodeGot:
            "got"
        case .curlCommand:
            String(localized: "Command")
        case .curlEnvironment:
            String(localized: "Env")
        case .rubyNetHTTP:
            "net/http"
        case .rubyHTTP:
            "http"
        case .rubyFaraday:
            "Faraday"
        case .goNetHTTP:
            "net/http"
        case .goResty:
            "Resty"
        case .rustReqwest:
            "reqwest"
        case .javaKeytool:
            String(localized: "keytool")
        case .javaHttpClient:
            "HttpClient"
        case .firefoxConfig:
            String(localized: "Settings")
        case .postmanConfig:
            String(localized: "Settings")
        case .insomniaConfig:
            String(localized: "Settings")
        case .pawConfig:
            String(localized: "Settings")
        case .dockerRun:
            "docker run"
        case .electronCommand:
            String(localized: "CLI flag")
        case .electronSession:
            "session.setProxy"
        case .nextJSRouteHandler:
            String(localized: "Route handler")
        case .flutterHttpClient:
            "HttpClient"
        case .flutterHTTPPackage:
            "package:http"
        case .flutterDio5:
            "Dio 5"
        case .flutterAndroidNetworkSecurityConfig:
            String(localized: "Android XML")
        case .reactNativeFetchProbe:
            "fetch"
        case .reactNativeAndroidNetworkSecurityConfig:
            String(localized: "Android XML")
        case .reactNativeMetroChecklist:
            String(localized: "Metro checklist")
        }
    }
}

// MARK: - SetupSnippet

struct SetupSnippet: Identifiable, Equatable {
    let id: SetupSnippetID
    let title: String
}

// MARK: - SetupValidationSpec

struct SetupValidationSpec: Equatable {
    let method: String
    let host: String
    let path: String
    let instruction: String
    let preferredSnippetID: SetupSnippetID?
}

// MARK: - SetupWorkflow

struct SetupWorkflow: Equatable {
    let snippets: [SetupSnippet]
    let validation: SetupValidationSpec?

    var defaultSnippetID: SetupSnippetID? {
        snippets.first?.id
    }

    var supportsSnippets: Bool {
        !snippets.isEmpty
    }

    var supportsValidation: Bool {
        validation != nil
    }
}

// MARK: - DeveloperSetupWorkflowCatalog

enum DeveloperSetupWorkflowCatalog {
    // MARK: Internal

    static let certificatePathPlaceholder = "<path to exported RockxyRootCA.pem>"

    static func workflow(for targetID: SetupTarget.ID) -> SetupWorkflow {
        switch targetID {
        case .python:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .pythonRequests, title: "requests"),
                    SetupSnippet(id: .pythonHTTPX, title: "httpx"),
                    SetupSnippet(id: .pythonAIOHTTP, title: "aiohttp"),
                    SetupSnippet(id: .pythonURLLib3, title: "urllib3"),
                ],
                validation: validationSpec(for: .python, runtimeName: "Python")
            )

        case .nodeJS:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .nodeAxios, title: "axios"),
                    SetupSnippet(id: .nodeHTTPS, title: "https"),
                    SetupSnippet(id: .nodeGot, title: "got"),
                ],
                validation: validationSpec(for: .nodeJS, runtimeName: "Node.js")
            )

        case .curl:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .curlCommand, title: String(localized: "Command")),
                    SetupSnippet(id: .curlEnvironment, title: String(localized: "Env")),
                ],
                validation: validationSpec(for: .curl, runtimeName: "cURL")
            )

        case .ruby:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .rubyNetHTTP, title: "net/http"),
                    SetupSnippet(id: .rubyHTTP, title: "http"),
                    SetupSnippet(id: .rubyFaraday, title: "Faraday"),
                ],
                validation: validationSpec(for: .ruby, runtimeName: "Ruby")
            )

        case .golang:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .goNetHTTP, title: "net/http"),
                    SetupSnippet(id: .goResty, title: "Resty"),
                ],
                validation: validationSpec(for: .golang, runtimeName: "Golang")
            )

        case .rust:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .rustReqwest, title: "reqwest"),
                ],
                validation: validationSpec(for: .rust, runtimeName: "Rust")
            )

        case .javaVMs:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .javaKeytool, title: String(localized: "keytool")),
                    SetupSnippet(id: .javaHttpClient, title: "HttpClient"),
                ],
                validation: validationSpec(for: .javaVMs, runtimeName: "Java", preferredSnippetID: .javaHttpClient)
            )

        case .firefox:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .firefoxConfig, title: String(localized: "Settings")),
                ],
                validation: validationSpec(for: .firefox, runtimeName: "Firefox", preferredSnippetID: .curlCommand)
            )

        case .postman:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .postmanConfig, title: String(localized: "Settings")),
                ],
                validation: validationSpec(for: .postman, runtimeName: "Postman", preferredSnippetID: .curlCommand)
            )

        case .insomnia:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .insomniaConfig, title: String(localized: "Settings")),
                ],
                validation: validationSpec(for: .insomnia, runtimeName: "Insomnia", preferredSnippetID: .curlCommand)
            )

        case .paw:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .pawConfig, title: String(localized: "Settings")),
                ],
                validation: validationSpec(for: .paw, runtimeName: "Paw", preferredSnippetID: .curlCommand)
            )

        case .docker:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .dockerRun, title: "docker run"),
                ],
                validation: validationSpec(for: .docker, runtimeName: "Docker", preferredSnippetID: .dockerRun)
            )

        case .electronJS:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .electronCommand, title: String(localized: "CLI flag")),
                    SetupSnippet(id: .electronSession, title: "session.setProxy"),
                ],
                validation: validationSpec(
                    for: .electronJS,
                    runtimeName: "Electron",
                    preferredSnippetID: .electronCommand
                )
            )

        case .nextJS:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .nextJSRouteHandler, title: String(localized: "Route handler")),
                ],
                validation: validationSpec(
                    for: .nextJS,
                    runtimeName: "Next.js",
                    preferredSnippetID: .nextJSRouteHandler
                )
            )

        case .flutter:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .flutterDio5, title: "Dio 5"),
                    SetupSnippet(id: .flutterHttpClient, title: "HttpClient"),
                    SetupSnippet(id: .flutterHTTPPackage, title: "package:http"),
                    SetupSnippet(id: .flutterAndroidNetworkSecurityConfig, title: String(localized: "Android XML")),
                ],
                validation: validationSpec(for: .flutter, runtimeName: "Flutter", preferredSnippetID: .flutterDio5)
            )

        case .reactNative:
            SetupWorkflow(
                snippets: [
                    SetupSnippet(id: .reactNativeFetchProbe, title: "fetch"),
                    SetupSnippet(
                        id: .reactNativeAndroidNetworkSecurityConfig,
                        title: String(localized: "Android XML")
                    ),
                    SetupSnippet(id: .reactNativeMetroChecklist, title: String(localized: "Metro checklist")),
                ],
                validation: validationSpec(
                    for: .reactNative,
                    runtimeName: "React Native",
                    preferredSnippetID: .reactNativeFetchProbe
                )
            )

        case .iosDevice,
             .iosSimulator,
             .androidDevice,
             .androidEmulator,
             .tvOSWatchOS,
             .visionPro:
            SetupWorkflow(snippets: [], validation: nil)
        }
    }

    static func steps(
        for target: SetupTarget,
        snapshot: SetupSnapshot,
        selectedSnippetID: SetupSnippetID?
    )
        -> [SetupStep]
    {
        let snippetTitle = snippetStepTitle(for: target.id)
        let snippetDescription = snippetStepDescription(for: target.id)

        return [
            SetupStep(
                id: "proxy",
                title: String(localized: "Proxy status"),
                description: snapshot.proxyRunning
                    ?
                    String(
                        localized: "Rockxy is listening on \(snapshot.effectiveListenAddress):\(snapshot.activePort)."
                    )
                    : String(localized: "Start Rockxy before you point \(target.title) traffic at the local proxy."),
                actionTitle: String(localized: "Verify"),
                actionKind: .verifyProxy,
                isComplete: snapshot.proxyRunning && snapshot.recordingEnabled,
                isEnabled: true
            ),
            SetupStep(
                id: "certificate",
                title: String(localized: "Certificate"),
                description: snapshot.certificateTrusted
                    ? String(localized: "The Rockxy root certificate is trusted for HTTPS interception.")
                    :
                    String(
                        localized: "Trust and export the Rockxy root certificate before validating HTTPS requests."
                    ),
                actionTitle: String(localized: "Open Certificate"),
                actionKind: .openCertificate,
                isComplete: snapshot.certificateTrusted && snapshot.certificateExportable,
                isEnabled: true
            ),
            SetupStep(
                id: "snippet",
                title: snippetTitle,
                description: snippetDescription,
                actionTitle: String(localized: "Copy"),
                actionKind: .copySnippet,
                isComplete: selectedSnippetID != nil,
                isEnabled: selectedSnippetID != nil
            ),
            SetupStep(
                id: "validate",
                title: String(localized: "Verify capture"),
                description: snapshot.verificationState == .success
                    ? String(localized: "Rockxy saw the validation request and can reveal it in the main window.")
                    : String(localized: "Run the validation request and wait for the first matching capture."),
                actionTitle: String(localized: "Run Test"),
                actionKind: .runValidation,
                isComplete: snapshot.verificationState == .success,
                isEnabled: true
            ),
        ]
    }

    static func generatedSnippet(
        for targetID: SetupTarget.ID,
        snippetID: SetupSnippetID,
        port: Int,
        certificatePath: String?
    )
        -> String?
    {
        let proxyURL = "http://127.0.0.1:\(port)"
        let rawCertificatePath = certificatePath ?? certificatePathPlaceholder

        let snippet: String? = switch (targetID, snippetID) {
        case (.python, .pythonRequests):
            pythonRequestsSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.python, .pythonHTTPX):
            pythonHTTPXSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.python, .pythonAIOHTTP):
            pythonAIOHTTPSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.python, .pythonURLLib3):
            pythonURLLib3Snippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.nodeJS, .nodeAxios):
            nodeAxiosSnippet(port: port, certPath: rawCertificatePath)
        case (.nodeJS, .nodeHTTPS):
            nodeHTTPSSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.nodeJS, .nodeGot):
            nodeGotSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.curl, .curlCommand):
            curlCommandSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.curl, .curlEnvironment):
            curlEnvironmentSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.ruby, .rubyNetHTTP):
            rubyNetHTTPSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.ruby, .rubyHTTP):
            rubyHTTPSnippet(port: port, certPath: rawCertificatePath)
        case (.ruby, .rubyFaraday):
            rubyFaradaySnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.golang, .goNetHTTP):
            goNetHTTPSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.golang, .goResty):
            goRestySnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.rust, .rustReqwest):
            rustReqwestSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.javaVMs, .javaKeytool):
            javaKeytoolSnippet(certPath: rawCertificatePath)
        case (.javaVMs, .javaHttpClient):
            javaHttpClientSnippet(port: port, certPath: rawCertificatePath)
        case (.firefox, .firefoxConfig):
            firefoxConfigSnippet(port: port, certPath: rawCertificatePath)
        case (.postman, .postmanConfig):
            postmanConfigSnippet(port: port, certPath: rawCertificatePath)
        case (.insomnia, .insomniaConfig):
            insomniaConfigSnippet(port: port, certPath: rawCertificatePath)
        case (.paw, .pawConfig):
            pawConfigSnippet(port: port, certPath: rawCertificatePath)
        case (.docker, .dockerRun):
            dockerRunSnippet(port: port, certPath: rawCertificatePath)
        case (.electronJS, .electronCommand):
            electronCommandSnippet(port: port, certPath: rawCertificatePath)
        case (.electronJS, .electronSession):
            electronSessionSnippet(port: port, certPath: rawCertificatePath)
        case (.nextJS, .nextJSRouteHandler):
            nextJSRouteHandlerSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
        case (.flutter, .flutterHttpClient):
            DeveloperSetupMobileSnippetCatalog.flutterHttpClientSnippet(port: port, certPath: rawCertificatePath)
        case (.flutter, .flutterHTTPPackage):
            DeveloperSetupMobileSnippetCatalog.flutterHTTPPackageSnippet(port: port, certPath: rawCertificatePath)
        case (.flutter, .flutterDio5):
            DeveloperSetupMobileSnippetCatalog.flutterDio5Snippet(port: port, certPath: rawCertificatePath)
        case (.flutter, .flutterAndroidNetworkSecurityConfig):
            DeveloperSetupMobileSnippetCatalog.flutterAndroidNetworkSecurityConfigSnippet(certPath: rawCertificatePath)
        case (.reactNative, .reactNativeFetchProbe):
            DeveloperSetupMobileSnippetCatalog.reactNativeFetchProbeSnippet(port: port, certPath: rawCertificatePath)
        case (.reactNative, .reactNativeAndroidNetworkSecurityConfig):
            DeveloperSetupMobileSnippetCatalog.reactNativeAndroidNetworkSecurityConfigSnippet(certPath: rawCertificatePath)
        case (.reactNative, .reactNativeMetroChecklist):
            DeveloperSetupMobileSnippetCatalog.reactNativeMetroChecklistSnippet(port: port, certPath: rawCertificatePath)
        default:
            nil
        }

        guard let snippet else {
            return nil
        }

        return snippet
    }

    static func generatedValidationSnippet(
        for targetID: SetupTarget.ID,
        workflow: SetupWorkflow,
        selectedSnippetID: SetupSnippetID,
        port: Int,
        certificatePath: String?
    )
        -> String?
    {
        let validationSnippetID = workflow.validation?.preferredSnippetID ?? selectedSnippetID
        let proxyURL = "http://127.0.0.1:\(port)"
        let rawCertificatePath = certificatePath ?? certificatePathPlaceholder
        let validationURL = validationURL(for: targetID)

        if let snippet = generatedSnippet(
            for: targetID,
            snippetID: validationSnippetID,
            port: port,
            certificatePath: certificatePath
        ), snippet.contains(defaultValidationURL) {
            return snippet.replacingOccurrences(of: defaultValidationURL, with: validationURL)
        }

        return curlCommandSnippet(proxyURL: proxyURL, certPath: rawCertificatePath)
            .replacingOccurrences(of: defaultValidationURL, with: validationURL)
    }

    // MARK: Private

    private enum StringLiteralLanguage {
        case python
        case javaScript
        case ruby
        case go
        case rust
        case java
        case dart
    }

    private static let defaultValidationURL = "https://httpbin.org/get"

    private static func pythonRequestsSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .python)
        let certPath = escapeForStringLiteral(certPath, language: .python)
        return """
        import requests

        proxies = {
            "http": "\(proxyURL)",
            "https": "\(proxyURL)",
        }

        response = requests.get(
            "https://httpbin.org/get",
            proxies=proxies,
            verify="\(certPath)",
            timeout=10,
        )
        print(response.status_code)
        print(response.json())
        """
    }

    private static func pythonHTTPXSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .python)
        let certPath = escapeForStringLiteral(certPath, language: .python)
        return """
        import httpx

        with httpx.Client(proxy="\(proxyURL)", verify="\(certPath)", timeout=10.0) as client:
            response = client.get("https://httpbin.org/get")
            print(response.status_code)
            print(response.json())
        """
    }

    private static func pythonAIOHTTPSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .python)
        let certPath = escapeForStringLiteral(certPath, language: .python)
        return """
        import aiohttp
        import asyncio
        import ssl

        async def main():
            ssl_context = ssl.create_default_context(cafile="\(certPath)")
            timeout = aiohttp.ClientTimeout(total=10)

            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(
                    "https://httpbin.org/get",
                    proxy="\(proxyURL)",
                    ssl=ssl_context,
                ) as response:
                    print(response.status)
                    print(await response.json())

        asyncio.run(main())
        """
    }

    private static func pythonURLLib3Snippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .python)
        let certPath = escapeForStringLiteral(certPath, language: .python)
        return """
        import urllib3

        http = urllib3.ProxyManager(
            "\(proxyURL)",
            cert_reqs="CERT_REQUIRED",
            ca_certs="\(certPath)",
        )

        response = http.request("GET", "https://httpbin.org/get")
        print(response.status)
        print(response.data.decode())
        """
    }

    private static func nodeAxiosSnippet(port: Int, certPath: String) -> String {
        let certPath = escapeForStringLiteral(certPath, language: .javaScript)
        return """
        import axios from "axios";
        import fs from "node:fs";
        import https from "node:https";

        const response = await axios.get("https://httpbin.org/get", {
          proxy: { protocol: "http", host: "127.0.0.1", port: \(port) },
          httpsAgent: new https.Agent({ ca: fs.readFileSync("\(certPath)") }),
          timeout: 10_000,
        });

        console.log(response.status);
        console.log(response.data);
        """
    }

    private static func nodeHTTPSSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .javaScript)
        let certPath = escapeForStringLiteral(certPath, language: .javaScript)
        return """
        import fs from "node:fs";
        import https from "node:https";

        process.env.HTTP_PROXY = "\(proxyURL)";
        process.env.HTTPS_PROXY = "\(proxyURL)";

        const agent = new https.Agent({
          ca: fs.readFileSync("\(certPath)"),
          proxyEnv: {
            HTTP_PROXY: process.env.HTTP_PROXY,
            HTTPS_PROXY: process.env.HTTPS_PROXY,
          },
        });

        const request = https.request("https://httpbin.org/get", {
          host: "httpbin.org",
          path: "/get",
          method: "GET",
          port: 443,
          agent,
          headers: {},
        });

        request.on("response", (response) => {
          console.log(response.statusCode);
          response.setEncoding("utf8");
          response.on("data", (chunk) => process.stdout.write(chunk));
        });

        request.end();
        """
    }

    private static func nodeGotSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .javaScript)
        let certPath = escapeForStringLiteral(certPath, language: .javaScript)
        return """
        import fs from "node:fs";
        import got from "got";
        import { HttpsProxyAgent } from "https-proxy-agent";

        const agent = {
          https: new HttpsProxyAgent("\(proxyURL)"),
        };

        const response = await got("https://httpbin.org/get", {
          agent,
          https: { certificateAuthority: fs.readFileSync("\(certPath)") },
          timeout: { request: 10_000 },
        });

        console.log(response.statusCode);
        console.log(response.body);
        """
    }

    private static func curlCommandSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForShell(proxyURL)
        let certPath = escapeForShell(certPath)
        return """
        curl --proxy \(proxyURL) \\
          --cacert \(certPath) \\
          --request GET \\
          "https://httpbin.org/get"
        """
    }

    private static func curlEnvironmentSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForShell(proxyURL)
        let certPath = escapeForShell(certPath)
        return """
        export HTTP_PROXY=\(proxyURL)
        export HTTPS_PROXY=\(proxyURL)

        curl --cacert \(certPath) "https://httpbin.org/get"
        """
    }

    private static func rubyNetHTTPSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .ruby)
        let certPath = escapeForStringLiteral(certPath, language: .ruby)
        return """
        require "net/http"
        require "openssl"
        require "uri"

        proxy_uri = URI("\(proxyURL)")
        target_uri = URI("https://httpbin.org/get")

        http = Net::HTTP.new(target_uri.host, target_uri.port, proxy_uri.host, proxy_uri.port)
        http.use_ssl = true
        http.ca_file = "\(certPath)"

        response = http.get(target_uri.request_uri)
        puts response.code
        puts response.body
        """
    }

    private static func rubyHTTPSnippet(port: Int, certPath: String) -> String {
        let certPath = escapeForStringLiteral(certPath, language: .ruby)
        return """
        require "http"

        response = HTTP.via("127.0.0.1", \(port))
          .headers({})
          .get("https://httpbin.org/get", ssl_context: { ca_file: "\(certPath)" })

        puts response.code
        puts response.to_s
        """
    }

    private static func rubyFaradaySnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .ruby)
        let certPath = escapeForStringLiteral(certPath, language: .ruby)
        return """
        require "faraday"

        connection = Faraday.new(
          url: "https://httpbin.org",
          proxy: "\(proxyURL)",
          ssl: { ca_file: "\(certPath)" }
        )

        response = connection.get("/get")
        puts response.status
        puts response.body
        """
    }

    private static func goNetHTTPSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .go)
        let certPath = escapeForStringLiteral(certPath, language: .go)
        return """
        package main

        import (
            "crypto/tls"
            "crypto/x509"
            "fmt"
            "net/http"
            "net/url"
            "os"
        )

        func main() {
            proxyURL, _ := url.Parse("\(proxyURL)")
            certPEM, _ := os.ReadFile("\(certPath)")
            pool := x509.NewCertPool()
            pool.AppendCertsFromPEM(certPEM)

            client := &http.Client{
                Transport: &http.Transport{
                    Proxy: http.ProxyURL(proxyURL),
                    TLSClientConfig: &tls.Config{
                        RootCAs: pool,
                    },
                },
            }

            response, _ := client.Get("https://httpbin.org/get")
            defer response.Body.Close()
            fmt.Println(response.Status)
        }
        """
    }

    private static func goRestySnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .go)
        let certPath = escapeForStringLiteral(certPath, language: .go)
        return """
        package main

        import (
            "fmt"

            "github.com/go-resty/resty/v2"
        )

        func main() {
            client := resty.New().
                SetProxy("\(proxyURL)").
                SetRootCertificate("\(certPath)")

            response, _ := client.R().Get("https://httpbin.org/get")
            fmt.Println(response.Status())
            fmt.Println(response.String())
        }
        """
    }

    private static func rustReqwestSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForStringLiteral(proxyURL, language: .rust)
        let certPath = escapeForStringLiteral(certPath, language: .rust)
        return """
        use reqwest::{Certificate, Client, Proxy};
        use std::fs;

        #[tokio::main]
        async fn main() -> Result<(), Box<dyn std::error::Error>> {
            let cert = Certificate::from_pem(&fs::read("\(certPath)")?)?;
            let client = Client::builder()
                .proxy(Proxy::all("\(proxyURL)")?)
                .add_root_certificate(cert)
                .build()?;

            let response = client.get("https://httpbin.org/get").send().await?;
            println!("{}", response.status());
            println!("{}", response.text().await?);
            Ok(())
        }
        """
    }

    private static func javaKeytoolSnippet(certPath: String) -> String {
        let certPath = escapeForShell(certPath)
        return """
        # Import the Rockxy root CA into the active JVM's cacerts keystore.
        # This changes trust for the selected JDK, so prefer a dedicated
        # development JVM or a copied cacerts file if you do not want to mutate
        # a shared installation.
        # Requires the default cacerts password "changeit" unless it was changed.
        keystore="$( [ -n "$JAVA_HOME" ] && printf "%s" "$JAVA_HOME" || /usr/libexec/java_home )/lib/security/cacerts"

        keytool -importcert \\
          -noprompt \\
          -alias rockxy-ca \\
          -file \(certPath) \\
          -keystore "$keystore" \\
          -storepass changeit

        # Then run your Java test, app, or CLI request normally; it will
        # hit Rockxy once you point HTTP traffic at 127.0.0.1 on Rockxy's port.
        """
    }

    private static func javaHttpClientSnippet(port: Int, certPath: String) -> String {
        let certPath = escapeForStringLiteral(certPath, language: .java)
        return """
        import java.net.InetSocketAddress;
        import java.net.ProxySelector;
        import java.net.URI;
        import java.net.http.HttpClient;
        import java.net.http.HttpRequest;
        import java.net.http.HttpResponse;

        public class RockxyVerify {
            public static void main(String[] args) throws Exception {
                // Assumes the Rockxy root CA has been imported into the active JVM cacerts
                // keystore (see the keytool snippet).
                // Certificate reference: \(certPath)
                HttpClient client = HttpClient.newBuilder()
                    .proxy(ProxySelector.of(new InetSocketAddress("127.0.0.1", \(port))))
                    .build();

                HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create("https://httpbin.org/get"))
                    .GET()
                    .build();

                HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                System.out.println(response.statusCode());
                System.out.println(response.body());
            }
        }
        """
    }

    private static func firefoxConfigSnippet(port: Int, certPath: String) -> String {
        let shellCertPath = escapeForShell(certPath)
        return """
        # 1. Firefox > Settings > Network Settings > Manual proxy configuration
        #    HTTP Proxy:  127.0.0.1    Port: \(port)
        #    [x] Also use this proxy for HTTPS
        #
        # 2. Firefox > Settings > Privacy & Security > Certificates > View Certificates
        #    Authorities > Import > select the file below
        #    [x] Trust this CA to identify websites
        #       \(certPath)
        #
        # 3. Verify the proxy works via cURL first:
        curl --proxy http://127.0.0.1:\(port) \\
          --cacert \(shellCertPath) \\
          "https://httpbin.org/get"
        #
        # 4. Open https://httpbin.org/get in Firefox and confirm Rockxy captured it.
        """
    }

    private static func postmanConfigSnippet(port: Int, certPath: String) -> String {
        let shellCertPath = escapeForShell(certPath)
        return """
        # 1. Postman > Settings > Proxy
        #    [x] Add a custom proxy configuration
        #    Proxy Type: HTTP + HTTPS
        #    Proxy Server: 127.0.0.1    Port: \(port)
        #
        # 2. Postman > Settings > Certificates > CA Certificates
        #    PEM file:
        #       \(certPath)
        #    (As a temporary debugging fallback only, you can turn off
        #     "SSL certificate verification" while confirming capture.)
        #
        # 3. Verify the proxy+cert work via cURL first:
        curl --proxy http://127.0.0.1:\(port) \\
          --cacert \(shellCertPath) \\
          "https://httpbin.org/get"
        #
        # 4. Send GET https://httpbin.org/get from Postman and confirm Rockxy captured it.
        """
    }

    private static func insomniaConfigSnippet(port: Int, certPath: String) -> String {
        let shellCertPath = escapeForShell(certPath)
        return """
        # 1. Insomnia > Preferences > Proxy
        #    [x] Enable proxy
        #    HTTP Proxy:  127.0.0.1:\(port)
        #    HTTPS Proxy: 127.0.0.1:\(port)
        #
        # 2. Insomnia > Preferences > General
        #    [ ] Validate SSL Certificates  (temporary debugging fallback only)
        #
        #    Trusted CA PEM:
        #       \(certPath)
        #
        # 3. Verify the proxy+cert work via cURL first:
        curl --proxy http://127.0.0.1:\(port) \\
          --cacert \(shellCertPath) \\
          "https://httpbin.org/get"
        #
        # 4. Send GET https://httpbin.org/get from Insomnia and confirm Rockxy captured it.
        """
    }

    private static func pawConfigSnippet(port: Int, certPath: String) -> String {
        let shellCertPath = escapeForShell(certPath)
        return """
        # Paw follows the macOS system proxy, so point the system proxy at Rockxy first.
        #
        # 1. macOS > System Settings > Network > <active interface> > Details > Proxies
        #    Web Proxy (HTTP):    127.0.0.1 : \(port)
        #    Secure Web Proxy:    127.0.0.1 : \(port)
        #
        # 2. Trust the Rockxy root CA in the macOS login/System keychain:
        #       \(certPath)
        #
        # 3. Verify the proxy+cert work via cURL first:
        curl --proxy http://127.0.0.1:\(port) \\
          --cacert \(shellCertPath) \\
          "https://httpbin.org/get"
        #
        # 4. Send GET https://httpbin.org/get from Paw and confirm Rockxy captured it.
        """
    }

    private static func dockerRunSnippet(port: Int, certPath: String) -> String {
        let certPath = escapeForShell(certPath)
        return """
        # Send one HTTPS request from a throwaway container through Rockxy.
        # Inside the container, the Mac is reachable at host.docker.internal.
        docker run --rm \\
          -e HTTP_PROXY=http://host.docker.internal:\(port) \\
          -e HTTPS_PROXY=http://host.docker.internal:\(port) \\
          -v \(certPath):/etc/ssl/certs/rockxy.pem:ro \\
          curlimages/curl:latest \\
          --cacert /etc/ssl/certs/rockxy.pem \\
          https://httpbin.org/get
        """
    }

    private static func electronCommandSnippet(port: Int, certPath: String) -> String {
        let certPath = escapeForShell(certPath)
        return """
        # Launch the Electron app with Chromium's proxy CLI flag.
        # Use NODE_EXTRA_CA_CERTS so Node code inside the app trusts the Rockxy CA.
        NODE_EXTRA_CA_CERTS=\(certPath) \\
          ./YourElectronApp --proxy-server=http://127.0.0.1:\(port)

        # If the binary lives inside the .app bundle:
        NODE_EXTRA_CA_CERTS=\(certPath) \\
          /Applications/YourApp.app/Contents/MacOS/YourApp \\
          --proxy-server=http://127.0.0.1:\(port)
        """
    }

    private static func electronSessionSnippet(port: Int, certPath: String) -> String {
        let certPath = escapeForShell(certPath)
        return """
        # Export NODE_EXTRA_CA_CERTS before Electron starts.
        NODE_EXTRA_CA_CERTS=\(certPath) npx electron .

        // main.ts — run inside the Electron main process.
        import { app, session } from "electron";

        app.whenReady().then(async () => {
          await session.defaultSession.setProxy({
            proxyRules: "http=127.0.0.1:\(port);https=127.0.0.1:\(port)",
          });

          // ... create your BrowserWindow after setProxy resolves.
        });
        """
    }

    private static func nextJSRouteHandlerSnippet(proxyURL: String, certPath: String) -> String {
        let proxyURL = escapeForShell(proxyURL)
        let certPath = escapeForShell(certPath)
        return """
        // app/api/rockxy-check/route.ts — App Router handler.
        // Start the dev server with:
        //   NODE_USE_ENV_PROXY=1 \\
        //   NODE_EXTRA_CA_CERTS=\(certPath) \\
        //   HTTP_PROXY=\(proxyURL) HTTPS_PROXY=\(proxyURL) next dev
        // so the Node.js fetch inside the handler trusts the Rockxy CA
        // and routes through the proxy.

        export const dynamic = "force-dynamic";

        export async function GET() {
          const response = await fetch("https://httpbin.org/get", { cache: "no-store" });
          const body = await response.json();
          return Response.json(body);
        }
        """
    }

    private static func validationSpec(
        for targetID: SetupTarget.ID,
        runtimeName: String,
        preferredSnippetID: SetupSnippetID? = nil
    )
        -> SetupValidationSpec
    {
        SetupValidationSpec(
            method: "GET",
            host: "httpbin.org",
            path: validationPath(for: targetID),
            instruction: String(
                localized: """
                Run the selected \(runtimeName) validation step and wait for Rockxy to capture \
                GET \(validationURL(for: targetID)). This confirms a matching probe reached Rockxy, \
                but it does not attribute the request to a specific app or process.
                """
            ),
            preferredSnippetID: preferredSnippetID
        )
    }

    private static func validationURL(for targetID: SetupTarget.ID) -> String {
        "https://httpbin.org\(validationPath(for: targetID))"
    }

    private static func validationPath(for targetID: SetupTarget.ID) -> String {
        "/anything/rockxy/\(targetID.rawValue)"
    }

    private static func escapeForShell(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func escapeForStringLiteral(_ value: String, language: StringLiteralLanguage) -> String {
        let escaped = value.unicodeScalars.reduce(into: "") { result, scalar in
            switch scalar {
            case "\\":
                result += "\\\\"
            case "\"":
                result += "\\\""
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                result.append(String(scalar))
            }
        }

        switch language {
        case .python,
             .javaScript,
             .ruby,
             .go,
             .rust,
             .java,
             .dart:
            return escaped
        }
    }

    private static func snippetStepTitle(for targetID: SetupTarget.ID) -> String {
        switch targetID {
        case .curl:
            String(localized: "cURL command")
        case .javaVMs:
            String(localized: "Java setup")
        case .firefox,
             .postman,
             .insomnia,
             .paw:
            String(localized: "Client configuration")
        case .docker:
            String(localized: "Container command")
        case .electronJS:
            String(localized: "Electron configuration")
        case .nextJS:
            String(localized: "Next.js handler")
        case .flutter:
            String(localized: "Flutter client")
        case .reactNative:
            String(localized: "React Native setup")
        default:
            String(localized: "Runtime snippet")
        }
    }

    private static func snippetStepDescription(for targetID: SetupTarget.ID) -> String {
        switch targetID {
        case .curl:
            String(localized: "Choose the command or environment example that matches how you run cURL.")
        case .nodeJS:
            String(localized: "Choose the Node.js library that matches your current runtime code path.")
        case .ruby:
            String(localized: "Choose the Ruby client that matches your current code path and copy the snippet.")
        case .golang:
            String(localized: "Choose the Go HTTP client that matches your runtime and copy the snippet.")
        case .rust:
            String(localized: "Use the reqwest snippet to point Rust traffic at Rockxy and trust the root certificate.")
        case .javaVMs:
            String(localized: "Import the Rockxy CA with keytool, then run the HttpClient sample to confirm capture.")
        case .firefox:
            String(
                localized: "Paste the proxy values into Firefox's Network Settings and import the CA into its own certificate store."
            )
        case .postman:
            String(localized: "Paste the proxy values into Postman's settings and trust the exported PEM.")
        case .insomnia:
            String(localized: "Enable Insomnia's proxy toggle, paste the values, and trust the exported PEM.")
        case .paw:
            String(localized: "Point the macOS system proxy at Rockxy — Paw follows the system proxy automatically.")
        case .docker:
            String(
                localized: "Run one throwaway container to confirm host.docker.internal + the mounted CA work end-to-end."
            )
        case .electronJS:
            String(
                localized: "Pick the CLI flag variant or the main-process session.setProxy call, depending on how you launch the app."
            )
        case .nextJS:
            String(localized: "Add the route handler and start next dev with NODE_EXTRA_CA_CERTS + HTTPS_PROXY set.")
        case .flutter:
            String(
                localized: """
                Choose the Flutter client path you use, then keep the iOS or Android device setup aligned with that runtime.
                """
            )
        case .reactNative:
            String(
                localized: """
                Choose the React Native probe, Android debug trust XML, or Metro checklist that matches the target runtime.
                """
            )
        default:
            String(localized: "Choose the snippet that matches your current runtime or library and copy it.")
        }
    }
}
