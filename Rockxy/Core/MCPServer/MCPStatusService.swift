import Foundation
import os

nonisolated(unsafe) private let logger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPStatusService"
)

// MARK: - MCPStatusService

struct MCPStatusService {
    // MARK: Internal

    /// Reference to the server coordinator for dynamic provider resolution.
    let serverCoordinator: MCPServerCoordinator

    func getVersion() -> MCPToolCallResult {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        let result: MCPJSONValue = .object([
            "app_version": .string(appVersion),
            "build_number": .string(buildNumber),
            "mcp_protocol_version": .string(MCPProtocolVersion.current),
            "app_name": .string(RockxyIdentity.current.displayName),
        ])

        return jsonResult(result)
    }

    func getProxyStatus() async -> MCPToolCallResult {
        let state = await MainActor.run { captureState() }

        var fields: [String: MCPJSONValue] = [
            "is_running": .bool(state.isRunning),
            "is_recording": .bool(state.isRecording),
            "is_system_proxy": .bool(state.isSystemProxy),
            "transaction_count": .int(state.transactionCount),
            "has_provider": .bool(state.hasProvider),
        ]

        if state.isRunning {
            fields["port"] = .int(state.port)
        }

        if !state.isRunning, !state.hasProvider {
            let message = "Proxy window not active"
            fields["note"] = .string(message)
            fields["status_reason"] = .string(message)
        }

        return jsonResult(.object(fields))
    }

    func getCertificateStatus() async -> MCPToolCallResult {
        let (readiness, canIntercept) = await MainActor.run {
            (
                ReadinessCoordinator.shared.certReadiness,
                ReadinessCoordinator.shared.canInterceptHTTPS
            )
        }

        var fields: [String: MCPJSONValue] = [
            "readiness": .string(readinessString(readiness)),
            "can_intercept_https": .bool(canIntercept),
        ]

        let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)

        fields["has_generated_certificate"] = .bool(snapshot.hasGeneratedCertificate)
        fields["is_installed_in_keychain"] = .bool(snapshot.isInstalledInKeychain)
        fields["has_trust_settings"] = .bool(snapshot.hasTrustSettings)
        fields["is_system_trust_validated"] = .bool(snapshot.isSystemTrustValidated)

        if let commonName = snapshot.commonName {
            fields["common_name"] = .string(commonName)
        }

        if let notBefore = snapshot.notValidBefore {
            fields["not_valid_before"] = .string(Self.dateFormatter.string(from: notBefore))
        }

        if let notAfter = snapshot.notValidAfter {
            fields["not_valid_after"] = .string(Self.dateFormatter.string(from: notAfter))
        }

        if let fingerprint = snapshot.fingerprintSHA256 {
            fields["fingerprint_sha256"] = .string(fingerprint)
        }

        return jsonResult(.object(fields))
    }

    func getSSLProxyingList() async -> MCPToolCallResult {
        let state = await MainActor.run { sslProxyingState() }

        var includeRules: [MCPJSONValue] = []
        for rule in state.includeRules {
            includeRules.append(.object([
                "id": .string(rule.id.uuidString),
                "domain": .string(rule.domain),
                "is_enabled": .bool(rule.isEnabled),
            ]))
        }

        var excludeRules: [MCPJSONValue] = []
        for rule in state.excludeRules {
            excludeRules.append(.object([
                "id": .string(rule.id.uuidString),
                "domain": .string(rule.domain),
                "is_enabled": .bool(rule.isEnabled),
            ]))
        }

        let result: MCPJSONValue = .object([
            "is_enabled": .bool(state.isEnabled),
            "include_rules": .array(includeRules),
            "exclude_rules": .array(excludeRules),
            "bypass_domains": .string(state.bypassDomains),
        ])

        return jsonResult(result)
    }

    // MARK: Private

    private struct CaptureState {
        let isRunning: Bool
        let port: Int
        let isRecording: Bool
        let isSystemProxy: Bool
        let transactionCount: Int
        let hasProvider: Bool
    }

    private struct SSLState {
        let isEnabled: Bool
        let includeRules: [SSLProxyingRule]
        let excludeRules: [SSLProxyingRule]
        let bypassDomains: String
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @MainActor
    private func captureState() -> CaptureState {
        guard let provider = serverCoordinator.currentStateProvider() else {
            return CaptureState(
                isRunning: false,
                port: 0,
                isRecording: false,
                isSystemProxy: false,
                transactionCount: 0,
                hasProvider: false
            )
        }
        return CaptureState(
            isRunning: provider.isProxyRunning,
            port: provider.activeProxyPort,
            isRecording: provider.isRecording,
            isSystemProxy: provider.isSystemProxyConfigured,
            transactionCount: provider.transactionCount,
            hasProvider: true
        )
    }

    @MainActor
    private func sslProxyingState() -> SSLState {
        let manager = SSLProxyingManager.shared
        return SSLState(
            isEnabled: manager.isEnabled,
            includeRules: manager.includeRules,
            excludeRules: manager.excludeRules,
            bypassDomains: manager.bypassDomains
        )
    }

    private func readinessString(_ readiness: CertReadiness) -> String {
        switch readiness {
        case .notGenerated:
            "not_generated"
        case .generatedNotInstalled:
            "generated_not_installed"
        case .installedNotTrusted:
            "installed_not_trusted"
        case .trusted:
            "trusted"
        }
    }

    private func jsonResult(_ value: MCPJSONValue) -> MCPToolCallResult {
        do {
            let data = try value.encodeToData()
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return MCPToolCallResult(content: [.text(text)], isError: nil)
        } catch {
            logger.error("Failed to encode tool result: \(error.localizedDescription, privacy: .public)")
            return MCPToolCallResult(
                content: [.text("{\"error\": \"Internal encoding error\"}")],
                isError: true
            )
        }
    }
}
