import Foundation

// MARK: - SetupRuntimeReadiness

struct SetupRuntimeReadiness: Equatable {
    let isSatisfied: Bool
    let note: String?

    static let notRequired = SetupRuntimeReadiness(isSatisfied: true, note: nil)
}

// MARK: - DeveloperSetupRuntimeTooling

enum DeveloperSetupRuntimeTooling {
    static func readiness(for targetID: SetupTarget.ID) -> SetupRuntimeReadiness {
        switch targetID {
        case .python:
            let pathCandidates = executableURLsOnPath(named: "python3")
            return executableReadiness(
                title: "Python 3",
                urls: [URL(fileURLWithPath: "/usr/bin/python3")] + pathCandidates,
                missingNote: "Python validation needs a local python3 executable. Install Python 3, or make sure python3 is available on PATH, then rerun the Python setup flow."
            )
        case .nodeJS:
            return executableReadiness(
                title: "Node.js",
                urls: nodeExecutableCandidates(),
                missingNote: """
                Node.js validation needs a local node executable. Install Node with Homebrew or nvm, \
                or make sure node is available on PATH, then rerun the Node.js setup flow.
                """
            )
        case .ruby:
            return executableReadiness(
                title: "Ruby",
                urls: [URL(fileURLWithPath: "/usr/bin/ruby")]
            )
        case .golang:
            return executableReadiness(
                title: "Go",
                urls: executableCandidates(
                    name: "go",
                    additionalPaths: ["/usr/local/bin/go", "/opt/homebrew/bin/go"]
                )
            )
        case .rust:
            return executableReadiness(
                title: "Rust",
                urls: executableCandidates(
                    name: "rustc",
                    additionalPaths: ["/usr/local/bin/rustc", "/opt/homebrew/bin/rustc"],
                    includeCargoHome: true
                )
            )
        case .javaVMs:
            let hasJava = javaTool(named: "java") != nil
            let hasJavac = javaTool(named: "javac") != nil
            let hasKeytool = javaTool(named: "keytool") != nil
            let note = "Java validation needs a local JDK with java, javac, and keytool installed. Install a JDK on this Mac, then rerun the Java flow."
            return SetupRuntimeReadiness(
                isSatisfied: hasJava && hasJavac && hasKeytool,
                note: hasJava && hasJavac && hasKeytool ? nil : note
            )
        case .curl:
            return executableReadiness(
                title: "cURL",
                urls: [URL(fileURLWithPath: "/usr/bin/curl")]
            )
        case .docker:
            return executableReadiness(
                title: "Docker CLI",
                urls: executableCandidates(
                    name: "docker",
                    additionalPaths: [
                        "/usr/local/bin/docker",
                        "/opt/homebrew/bin/docker",
                        "/Applications/Docker.app/Contents/Resources/bin/docker",
                    ]
                )
            )
        case .nextJS:
            return executableReadiness(
                title: "Node.js",
                urls: nodeExecutableCandidates(),
                missingNote: """
                Node.js validation needs a local node executable. Install Node with Homebrew or nvm, \
                or make sure node is available on PATH, then rerun the Next.js setup flow.
                """
            )
        default:
            return .notRequired
        }
    }

    static func readinessAsync(for targetID: SetupTarget.ID) async -> SetupRuntimeReadiness {
        await Task.detached(priority: .utility) {
            readiness(for: targetID)
        }.value
    }

    static func javaTool(named name: String) -> URL? {
        let fileManager = FileManager.default

        let directCandidates = [
            "/opt/homebrew/opt/openjdk/bin/\(name)",
            "/usr/local/opt/openjdk/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]

        for candidate in directCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

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
        return fileManager.isExecutableFile(atPath: toolURL.path) ? toolURL : nil
    }

    static func executableURLsOnPath(named name: String, path: String? = nil) -> [URL] {
        let searchPath = path ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        guard !searchPath.isEmpty else {
            return []
        }

        let fileManager = FileManager.default
        var urls: [URL] = []
        var seen = Set<String>()

        for component in searchPath.split(separator: ":").map(String.init) where !component.isEmpty {
            let candidate = URL(fileURLWithPath: component).appendingPathComponent(name)
            let normalizedPath = candidate.path
            guard
                seen.insert(normalizedPath).inserted,
                fileManager.isExecutableFile(atPath: normalizedPath)
            else {
                continue
            }
            urls.append(candidate)
        }

        return urls
    }

    static func nodeExecutableCandidates(
        path: String? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let fileManager = FileManager.default
        var urls = executableURLsOnPath(named: "node", path: path)
        var seen = Set(urls.map(\.path))

        let standardPaths = [
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/bin/node",
        ]
        for standardPath in standardPaths where seen.insert(standardPath).inserted {
            urls.append(URL(fileURLWithPath: standardPath))
        }

        let nvmVersionsDirectory = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versionDirectories = try? fileManager.contentsOfDirectory(
            at: nvmVersionsDirectory,
            includingPropertiesForKeys: nil
        ) {
            let discovered = versionDirectories
                .map { $0.appendingPathComponent("bin/node").path }
                .sorted()
                .reversed()
            for path in discovered where seen.insert(path).inserted {
                urls.append(URL(fileURLWithPath: path))
            }
        }

        return urls
    }

    private static func executableReadiness(
        title: String,
        urls: [URL],
        missingNote: String? = nil
    )
        -> SetupRuntimeReadiness
    {
        let fileManager = FileManager.default
        if urls.contains(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return SetupRuntimeReadiness(isSatisfied: true, note: nil)
        }

        return SetupRuntimeReadiness(
            isSatisfied: false,
            note: missingNote ?? "\(title) is not installed or not on a standard executable path for this Mac yet."
        )
    }

    private static func executableCandidates(
        name: String,
        additionalPaths: [String],
        includeCargoHome: Bool = false,
        includeNVM: Bool = false
    ) -> [URL] {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        var paths = additionalPaths
        paths.append("/usr/bin/\(name)")

        if includeCargoHome {
            paths.append(homeDirectory.appendingPathComponent(".cargo/bin/\(name)").path)
        }

        if includeNVM {
            let nvmVersionsDirectory = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
            if let versionDirectories = try? fileManager.contentsOfDirectory(
                at: nvmVersionsDirectory,
                includingPropertiesForKeys: nil
            ) {
                let discovered = versionDirectories
                    .map { $0.appendingPathComponent("bin/\(name)").path }
                    .sorted()
                paths.append(contentsOf: discovered.reversed())
            }
        }

        return paths.map(URL.init(fileURLWithPath:))
    }
}
