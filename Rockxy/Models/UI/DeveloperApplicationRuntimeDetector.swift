import Foundation

/// Runtime behavior detected from bounded, structural evidence inside an application bundle.
/// Capabilities are intentionally independent from settings formats and product identities.
enum DeveloperApplicationRuntimeCapability: Hashable, Sendable {
    case javaVirtualMachine
}

enum DeveloperApplicationRuntimeDetector {
    static func capabilities(
        in appURL: URL,
        bundle: Bundle,
        fileManager: FileManager = .default
    ) -> Set<DeveloperApplicationRuntimeCapability> {
        if productMetadataDeclaresJavaRuntime(in: appURL, fileManager: fileManager)
            || isJPackageApplication(appURL, bundle: bundle, fileManager: fileManager)
            || isLegacyJavaApplication(appURL, bundle: bundle, fileManager: fileManager)
        {
            return [.javaVirtualMachine]
        }
        return []
    }

    static func isContainedExecutable(
        relativePath: String,
        relativeTo baseURL: URL,
        bundleURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            return false
        }
        return isContainedExecutable(
            baseURL.appendingPathComponent(relativePath),
            bundleURL: bundleURL,
            fileManager: fileManager
        )
    }

    private static let maximumMetadataBytes: UInt64 = 1_048_576

    private static func productMetadataDeclaresJavaRuntime(
        in appURL: URL,
        fileManager: FileManager
    ) -> Bool {
        let metadataURL = appURL
            .appendingPathComponent("Contents/Resources/product-info.json", isDirectory: false)
        guard fileManager.fileExists(atPath: metadataURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: metadataURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.uint64Value <= maximumMetadataBytes,
              let data = try? Data(contentsOf: metadataURL, options: [.mappedIfSafe]),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let launchEntries = object["launch"] as? [[String: Any]]
        else {
            return false
        }
        let baseURL = metadataURL.deletingLastPathComponent()
        return launchEntries.contains { entry in
            guard entry["os"] as? String == "macOS",
                  let relativePath = entry["javaExecutablePath"] as? String
            else {
                return false
            }
            return isContainedExecutable(
                relativePath: relativePath,
                relativeTo: baseURL,
                bundleURL: appURL,
                fileManager: fileManager
            )
        }
    }

    private static func isJPackageApplication(
        _ appURL: URL,
        bundle: Bundle,
        fileManager: FileManager
    ) -> Bool {
        guard let executable = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              isSafeDirectoryComponent(executable)
        else {
            return false
        }
        let runtimeURL = appURL.appendingPathComponent(
            "Contents/runtime/Contents/Home/bin/java",
            isDirectory: false
        )
        let configurationURL = appURL.appendingPathComponent(
            "Contents/app/\(executable).cfg",
            isDirectory: false
        )
        return isContainedExecutable(
            runtimeURL,
            bundleURL: appURL,
            fileManager: fileManager
        ) && fileManager.isReadableFile(atPath: configurationURL.path)
    }

    private static func isLegacyJavaApplication(
        _ appURL: URL,
        bundle: Bundle,
        fileManager: FileManager
    ) -> Bool {
        guard bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "JavaApplicationStub"
        else {
            return false
        }
        let mainClass = bundle.object(forInfoDictionaryKey: "JVMMainClassName") as? String
        let executableURL = appURL.appendingPathComponent(
            "Contents/MacOS/JavaApplicationStub",
            isDirectory: false
        )
        return mainClass?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && isContainedExecutable(executableURL, bundleURL: appURL, fileManager: fileManager)
    }

    private static func isContainedExecutable(
        _ executableURL: URL,
        bundleURL: URL,
        fileManager: FileManager
    ) -> Bool {
        let resolvedBundleURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = resolvedBundleURL.path.hasSuffix("/")
            ? resolvedBundleURL.path
            : resolvedBundleURL.path + "/"
        guard resolvedExecutableURL.path.hasPrefix(prefix) else {
            return false
        }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: resolvedExecutableURL.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && fileManager.isExecutableFile(atPath: resolvedExecutableURL.path)
    }

    private static func isSafeDirectoryComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.contains(":")
            && !component.contains("\0")
    }
}
