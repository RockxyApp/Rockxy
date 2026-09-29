import Foundation
import os

nonisolated(unsafe) private let logger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPChangeService"
)

// MARK: - MCPChangeService

/// Handles every MCP tool that changes Rockxy. Each call re-checks the user's permission
/// first; nothing is validated, written, or toggled while changes are turned off.
struct MCPChangeService {
    // MARK: Lifecycle

    init(
        serverCoordinator: MCPServerCoordinator,
        ruleMutations: MCPRuleMutationService,
        permission: MCPChangePermission = MCPChangePermission(),
        defaults: UserDefaults = .standard
    ) {
        self.serverCoordinator = serverCoordinator
        self.ruleMutations = ruleMutations
        self.permission = permission
        self.defaults = defaults
    }

    // MARK: Internal

    static let toolNames: Set<String> = [
        "create_breakpoint",
        "create_map_local",
        "create_map_remote",
        "create_block_rule",
        "set_rule_enabled",
        "enable_ssl_proxying",
        "set_no_caching",
        "set_recording",
        "clear_session",
    ]

    let serverCoordinator: MCPServerCoordinator
    let ruleMutations: MCPRuleMutationService
    let permission: MCPChangePermission
    let defaults: UserDefaults

    /// Accepts a host name or a leading-wildcard pattern such as `*.example.com`.
    static func isValidDecryptionDomain(_ value: String) -> Bool {
        let host = value.hasPrefix("*.") ? String(value.dropFirst(2)) : value
        guard !host.isEmpty, value.count <= 253, !host.hasPrefix("."), !host.hasSuffix("."),
              !host.contains("..") else
        {
            return false
        }
        return host.unicodeScalars.allSatisfy {
            ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" || $0 == "."
        }
    }

    func call(_ name: String, arguments args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        guard permission.isAllowed() else {
            logger.info("MCP change refused (changes are off): \(name, privacy: .public)")
            return MCPChangePermission.deniedResult(tool: name)
        }

        switch name {
        case "create_breakpoint":
            return await ruleMutations.createBreakpoint(args)
        case "create_map_local":
            return await ruleMutations.createMapLocal(args)
        case "create_map_remote":
            return await ruleMutations.createMapRemote(args)
        case "create_block_rule":
            return await ruleMutations.createBlockRule(args)
        case "set_rule_enabled":
            return await ruleMutations.setRuleEnabled(args)
        case "enable_ssl_proxying":
            return await enableSSLProxying(args)
        case "set_no_caching":
            return setNoCaching(args)
        case "set_recording":
            return await setRecording(args)
        case "clear_session":
            return await clearSession()
        default:
            return MCPToolResultEncoding.error(["error": "Unknown tool: \(name)"])
        }
    }

    // MARK: Private

    private static let windowUnavailable = MCPToolResultEncoding.error([
        "error": "The Rockxy main window is not open. Ask the user to open it and try again.",
    ])

    private func enableSSLProxying(_ args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        guard case let .string(rawDomain) = args["domain"] else {
            return MCPArgumentError(param: "domain", message: "Missing required parameter: domain").result
        }
        let domain = rawDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidDecryptionDomain(domain) else {
            return MCPArgumentError(
                param: "domain",
                message: "domain must be a host name such as api.example.com or *.example.com"
            ).result
        }

        let outcome: MCPDecryptionChange? = await MainActor.run {
            serverCoordinator.currentControlProvider()?.mcpEnableHTTPSDecryption(for: domain)
        }
        let canIntercept = await MainActor.run { ReadinessCoordinator.shared.canInterceptHTTPS }

        switch outcome {
        case nil:
            return Self.windowUnavailable
        case let .refused(reason):
            return MCPToolResultEncoding.error(["error": reason, "domain": domain])
        case let .enabled(domain),
             let .alreadyEnabled(domain):
            var fields: [String: MCPJSONValue] = [
                "domain": .string(domain),
                "changed": .bool(outcome == .enabled(domain: domain)),
                "can_intercept_https": .bool(canIntercept),
            ]
            if !canIntercept {
                fields["note"] = .string(
                    "The Rockxy root certificate is not trusted yet, so HTTPS stays encrypted until "
                        + "the user installs and trusts it from the Certificate menu."
                )
            }
            return MCPToolResultEncoding.object(fields)
        }
    }

    private func setNoCaching(_ args: [String: MCPJSONValue]) -> MCPToolCallResult {
        guard case let .bool(enabled) = args["enabled"] else {
            return MCPArgumentError(param: "enabled", message: "Missing required parameter: enabled").result
        }
        defaults.set(enabled, forKey: NoCacheHeaderMutator.userDefaultsKey)
        return MCPToolResultEncoding.object(["no_caching": .bool(enabled)])
    }

    private func setRecording(_ args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        guard case let .bool(recording) = args["recording"] else {
            return MCPArgumentError(param: "recording", message: "Missing required parameter: recording").result
        }
        let applied: Bool? = await MainActor.run {
            serverCoordinator.currentControlProvider()?.mcpSetRecording(recording)
        }
        switch applied {
        case nil:
            return Self.windowUnavailable
        case false?:
            return MCPToolResultEncoding.error([
                "error": "The proxy is not running. Ask the user to start capture in Rockxy first.",
            ])
        case true?:
            return MCPToolResultEncoding.object(["is_recording": .bool(recording)])
        }
    }

    @MainActor
    private func clearSession() async -> MCPToolCallResult {
        guard let provider = serverCoordinator.currentControlProvider() else {
            return Self.windowUnavailable
        }
        await provider.mcpClearSession()
        return MCPToolResultEncoding.object(["cleared": .bool(true)])
    }
}
