import Foundation
import os

// Extends `MainContentCoordinator` with the system-proxy acquisition policy: the "Never" guard,
// the user-facing switch on/off/retry controls, and how their failures are reported. Acquiring
// is gated by `AutomaticSystemProxyRouting`; releasing is never gated.

// MARK: - MainContentCoordinator + SystemProxyRouting

extension MainContentCoordinator {
    /// "Never" refusals are a choice the user made, not a fault: no failure warning (its Retry
    /// would only be refused again), routing is not expected, and the reason is shown.
    func reportRoutingBlocked() {
        readiness.clearProxyEnableFailure()
        readiness.setSystemRoutingExpected(false)
        activeToast = ToastMessage(style: .warning, text: AutomaticSystemProxyRouting.neverUnavailableReason)
        Self.logger.info("System proxy change refused: routing mode is Never")
    }

    /// Entry guard for every user-facing path that would set the system proxy. Returns false
    /// after explaining why, before anything is marked expected or touched.
    func systemProxyAcquisitionAllowed() -> Bool {
        guard AutomaticSystemProxyRouting.permits(.acquireExplicitly, mode: AutomaticSystemProxyRouting.currentMode()) else {
            reportRoutingBlocked()
            return false
        }
        return true
    }

    /// A Stop that superseded an in-flight enable is the user getting what they asked
    /// for, so it must not surface as an enable failure. Everything else still does.
    func reportEnableFailure(_ error: Error) {
        if error is SystemProxyRoutingBlocked {
            reportRoutingBlocked()
            return
        }
        if let proxyError = error as? SystemProxyError, case .enableSupersededByStop = proxyError {
            Self.logger.info("System proxy enable gave way to Stop")
            return
        }
        readiness.setProxyEnableFailed(message: error.localizedDescription)
    }

    func retrySystemProxy() {
        guard isProxyRunning, systemProxyAcquisitionAllowed() else {
            return
        }
        readiness.clearProxyEnableFailure()
        readiness.setSystemRoutingExpected(true)

        Task {
            do {
                try await enableSystemProxySyncingRefusal(port: self.activeProxyPort)
                isSystemProxyConfigured = true
                isProxyOverridden = true
                readiness.setSystemRoutingReady(true)
                runCaptureHealthCheck()
                Self.logger.info("System proxy enabled on retry")
            } catch {
                isSystemProxyConfigured = false
                isProxyOverridden = false
                readiness.setSystemRoutingReady(false)
                reportEnableFailure(error)
                Self.logger.warning("System proxy retry failed: \(error.localizedDescription)")
            }
        }
    }

    /// Returns the task that applies the change, so a caller can wait for macOS to finish.
    @discardableResult
    func switchOffSystemProxyOverride() -> Task<Void, Never> {
        Task { @MainActor in
            do {
                let report = try await disableSystemProxySyncingRefusal()
                isSystemProxyConfigured = false
                isProxyOverridden = false
                readiness.setSystemRoutingExpected(false)
                readiness.setSystemRoutingReady(false)
                await readiness.refresh()
                Self.logger.info("System proxy override switched off")
                await PreviousProxyRestorePresenter.resolve(report)
            } catch {
                readiness.setProxyRestoreFailed(retryAction: .retryDisableSystemRouting)
                Self.logger.error("Failed to switch off system proxy override: \(error.localizedDescription)")
            }
        }
    }

    /// Returns the task that applies the change, or nil when the proxy is not running.
    @discardableResult
    func switchOnSystemProxyOverride() -> Task<Void, Never>? {
        guard isProxyRunning, systemProxyAcquisitionAllowed() else {
            return nil
        }
        readiness.clearProxyEnableFailure()
        readiness.setSystemRoutingExpected(true)

        return Task { @MainActor in
            do {
                try await enableSystemProxySyncingRefusal(port: self.activeProxyPort)
                isSystemProxyConfigured = true
                isProxyOverridden = true
                readiness.setSystemRoutingReady(true)
                runCaptureHealthCheck()
                await readiness.refresh()
                Self.logger.info("System proxy override switched on")
            } catch {
                isSystemProxyConfigured = false
                isProxyOverridden = false
                readiness.setSystemRoutingReady(false)
                reportEnableFailure(error)
                Self.logger.error("Failed to switch on system proxy override: \(error.localizedDescription)")
            }
        }
    }

    func toggleSystemProxyOverride() {
        // Only disable when the live routing is confirmed to point at this listener.
        // A stale/foreign override must be reclaimed, not switched off as if Rockxy owned it.
        if isSystemProxyConfigured {
            switchOffSystemProxyOverride()
        } else {
            switchOnSystemProxyOverride()
        }
    }
}
