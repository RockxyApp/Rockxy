import Foundation

enum HandshakeReader {
    // MARK: Internal

    struct Handshake: Codable {
        let token: String
        let port: Int
    }

    enum HandshakeError: LocalizedError {
        case fileNotFound
        case invalidFormat(String)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                "MCP handshake file not found at \(HandshakeReader.handshakePath.path)"
            case let .invalidFormat(detail):
                "MCP handshake file has invalid format: \(detail)"
            }
        }
    }

    static func readHandshake() throws -> Handshake {
        let filePath = handshakePath

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw HandshakeError.fileNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: filePath)
        } catch {
            throw HandshakeError.invalidFormat("could not read file: \(error.localizedDescription)")
        }

        do {
            return try JSONDecoder().decode(Handshake.self, from: data)
        } catch {
            throw HandshakeError.invalidFormat(error.localizedDescription)
        }
    }

    // MARK: Private

    private static let fallbackAppSupportDirectoryName = "com.amunx.rockxy.community"

    private static let testRunToken: String = {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["ROCKXY_TEST_RUN_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !explicit.isEmpty
        {
            return explicit
        }

        if let configurationPath = environment["XCTestConfigurationFilePath"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !configurationPath.isEmpty
        {
            return "xc-\(stableHash(configurationPath))"
        }

        return "default"
    }()

    /// Discover the app support directory name by reading the host app's Info.plist.
    /// The CLI binary lives at Rockxy.app/Contents/MacOS/rockxy-mcp, so the app's
    /// Info.plist is at ../../Info.plist relative to the executable.
    private static var appSupportDirectoryName: String {
        if let plist = hostApplicationInfoDictionary {
            if let dirName = plist["RockxyAppSupportDirectoryName"] as? String, !dirName.isEmpty {
                return dirName
            }
            if let bundleId = plist["CFBundleIdentifier"] as? String, !bundleId.isEmpty {
                return bundleId
            }
            if let familyNamespace = plist["RockxyFamilyNamespace"] as? String, !familyNamespace.isEmpty {
                return familyNamespace
            }
        }
        return fallbackAppSupportDirectoryName
    }

    private static var handshakePath: URL {
        applicationSupportDirectory
            .appendingPathComponent("mcp-handshake.json")
    }

    private static var applicationSupportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["ROCKXY_TEST_APP_SUPPORT_DIRECTORY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        if isRunningTests {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("rockxy-tests-\(testRunToken)", isDirectory: true)
            return root.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        }

        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return root.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
    }

    private static var hostApplicationInfoDictionary: [String: Any]? {
        guard let executablePath = Bundle.main.executablePath else {
            return nil
        }

        let executableURL = URL(fileURLWithPath: executablePath)
        let contentsURL = executableURL
            .deletingLastPathComponent() // MacOS/
            .deletingLastPathComponent() // Contents/
        let plistURL = contentsURL.appendingPathComponent("Info.plist")

        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: plistData,
                  format: nil
              ) as? [String: Any] else
        {
            return nil
        }

        return plist
    }

    private static var isRunningTests: Bool {
        !(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] ?? "").isEmpty
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("Testing.Test") != nil
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
