import Foundation
@testable import Rockxy
import Testing

// MARK: - DeveloperSetupTrustBundleTests

/// Executes the prepared-terminal trust bundle block in real shells.
struct DeveloperSetupTrustBundleTests {
    @Test(
        "Combined trust bundle keeps existing anchors, appends the Rockxy root, and never nests",
        arguments: ["/bin/zsh", "/bin/bash"]
    )
    func combinedTrustBundleKeepsExistingAnchors(shellPath: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-trust-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let corporate = directory.appendingPathComponent("corporate.pem")
        let root = directory.appendingPathComponent("root.pem")
        let block = directory.appendingPathComponent("block.sh")
        try "CORPORATE-ANCHOR\n".write(to: corporate, atomically: true, encoding: .utf8)
        try "ROCKXY-ROOT\n".write(to: root, atomically: true, encoding: .utf8)
        try RockxySetupScriptBuilder.combinedTrustBundleLines.joined(separator: "\n")
            .write(to: block, atomically: true, encoding: .utf8)

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = [
            "-c",
            ". \"$BLOCK\"; . \"$BLOCK\"; printf '%s\\n%s\\n%s\\n' "
                + "\"$SSL_CERT_FILE\" \"$REQUESTS_CA_BUNDLE\" \"$ROCKXY_ORIGINAL_SSL_CERT_FILE\"; cat \"$SSL_CERT_FILE\"",
        ]
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "TMPDIR": directory.path + "/",
            "BLOCK": block.path,
            "ROCKXY_ROOT_CA_PATH": root.path,
            "SSL_CERT_FILE": corporate.path,
        ]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n").map(String.init)
        let bundlePath = directory.appendingPathComponent("rockxy-ca-bundle.pem").path

        #expect(process.terminationStatus == 0)
        #expect(lines.count >= 5)
        #expect(lines.first == bundlePath)
        #expect(lines.dropFirst().first == bundlePath)
        #expect(lines.dropFirst(2).first == corporate.path)
        #expect(Array(lines.dropFirst(3)) == ["CORPORATE-ANCHOR", "ROCKXY-ROOT"])
    }

    @Test(
        "Java terminals get a private truststore with the JDK anchors and the Rockxy root, once",
        .enabled(if: Self.javaHome != nil),
        arguments: ["/bin/zsh", "/bin/bash"]
    )
    func javaTrustStoreAddsRootWithoutStacking(shellPath: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-java-trust-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("root.pem")
        let script = directory.appendingPathComponent("setup.sh")
        try AndroidEmulatorProxyControllerTests.testCAPEM.write(to: root, atomically: true, encoding: .utf8)
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_090,
            certificatePath: root.path,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .javaVMs
        )
        try RockxySetupScriptBuilder.script(context: context).write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = [
            "-c",
            ". \"$SCRIPT\" >/dev/null; . \"$SCRIPT\" >/dev/null; printf '%s\\n' \"$JAVA_TOOL_OPTIONS\"; "
                + "\"$JAVA_HOME/bin/keytool\" -list -keystore \"$TMPDIR/rockxy-java-truststore.p12\" "
                + "-storetype PKCS12 -storepass changeit",
        ]
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "TMPDIR": directory.path + "/",
            "SCRIPT": script.path,
            "JAVA_HOME": Self.javaHome ?? "",
            "JAVA_TOOL_OPTIONS": "-Dfile.encoding=UTF-8",
        ]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let options = text.split(separator: "\n").first.map(String.init) ?? ""
        let storePath = directory.appendingPathComponent("rockxy-java-truststore.p12").path

        #expect(process.terminationStatus == 0)
        #expect(options.hasPrefix("-Dfile.encoding=UTF-8"))
        #expect(options.components(separatedBy: "-Djavax.net.ssl.trustStore=\(storePath)").count - 1 == 1)
        #expect(options.components(separatedBy: "-Dhttps.proxyPort=9090").count - 1 == 1)
        #expect(text.contains("rockxy-root"))
        // The JDK's own anchors stay trusted next to the Rockxy root.
        let entries = text.split(separator: "\n").filter { $0.contains("trustedCertEntry") }.count
        #expect(entries > 50)
    }

    @Test(
        "The macOS system Ruby trusts the Rockxy root through a RUBYOPT preload, added once",
        .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/ruby")),
        arguments: ["/bin/zsh", "/bin/bash"]
    )
    func systemRubyTrustsRootThroughPreload(shellPath: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-ruby-trust-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("root.pem")
        let script = directory.appendingPathComponent("setup.sh")
        try AndroidEmulatorProxyControllerTests.testCAPEM.write(to: root, atomically: true, encoding: .utf8)
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_090,
            certificatePath: root.path,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .ruby
        )
        try RockxySetupScriptBuilder.script(context: context).write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = [
            "-c",
            ". \"$SCRIPT\" >/dev/null; . \"$SCRIPT\" >/dev/null; printf '%s\\n' \"$RUBYOPT\"; /usr/bin/ruby -e "
                + "'c = OpenSSL::X509::Certificate.new(File.read(ENV[\"ROCKXY_ROOT_CA_PATH\"])); "
                + "puts OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE.verify(c)'",
        ]
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "TMPDIR": directory.path + "/",
            "SCRIPT": script.path,
            "RUBYOPT": "-W0",
        ]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let lines = (String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .split(separator: "\n").map(String.init)
        let preload = directory.appendingPathComponent("rockxy-ruby-trust.rb").path

        #expect(process.terminationStatus == 0)
        #expect(lines.first == "-W0 -r\(preload)")
        #expect(lines.dropFirst().first == "true")
    }

    private static let javaHome: String? = {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else {
            return nil
        }
        process.waitUntilExit()
        let path = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, let path, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path + "/bin/keytool") else
        {
            return nil
        }
        return path
    }()
}
