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
}
