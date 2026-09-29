import Foundation

extension MainContentCoordinator {
    func attachToMCPServer(_ mcpCoordinator: MCPServerCoordinator) {
        mcpCoordinator.attachProviders(flow: self, state: self, control: self)
    }

    func detachFromMCPServer(_ mcpCoordinator: MCPServerCoordinator) {
        mcpCoordinator.detachProviders()
    }
}

// MARK: - MainContentCoordinator + MCPCaptureControlProvider

extension MainContentCoordinator: MCPCaptureControlProvider {
    func mcpEnableHTTPSDecryption(for domain: String) -> MCPDecryptionChange {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let reason = sslProxyingHostDecryptBlockedReason(for: normalized) {
            return .refused(reason: reason)
        }
        return enableSSLProxyingForDomain(normalized)
            ? .enabled(domain: normalized)
            : .alreadyEnabled(domain: normalized)
    }

    func mcpSetRecording(_ isRecording: Bool) -> Bool {
        guard isProxyRunning else {
            return false
        }
        if self.isRecording != isRecording {
            toggleRecording()
        }
        return true
    }

    func mcpClearSession() async {
        await clearSession()
    }
}
