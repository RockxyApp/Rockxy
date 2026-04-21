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
            return executableReadiness(
                title: "Python 3",
                urls: [URL(fileURLWithPath: "/usr/bin/python3")]
            )
        case .nodeJS:
            return executableReadiness(
                title: "Node.js",
                urls: executableCandidates(
                    name: "node",
                    additionalPaths: ["/usr/local/bin/node", "/opt/homebrew/bin/node"],
                    includeNVM: true
                )
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
            let note = "Java validation needs a local JDK or JRE. Install one on this Mac, then rerun the Java flow."
            return SetupRuntimeReadiness(isSatisfied: hasJava && hasJavac, note: hasJava && hasJavac ? nil : note)
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
                    additionalPaths: ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"]
                )
            )
        case .nextJS:
            return executableReadiness(
                title: "Node.js",
                urls: executableCandidates(
                    name: "node",
                    additionalPaths: ["/usr/local/bin/node", "/opt/homebrew/bin/node"],
                    includeNVM: true
                )
            )
        default:
            return .notRequired
        }
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

    private static func executableReadiness(title: String, urls: [URL]) -> SetupRuntimeReadiness {
        let fileManager = FileManager.default
        if urls.contains(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return SetupRuntimeReadiness(isSatisfied: true, note: nil)
        }

        return SetupRuntimeReadiness(
            isSatisfied: false,
            note: "\(title) is not installed or not on a standard executable path for this Mac yet."
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
