import Foundation
import os
import SwiftUI

// Owns onboarding progress and helper or certificate status for the welcome experience.

// MARK: - WelcomeViewModel

@MainActor @Observable
final class WelcomeViewModel {
    // MARK: Internal

    var certInstalled = false
    var certTrusted = false
    var helperStatus: HelperManager.HelperStatus = .notInstalled
    var systemProxyEnabled = false
    var isPerformingAction = false
    var errorMessage: String?

    var completedSteps: Int {
        var count = 0
        if certInstalled {
            count += 1
        }
        if certTrusted {
            count += 1
        }
        if helperStatus == .installedCompatible {
            count += 1
        }
        if systemProxyEnabled {
            count += 1
        }
        return count
    }

    var totalSteps: Int {
        4
    }

    var canGetStarted: Bool {
        certInstalled && certTrusted && helperStatus == .installedCompatible && systemProxyEnabled
    }

    func refreshStatus() async {
        let installed = await CertificateManager.shared.isRootCAInstalled()
        let trusted = await CertificateManager.shared.isRootCATrusted()
        await HelperManager.shared.checkStatus()
        let proxyEnabled = SystemProxyManager.shared.isSystemProxyEnabled()

        certInstalled = installed
        certTrusted = trusted
        helperStatus = HelperManager.shared.status
        systemProxyEnabled = proxyEnabled
    }

    func installCert() async {
        guard !certTrusted else {
            return
        }
        isPerformingAction = true
        errorMessage = nil
        defer { isPerformingAction = false }

        do {
            try await CertificateManager.shared.installAndTrust()
            certInstalled = true
            certTrusted = true
            await refreshStatus()
        } catch {
            Self.logger.error("Failed to install certificate: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func installHelper() async {
        isPerformingAction = true
        errorMessage = nil
        defer { isPerformingAction = false }

        do {
            try await HelperManager.shared.install()
            await refreshStatus()
        } catch {
            Self.logger.error("Failed to install helper: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func updateHelper() async {
        isPerformingAction = true
        errorMessage = nil
        defer { isPerformingAction = false }

        do {
            try await HelperManager.shared.update()
            await refreshStatus()
        } catch {
            Self.logger.error("Failed to update helper: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func enableProxy() async {
        isPerformingAction = true
        errorMessage = nil
        defer { isPerformingAction = false }

        do {
            let settings = AppSettingsStorage.load()
            try await SystemProxyManager.shared.enableSystemProxy(port: settings.proxyPort)
            await refreshStatus()
        } catch {
            Self.logger.error("Failed to enable proxy: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: "com.amunx.Rockxy", category: "WelcomeViewModel")
}
