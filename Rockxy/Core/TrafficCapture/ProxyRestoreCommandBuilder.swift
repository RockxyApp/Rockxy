import Foundation

// Defines `ProxyRestoreCommandBuilder`, which builds proxy restore command values for
// traffic capture and system proxy coordination.

// MARK: - ProxyRestoreCommandBuilder

enum ProxyRestoreCommandBuilder {
    static func parsePACOutput(_ output: String) -> (enabled: Bool, url: String) {
        var enabled = false
        var url = ""

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                enabled = value.lowercased() == "yes"
            } else if trimmed.hasPrefix("URL:") {
                let value = trimmed.replacingOccurrences(of: "URL:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value != "(null)" {
                    url = value
                }
            }
        }

        return (enabled, url)
    }

    static func parseAutoDiscoveryOutput(_ output: String) -> Bool {
        output.components(separatedBy: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Auto Proxy Discovery:") else {
                return false
            }
            let value = trimmed.replacingOccurrences(of: "Auto Proxy Discovery:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return value.lowercased() == "on"
        }
    }

    static func commands(service: String, snapshot: ServiceProxySnapshot) -> [[String]] {
        var commands: [[String]] = [
            ["-setwebproxystate", service, "off"],
            ["-setsecurewebproxystate", service, "off"],
            ["-setsocksfirewallproxystate", service, "off"],
            ["-setautoproxystate", service, "off"],
            ["-setproxyautodiscovery", service, "off"],
        ]

        if !snapshot.httpHost.isEmpty, snapshot.httpPort > 0 {
            commands.append(["-setwebproxy", service, snapshot.httpHost, String(snapshot.httpPort)])
            commands.append(["-setwebproxystate", service, snapshot.httpEnabled ? "on" : "off"])
        }

        if !snapshot.httpsHost.isEmpty, snapshot.httpsPort > 0 {
            commands.append([
                "-setsecurewebproxy", service, snapshot.httpsHost, String(snapshot.httpsPort),
            ])
            commands.append(["-setsecurewebproxystate", service, snapshot.httpsEnabled ? "on" : "off"])
        }

        if !snapshot.socksHost.isEmpty, snapshot.socksPort > 0 {
            commands.append([
                "-setsocksfirewallproxy", service, snapshot.socksHost, String(snapshot.socksPort),
            ])
            commands.append(["-setsocksfirewallproxystate", service, snapshot.socksEnabled ? "on" : "off"])
        }

        if snapshot.pacEnabled {
            if !snapshot.pacURL.isEmpty {
                commands.append(["-setautoproxyurl", service, snapshot.pacURL])
            }
            commands.append(["-setautoproxystate", service, "on"])
        }

        if snapshot.autoDiscoveryEnabled {
            commands.append(["-setproxyautodiscovery", service, "on"])
        }

        return commands
    }
}
