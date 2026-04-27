import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
@testable import Rockxy
import Testing

@Suite("Developer Setup Runtime Integration", .serialized)
struct DeveloperSetupRuntimeIntegrationTests {
    @Test("Python runtime traffic is captured end-to-end")
    func pythonRuntimeTrafficIsCaptured() async throws {
        try await assertRuntimeProbe(
            runtimeName: "Python",
            requestPath: "/developer-setup/python",
            buildInvocation: { proxyPort, upstreamPort, workingDirectory in
                let scriptURL = workingDirectory.appendingPathComponent("probe.py")
                try """
                import urllib.request

                proxy_handler = urllib.request.ProxyHandler({
                    "http": "http://127.0.0.1:\(proxyPort)",
                })
                opener = urllib.request.build_opener(proxy_handler)
                with opener.open("http://127.0.0.1:\(upstreamPort)/developer-setup/python", timeout=10) as response:
                    print(response.status)
                """.write(to: scriptURL, atomically: true, encoding: .utf8)

                return ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                    arguments: [scriptURL.path],
                    timeout: .seconds(45)
                )
            }
        )
    }

    @Test("Node.js runtime traffic is captured end-to-end")
    func nodeRuntimeTrafficIsCaptured() async throws {
        try await assertRuntimeProbe(
            runtimeName: "Node.js",
            requestPath: "/developer-setup/node",
            buildInvocation: { proxyPort, upstreamPort, workingDirectory in
                let scriptURL = workingDirectory.appendingPathComponent("probe.js")
                try """
                const http = require("node:http");

                const request = http.request({
                  host: "127.0.0.1",
                  port: \(proxyPort),
                  method: "GET",
                  path: "http://127.0.0.1:\(upstreamPort)/developer-setup/node",
                  headers: {
                    Host: "127.0.0.1:\(upstreamPort)",
                  },
                }, (response) => {
                  console.log(response.statusCode);
                  response.resume();
                  response.on("end", () => process.exit(0));
                });

                request.on("error", (error) => {
                  console.error(error);
                  process.exit(1);
                });

                request.end();
                """.write(to: scriptURL, atomically: true, encoding: .utf8)

                return ProcessInvocation(
                    executableURL: try runtimeExecutable(
                        name: "node",
                        additionalCandidates: ["/usr/local/bin/node", "/opt/homebrew/bin/node"],
                        searchNVM: true
                    ),
                    arguments: [scriptURL.path]
                )
            }
        )
    }

    @Test("Ruby runtime traffic is captured end-to-end")
    func rubyRuntimeTrafficIsCaptured() async throws {
        try await assertRuntimeProbe(
            runtimeName: "Ruby",
            requestPath: "/developer-setup/ruby",
            buildInvocation: { proxyPort, upstreamPort, workingDirectory in
                let scriptURL = workingDirectory.appendingPathComponent("probe.rb")
                try """
                require "uri"
                require "net/http"

                uri = URI("http://127.0.0.1:\(upstreamPort)/developer-setup/ruby")
                client = Net::HTTP::Proxy("127.0.0.1", \(proxyPort))

                response = client.start(uri.host, uri.port) do |http|
                  http.get(uri.request_uri)
                end

                puts response.code
                exit(response.code == "200" ? 0 : 1)
                """.write(to: scriptURL, atomically: true, encoding: .utf8)

                return ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/usr/bin/ruby"),
                    arguments: [scriptURL.path]
                )
            }
        )
    }

    @Test("Go runtime traffic is captured end-to-end")
    func goRuntimeTrafficIsCaptured() async throws {
        try await assertRuntimeProbe(
            runtimeName: "Go",
            requestPath: "/developer-setup/go",
            buildInvocation: { proxyPort, upstreamPort, workingDirectory in
                let sourceURL = workingDirectory.appendingPathComponent("probe.go")
                try """
                package main

                import (
                    "fmt"
                    "net/http"
                    "net/url"
                    "os"
                    "time"
                )

                func main() {
                    proxyURL, err := url.Parse("http://127.0.0.1:\(proxyPort)")
                    if err != nil {
                        panic(err)
                    }

                    client := &http.Client{
                        Timeout: 10 * time.Second,
                        Transport: &http.Transport{
                            Proxy: http.ProxyURL(proxyURL),
                        },
                    }

                    response, err := client.Get("http://127.0.0.1:\(upstreamPort)/developer-setup/go")
                    if err != nil {
                        panic(err)
                    }
                    defer response.Body.Close()

                    fmt.Println(response.StatusCode)
                    if response.StatusCode != http.StatusOK {
                        os.Exit(1)
                    }
                }
                """.write(to: sourceURL, atomically: true, encoding: .utf8)

                return ProcessInvocation(
                    executableURL: try runtimeExecutable(
                        name: "go",
                        additionalCandidates: ["/opt/homebrew/bin/go", "/usr/local/bin/go"]
                    ),
                    arguments: ["run", sourceURL.path]
                )
            }
        )
    }

    @Test("Rust runtime traffic is captured end-to-end")
    func rustRuntimeTrafficIsCaptured() async throws {
        try await assertRuntimeProbe(
            runtimeName: "Rust",
            requestPath: "/developer-setup/rust",
            buildInvocation: { proxyPort, upstreamPort, workingDirectory in
                let sourceURL = workingDirectory.appendingPathComponent("probe.rs")
                let binaryURL = workingDirectory.appendingPathComponent("probe-rust")
                try """
                use std::io::{Read, Write};
                use std::net::TcpStream;
                use std::process;
                use std::time::Duration;

                fn main() {
                    let mut stream = TcpStream::connect(("127.0.0.1", \(proxyPort))).expect("connect proxy");
                    stream.set_read_timeout(Some(Duration::from_secs(5))).expect("set read timeout");
                    let request = format!(
                        "GET http://127.0.0.1:\(upstreamPort)/developer-setup/rust HTTP/1.1\\r\\nHost: 127.0.0.1:\(upstreamPort)\\r\\nConnection: close\\r\\n\\r\\n"
                    );

                    stream.write_all(request.as_bytes()).expect("write request");

                    let mut buffer = [0_u8; 4096];
                    let count = stream.read(&mut buffer).expect("read response");
                    let response = String::from_utf8_lossy(&buffer[..count]);

                    if !response.starts_with("HTTP/1.1 200") && !response.starts_with("HTTP/1.0 200") {
                        eprintln!("{}", response);
                        process::exit(1);
                    }
                }
                """.write(to: sourceURL, atomically: true, encoding: .utf8)

                let rustc = try runtimeExecutable(
                    name: "rustc",
                    additionalCandidates: ["/opt/homebrew/bin/rustc", "/usr/local/bin/rustc"],
                    searchCargoHome: true
                )

                let compileResult = try await runProcess(
                    executableURL: rustc,
                    arguments: [sourceURL.path, "-o", binaryURL.path]
                )
                #expect(compileResult.terminationStatus == 0, "rustc failed: \(compileResult.stderr)")

                return ProcessInvocation(
                    executableURL: binaryURL,
                    arguments: []
                )
            }
        )
    }

    @Test("Java runtime traffic is captured end-to-end when a local JDK is installed")
    func javaRuntimeTrafficIsCaptured() async throws {
        guard
            let java = installedJavaTool(named: "java"),
            let javac = installedJavaTool(named: "javac")
        else {
            return
        }

        try await assertRuntimeProbe(
            runtimeName: "Java",
            requestPath: "/developer-setup/java",
            buildInvocation: { proxyPort, upstreamPort, workingDirectory in
                let sourceURL = workingDirectory.appendingPathComponent("DeveloperSetupProbeMain.java")
                try """
                import java.net.InetSocketAddress;
                import java.net.ProxySelector;
                import java.net.URI;
                import java.net.http.HttpClient;
                import java.net.http.HttpRequest;
                import java.net.http.HttpResponse;
                import java.time.Duration;

                public class DeveloperSetupProbeMain {
                    public static void main(String[] args) throws Exception {
                        HttpClient client = HttpClient.newBuilder()
                            .connectTimeout(Duration.ofSeconds(10))
                            .proxy(ProxySelector.of(new InetSocketAddress("127.0.0.1", \(proxyPort))))
                            .build();

                        HttpRequest request = HttpRequest.newBuilder()
                            .uri(URI.create("http://127.0.0.1:\(upstreamPort)/developer-setup/java"))
                            .timeout(Duration.ofSeconds(10))
                            .GET()
                            .build();

                        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
                        System.out.println(response.statusCode());
                        if (response.statusCode() != 200) {
                            System.exit(1);
                        }
                    }
                }
                """.write(to: sourceURL, atomically: true, encoding: .utf8)

                let compileResult = try await runProcess(
                    executableURL: javac,
                    arguments: [sourceURL.path],
                    workingDirectory: workingDirectory
                )
                #expect(compileResult.terminationStatus == 0, "javac failed: \(compileResult.stderr)")

                return ProcessInvocation(
                    executableURL: java,
                    arguments: ["-cp", workingDirectory.path, "DeveloperSetupProbeMain"]
                )
            }
        )
    }

    @Test("Firefox browser traffic is captured end-to-end when Firefox is installed")
    func firefoxTrafficIsCaptured() async throws {
        guard let firefox = installedAppExecutable(
            appPath: "/Applications/Firefox.app",
            executableRelativePath: "Contents/MacOS/firefox"
        ) else {
            return
        }

        try await assertRuntimeProbe(
            runtimeName: "Firefox",
            requestPath: "/developer-setup/firefox",
            captureTimeout: .seconds(30),
            buildInvocation: { proxyPort, upstreamPort, workingDirectory in
                let profileDirectory = workingDirectory.appendingPathComponent("FirefoxProfile", isDirectory: true)
                try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
                let userJS = profileDirectory.appendingPathComponent("user.js")
                try """
                user_pref("network.proxy.type", 1);
                user_pref("network.proxy.http", "127.0.0.1");
                user_pref("network.proxy.http_port", \(proxyPort));
                user_pref("network.proxy.ssl", "127.0.0.1");
                user_pref("network.proxy.ssl_port", \(proxyPort));
                user_pref("network.proxy.no_proxies_on", "");
                user_pref("network.proxy.allow_hijacking_localhost", true);
                user_pref("network.captive-portal-service.enabled", false);
                user_pref("app.update.auto", false);
                user_pref("app.update.enabled", false);
                user_pref("browser.shell.checkDefaultBrowser", false);
                user_pref("browser.bookmarks.restore_default_bookmarks", false);
                user_pref("datareporting.policy.dataSubmissionEnabled", false);
                user_pref("toolkit.telemetry.enabled", false);
                """.write(to: userJS, atomically: true, encoding: .utf8)

                let scriptURL = workingDirectory.appendingPathComponent("firefox-probe.sh")
                try """
                #!/bin/zsh
                set -eu

                profile_dir="$1"
                firefox_bin="$2"
                target_url="$3"

                "$firefox_bin" -headless -no-remote -profile "$profile_dir" "$target_url" >/dev/null 2>&1 &
                firefox_pid=$!
                sleep 15
                kill "$firefox_pid" >/dev/null 2>&1 || true
                wait "$firefox_pid" >/dev/null 2>&1 || true
                """.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: scriptURL.path
                )

                return ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: [
                        scriptURL.path,
                        profileDirectory.path,
                        firefox.path,
                        "http://127.0.0.1:\(upstreamPort)/developer-setup/firefox",
                    ],
                    timeout: .seconds(45)
                )
            }
        )
    }

    @Test("cURL traffic is captured end-to-end")
    func curlTrafficIsCaptured() async throws {
        try await assertRuntimeProbe(
            runtimeName: "cURL",
            requestPath: "/developer-setup/curl",
            buildInvocation: { proxyPort, upstreamPort, _ in
                ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/usr/bin/curl"),
                    arguments: [
                        "--proxy", "http://127.0.0.1:\(proxyPort)",
                        "--silent",
                        "--show-error",
                        "--fail",
                        "http://127.0.0.1:\(upstreamPort)/developer-setup/curl",
                    ]
                )
            }
        )
    }

    @Test("Docker container traffic is captured end-to-end when Docker Desktop is running")
    func dockerTrafficIsCaptured() async throws {
        let docker = try? runtimeExecutable(
            name: "docker",
            additionalCandidates: ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"]
        )
        guard
            let docker,
            let dockerHostAddress = dockerReachableHostIPv4Address()
        else {
            return
        }

        let daemonStatus = try await runProcess(
            executableURL: docker,
            arguments: ["info", "--format", "{{.ServerVersion}}"],
            timeout: .seconds(10)
        )
        guard daemonStatus.terminationStatus == 0 else {
            return
        }

        try await assertRuntimeProbe(
            runtimeName: "Docker",
            requestPath: "/developer-setup/docker",
            proxyListenAddress: "0.0.0.0",
            upstreamListenAddress: "0.0.0.0",
            expectedCapturedHost: dockerHostAddress,
            buildInvocation: { proxyPort, upstreamPort, _ in
                ProcessInvocation(
                    executableURL: docker,
                    arguments: [
                        "run",
                        "--rm",
                        "curlimages/curl@sha256:9a6f6a17667960e077f1b153009aaf18ac99a622221084e1938a45a06fff057a",
                        "--proxy", "http://\(dockerHostAddress):\(proxyPort)",
                        "--noproxy", "",
                        "--silent",
                        "--show-error",
                        "--fail",
                        "http://\(dockerHostAddress):\(upstreamPort)/developer-setup/docker",
                    ],
                    environment: dockerProcessEnvironment(
                        additionalPathEntries: [
                            "/Applications/Docker.app/Contents/Resources/bin",
                            docker.deletingLastPathComponent().path,
                        ]
                    ),
                    timeout: .seconds(120)
                )
            }
        )
    }

    @Test("Next.js route handler traffic is captured end-to-end when Node.js tooling is installed")
    func nextJSTrafficIsCaptured() async throws {
        guard
            let node = try? runtimeExecutable(
                name: "node",
                additionalCandidates: ["/usr/local/bin/node", "/opt/homebrew/bin/node"],
                searchNVM: true
            ),
            let npm = try? runtimeExecutable(
                name: "npm",
                additionalCandidates: ["/usr/local/bin/npm", "/opt/homebrew/bin/npm"],
                searchNVM: true
            ),
            let npx = try? runtimeExecutable(
                name: "npx",
                additionalCandidates: ["/usr/local/bin/npx", "/opt/homebrew/bin/npx"],
                searchNVM: true
            ),
            let nextHostAddress = dockerReachableHostIPv4Address()
        else {
            return
        }

        try await assertRuntimeProbe(
            runtimeName: "Next.js",
            requestPath: "/developer-setup/nextjs",
            upstreamListenAddress: "0.0.0.0",
            expectedCapturedHost: nextHostAddress,
            expectedCapturedMethod: "CONNECT",
            allowAnyCapturedPath: true,
            captureTimeout: .seconds(30),
            buildInvocation: { proxyPort, upstreamPort, workingDirectory in
                let appPort = try findFreePort()
                let packageJSON = workingDirectory.appendingPathComponent("package.json")
                let routeDirectory = workingDirectory.appendingPathComponent("app/api/rockxy-check", isDirectory: true)
                try FileManager.default.createDirectory(at: routeDirectory, withIntermediateDirectories: true)

                try """
                {
                  "name": "rockxy-next-probe",
                  "private": true
                }
                """.write(to: packageJSON, atomically: true, encoding: .utf8)

                let routeURL = routeDirectory.appendingPathComponent("route.ts")
                try """
                export const dynamic = "force-dynamic";

                export async function GET() {
                  const response = await fetch("http://\(nextHostAddress):\(upstreamPort)/developer-setup/nextjs", {
                    cache: "no-store",
                  });
                  const body = await response.text();
                  return new Response(body, { status: 200 });
                }
                """.write(to: routeURL, atomically: true, encoding: .utf8)

                let scriptURL = workingDirectory.appendingPathComponent("nextjs-probe.sh")
                try """
                #!/bin/zsh
                set -eu

                project_dir="$1"
                npm_bin="$2"
                npx_bin="$3"
                proxy_url="$4"
                app_port="$5"

                cd "$project_dir"
                "$npm_bin" install --package-lock-only --silent next@16.2.4 react@19.2.5 react-dom@19.2.5 >/dev/null
                "$npm_bin" ci --silent >/dev/null

                NODE_USE_ENV_PROXY=1 \\
                HTTP_PROXY="$proxy_url" \\
                HTTPS_PROXY="$proxy_url" \\
                "$npx_bin" next dev --hostname 127.0.0.1 --port "$app_port" >"$project_dir/next-dev.log" 2>&1 &
                next_pid=$!

                cleanup() {
                  kill "$next_pid" >/dev/null 2>&1 || true
                  wait "$next_pid" >/dev/null 2>&1 || true
                }
                trap cleanup EXIT

                for _ in $(seq 1 60); do
                  if /usr/bin/curl --silent --show-error --fail "http://127.0.0.1:$app_port/api/rockxy-check" >/dev/null; then
                    exit 0
                  fi
                  sleep 1
                done

                cat "$project_dir/next-dev.log" >&2
                exit 1
                """.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: scriptURL.path
                )

                return ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: [
                        scriptURL.path,
                        workingDirectory.path,
                        npm.path,
                        npx.path,
                        "http://127.0.0.1:\(proxyPort)",
                        "\(appPort)",
                    ],
                    environment: dockerProcessEnvironment(
                        additionalPathEntries: [
                            node.deletingLastPathComponent().path,
                            npm.deletingLastPathComponent().path,
                            npx.deletingLastPathComponent().path,
                        ]
                    ),
                    timeout: .seconds(240)
                )
            }
        )
    }

    // MARK: Private

    private func assertRuntimeProbe(
        runtimeName: String,
        requestPath: String,
        proxyListenAddress: String = "127.0.0.1",
        upstreamListenAddress: String = "127.0.0.1",
        expectedCapturedHost: String = "127.0.0.1",
        expectedCapturedMethod: String = "GET",
        expectedCapturedPath: String? = nil,
        allowAnyCapturedPath: Bool = false,
        captureTimeout: Duration = .seconds(10),
        buildInvocation: @escaping @Sendable (_ proxyPort: Int, _ upstreamPort: Int, _ workingDirectory: URL) async throws -> ProcessInvocation
    ) async throws {
        let probeLock = try RuntimeProbeFileLock.acquire()
        defer { probeLock.release() }

        let proxyPort = try findFreePort()
        let upstreamPort = try findFreePort()
        let transactionRecorder = TransactionRecorder()
        let upstreamRecorder = UpstreamRequestRecorder()
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeveloperSetupRuntime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let upstreamServer = try await LocalHTTPProbeServer(
            host: upstreamListenAddress,
            port: upstreamPort,
            requestRecorder: upstreamRecorder
        ).start()
        let proxyServer = ProxyServer(
            configuration: ProxyConfiguration(
                port: proxyPort,
                listenAddress: proxyListenAddress,
                listenIPv6: false
            ),
            onTransactionComplete: { transaction in
                transactionRecorder.record(transaction)
            }
        )

        try await proxyServer.start()

        do {
            let invocation = try await buildInvocation(proxyPort, upstreamPort, workingDirectory)
            let result = try await runProcess(
                executableURL: invocation.executableURL,
                arguments: invocation.arguments,
                workingDirectory: invocation.workingDirectory ?? workingDirectory,
                environment: invocation.environment,
                timeout: invocation.timeout
            )

            #expect(
                result.terminationStatus == 0,
                "\(runtimeName) probe failed.\nstdout:\n\(result.stdout)\nstderr:\n\(result.stderr)"
            )

            let capturedTransaction = try await transactionRecorder.waitForTransaction(
                host: expectedCapturedHost,
                method: expectedCapturedMethod,
                path: allowAnyCapturedPath ? nil : (expectedCapturedPath ?? requestPath),
                timeout: captureTimeout
            )
            let upstreamRequest = try await upstreamRecorder.waitForRequest(
                path: requestPath,
                timeout: captureTimeout
            )

            #expect(capturedTransaction.request.method == expectedCapturedMethod)
            #expect(capturedTransaction.request.host == expectedCapturedHost)
            if !allowAnyCapturedPath {
                #expect(capturedTransaction.request.path == (expectedCapturedPath ?? requestPath))
            }
            #expect(upstreamRequest.method == "GET")
            #expect(upstreamRequest.uri == requestPath)
        } catch {
            await proxyServer.stop()
            await upstreamServer.stop()
            throw error
        }

        await proxyServer.stop()
        await upstreamServer.stop()
    }

    private func runtimeExecutable(
        name: String,
        additionalCandidates: [String] = [],
        searchCargoHome: Bool = false,
        searchNVM: Bool = false
    ) throws -> URL {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        var candidates = additionalCandidates

        let standardCandidates = [
            "/usr/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
        ]
        candidates.append(contentsOf: standardCandidates)

        if searchCargoHome {
            candidates.append(homeDirectory.appendingPathComponent(".cargo/bin/\(name)").path)
        }

        if searchNVM {
            let nvmVersionsDirectory = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
            if let versionDirectories = try? fileManager.contentsOfDirectory(
                at: nvmVersionsDirectory,
                includingPropertiesForKeys: nil
            ) {
                let discovered = versionDirectories
                    .map { $0.appendingPathComponent("bin/\(name)").path }
                    .sorted()
                candidates.append(contentsOf: discovered.reversed())
            }
        }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        throw RuntimeProbeError.executableNotFound(name)
    }

    private func installedJavaTool(named name: String) -> URL? {
        let javaHomeProcess = Process()
        let outputPipe = Pipe()
        javaHomeProcess.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        javaHomeProcess.standardOutput = outputPipe
        javaHomeProcess.standardError = Pipe()

        guard (try? javaHomeProcess.run()) != nil else {
            return nil
        }

        javaHomeProcess.waitUntilExit()
        guard javaHomeProcess.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let javaHomePath = String(bytes: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !javaHomePath.isEmpty
        else {
            return nil
        }

        let toolURL = URL(fileURLWithPath: javaHomePath).appendingPathComponent("bin/\(name)")
        return FileManager.default.isExecutableFile(atPath: toolURL.path) ? toolURL : nil
    }

    private func installedAppExecutable(appPath: String, executableRelativePath: String) -> URL? {
        let executable = URL(fileURLWithPath: appPath).appendingPathComponent(executableRelativePath)
        return FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil
    }

    private func dockerReachableHostIPv4Address() -> String? {
        var interfacesPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacesPointer) == 0, let firstInterface = interfacesPointer else {
            return nil
        }
        defer { freeifaddrs(interfacesPointer) }

        var candidates: [(interface: String, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }

            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard
                isUp,
                !isLoopback,
                let address = interface.pointee.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }

            candidates.append((
                interface: String(cString: interface.pointee.ifa_name),
                address: String(cString: host)
            ))
        }

        let preferredInterfaces = ["en0", "en1", "bridge100"]
        for preferred in preferredInterfaces {
            if let match = candidates.first(where: { $0.interface == preferred }) {
                return match.address
            }
        }

        return candidates.first?.address
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration = .seconds(20)
    ) async throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = environment
        }
        try process.run()

        let stdoutReader = Task {
            var data = Data()
            for try await byte in stdoutPipe.fileHandleForReading.bytes {
                data.append(byte)
            }
            return data
        }

        let stderrReader = Task {
            var data = Data()
            for try await byte in stderrPipe.fileHandleForReading.bytes {
                data.append(byte)
            }
            return data
        }

        let deadline = ContinuousClock().now + timeout
        while process.isRunning {
            if ContinuousClock().now >= deadline {
                process.terminate()
                process.waitUntilExit()
                stdoutReader.cancel()
                stderrReader.cancel()
                throw RuntimeProbeError.processTimedOut(executableURL.lastPathComponent)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        let stdoutData = (try? await stdoutReader.value) ?? Data()
        let stderrData = (try? await stderrReader.value) ?? Data()
        let stdout = String(bytes: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(bytes: stderrData, encoding: .utf8) ?? ""
        return ProcessResult(
            terminationStatus: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

private func dockerProcessEnvironment(additionalPathEntries: [String]) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    var pathEntries = environment["PATH"]?
        .split(separator: ":")
        .map(String.init) ?? []

    for entry in additionalPathEntries.reversed() where !pathEntries.contains(entry) {
        pathEntries.insert(entry, at: 0)
    }

    environment["PATH"] = pathEntries.joined(separator: ":")
    return environment
}

// MARK: - ProcessInvocation

private struct ProcessInvocation {
    let executableURL: URL
    let arguments: [String]
    var workingDirectory: URL?
    var environment: [String: String]?
    var timeout: Duration = .seconds(20)
}

// MARK: - ProcessResult

private struct ProcessResult {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
}

// MARK: - TransactionRecorder

private final class TransactionRecorder: @unchecked Sendable {
    func record(_ transaction: HTTPTransaction) {
        lock.lock()
        transactions.append(transaction)
        lock.unlock()
    }

    func waitForTransaction(
        host: String,
        method: String,
        path: String?,
        timeout: Duration = .seconds(10)
    ) async throws -> HTTPTransaction {
        let deadline = ContinuousClock().now + timeout

        while ContinuousClock().now < deadline {
            if let transaction = matchingTransaction(host: host, method: method, path: path) {
                return transaction
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        throw RuntimeProbeError.captureTimedOut(path ?? host)
    }

    private func matchingTransaction(host: String, method: String, path: String?) -> HTTPTransaction? {
        lock.lock()
        defer { lock.unlock() }
        return transactions.first(where: { transaction in
            transaction.request.host == host &&
                transaction.request.method == method &&
                (path == nil || transaction.request.path == path)
        })
    }

    private let lock = NSLock()
    private var transactions: [HTTPTransaction] = []
}

// MARK: - UpstreamRequestRecorder

private struct UpstreamRequest: Equatable {
    let method: String
    let uri: String
}

private final class UpstreamRequestRecorder: @unchecked Sendable {
    func record(method: String, uri: String) {
        lock.lock()
        requests.append(UpstreamRequest(method: method, uri: uri))
        lock.unlock()
    }

    func waitForRequest(path: String, timeout: Duration = .seconds(10)) async throws -> UpstreamRequest {
        let deadline = ContinuousClock().now + timeout

        while ContinuousClock().now < deadline {
            if let request = matchingRequest(path: path) {
                return request
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        throw RuntimeProbeError.upstreamTimedOut(path)
    }

    private func matchingRequest(path: String) -> UpstreamRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.first(where: { $0.uri == path })
    }

    private let lock = NSLock()
    private var requests: [UpstreamRequest] = []
}

// MARK: - LocalHTTPProbeServer

private final class LocalHTTPProbeServer: @unchecked Sendable {
    init(host: String, port: Int, requestRecorder: UpstreamRequestRecorder) {
        self.host = host
        self.port = port
        self.requestRecorder = requestRecorder
    }

    func start() async throws -> LocalHTTPProbeServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 32)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(ProbeRequestHandler(requestRecorder: self.requestRecorder))
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        do {
            channel = try await bootstrap.bind(host: host, port: port).get()
            return self
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            throw error
        }
    }

    func stop() async {
        if let channel {
            try? await channel.close().get()
            self.channel = nil
        }

        if let eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
            self.eventLoopGroup = nil
        }
    }

    private let host: String
    private let port: Int
    private let requestRecorder: UpstreamRequestRecorder
    private var channel: Channel?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
}

// MARK: - ProbeRequestHandler

private final class ProbeRequestHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    init(requestRecorder: UpstreamRequestRecorder) {
        self.requestRecorder = requestRecorder
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            currentRequestHead = head
            requestRecorder.record(method: head.method.rawValue, uri: head.uri)
        case .body:
            break
        case .end:
            respond(context: context)
            currentRequestHead = nil
        }
    }

    private func respond(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: 2)
        buffer.writeString("ok")

        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "2")
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private let requestRecorder: UpstreamRequestRecorder
    private var currentRequestHead: HTTPRequestHead?
}

