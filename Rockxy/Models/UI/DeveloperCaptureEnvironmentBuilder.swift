import Foundation

/// Builds the launch environment shared by generic developer applications and prepared terminals.
/// Existing user options survive; Rockxy-owned option blocks are replaced idempotently.
enum DeveloperCaptureEnvironmentBuilder {
    static func safeInheritedEnvironment(
        from environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let fixedKeys = ["HOME", "USER", "LOGNAME", "PATH", "SHELL", "TMPDIR", "LANG", "SSH_AUTH_SOCK"]
        var inherited = environment.filter { key, _ in
            fixedKeys.contains(key) || key.hasPrefix("LC_")
        }
        // Finder-launched applications may omit PATH; provide the same conservative system path
        // expected by command-line children without inheriting shell startup secrets.
        inherited["PATH"] = inherited["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return inherited
    }

    static func environment(
        context: RockxySetupScriptContext,
        baseEnvironment: [String: String] = [:],
        includeJavaProxyProperties: Bool? = nil
    ) -> [String: String] {
        let proxyURL = "http://\(context.proxyHost):\(context.proxyPort)"
        var environment = baseEnvironment

        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            environment[key] = proxyURL
        }
        environment["npm_config_proxy"] = proxyURL
        environment["npm_config_https_proxy"] = proxyURL
        environment["ROCKXY_PROXY_HOST"] = context.proxyHost
        environment["ROCKXY_PROXY_PORT"] = String(context.proxyPort)
        environment["ROCKXY_SETUP_SESSION"] = "1"

        if environment["NO_PROXY"] == nil {
            environment["NO_PROXY"] = "localhost,127.0.0.1,::1"
        }
        environment["no_proxy"] = environment["NO_PROXY"]

        if let certificatePath = context.certificatePath, !certificatePath.isEmpty {
            // NODE_EXTRA_CA_CERTS is additive. Replacement-style CA variables are deliberately
            // omitted because pointing them at Rockxy's single root would discard the runtime's
            // normal public and corporate trust anchors.
            environment["NODE_EXTRA_CA_CERTS"] = certificatePath
            environment["ROCKXY_ROOT_CA_PATH"] = certificatePath
        }

        if includeJavaProxyProperties ?? (context.targetID == .javaVMs) {
            let options = javaProxyOptions(proxyHost: context.proxyHost, proxyPort: context.proxyPort)
            var existing = environment["JAVA_TOOL_OPTIONS"] ?? ""
            if let previous = environment["ROCKXY_JAVA_PROXY_OPTS"], !previous.isEmpty {
                existing = existing.replacingOccurrences(of: previous, with: "")
            }
            environment["ROCKXY_JAVA_PROXY_OPTS"] = options
            environment["JAVA_TOOL_OPTIONS"] = [existing.trimmingCharacters(in: .whitespaces), options]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        return environment
    }

    static func javaProxyOptions(proxyHost: String, proxyPort: Int) -> String {
        "-Dhttp.proxyHost=\(proxyHost) -Dhttp.proxyPort=\(proxyPort) " +
            "-Dhttps.proxyHost=\(proxyHost) -Dhttps.proxyPort=\(proxyPort)"
    }
}