// MARK: - RuntimeProbeFileLock

private struct RuntimeProbeFileLock {
    static func acquire() throws -> RuntimeProbeFileLock {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-developer-setup-runtime.lock")
            .path

        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw RuntimeProbeError.fileLockFailed
        }

        while flock(fd, LOCK_EX) != 0 {
            if errno == EINTR {
                continue
            }
            close(fd)
            throw RuntimeProbeError.fileLockFailed
        }

        return RuntimeProbeFileLock(fd: fd)
    }

    func release() {
        flock(fd, LOCK_UN)
        close(fd)
    }

    private let fd: Int32
}

// MARK: - Helpers

private func findFreePort() throws -> Int {
    let listener = try TCPListener(port: 0, address: "127.0.0.1")
    let port = listener.boundPort
    listener.close()
    return port
}

private final class TCPListener {
    init(port: Int, address: String) throws {
        let socketFd = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw RuntimeProbeError.socketCreationFailed
        }

        var reuse: Int32 = 1
        setsockopt(socketFd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(address)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(socketFd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(socketFd)
            throw RuntimeProbeError.bindFailed
        }

        guard listen(socketFd, 1) == 0 else {
            Darwin.close(socketFd)
            throw RuntimeProbeError.listenFailed
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(socketFd, sockPtr, &boundLen)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(socketFd)
            throw RuntimeProbeError.getsocknameFailed
        }

        fd = socketFd
        boundPort = Int(in_port_t(bigEndian: boundAddr.sin_port))
    }

    let boundPort: Int

    func close() {
        Darwin.close(fd)
    }

    private let fd: Int32
}

// MARK: - RuntimeProbeError

private enum RuntimeProbeError: LocalizedError {
    case executableNotFound(String)
    case processTimedOut(String)
    case captureTimedOut(String)
    case upstreamTimedOut(String)
    case socketCreationFailed
    case bindFailed
    case listenFailed
    case getsocknameFailed
    case fileLockFailed

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(name):
            "Required runtime executable not found: \(name)"
        case let .processTimedOut(name):
            "Runtime process timed out: \(name)"
        case let .captureTimedOut(path):
            "Rockxy did not capture the expected runtime probe for \(path)"
        case let .upstreamTimedOut(path):
            "Upstream probe server did not observe the expected request for \(path)"
        case .socketCreationFailed:
            "Failed to create test listener socket"
        case .bindFailed:
            "Failed to bind test listener socket"
        case .listenFailed:
            "Failed to listen on test listener socket"
        case .getsocknameFailed:
            "Failed to resolve the bound test listener port"
        case .fileLockFailed:
            "Failed to acquire the cross-process runtime probe lock"
        }
    }
}
