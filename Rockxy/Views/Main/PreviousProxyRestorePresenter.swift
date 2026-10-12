import AppKit
import os

// Defines `PreviousProxyRestorePresenter`, which asks the user whether to put back proxy settings
// that capture's restore deliberately left alone, and `PreviousProxyRestoreSummary`, which
// describes those settings.

// MARK: - PreviousProxyRestoreSummary

/// Human-readable descriptions of the settings a user is offered back.
enum PreviousProxyRestoreSummary {
    /// One line per service, such as "Wi-Fi: 127.0.0.1:7890 (HTTP, HTTPS, SOCKS)". Endpoints shared
    /// by several protocols are listed once, which is how proxy apps usually configure them.
    static func lines(for entries: [UnrestoredPreviousProxy]) -> [String] {
        entries.flatMap { entry in
            descriptions(of: entry.previous).map { description in
                String(localized: "\(entry.service): \(description)", bundle: RockxyLocalization.bundle)
            }
        }
    }

    static func descriptions(of snapshot: ServiceProxySnapshot) -> [String] {
        var protocolsByEndpoint: [(endpoint: String, protocols: [String])] = []
        func add(_ enabled: Bool, _ host: String, _ port: Int, _ name: String) {
            guard enabled, !host.isEmpty, port > 0 else {
                return
            }
            let endpoint = "\(host):\(port)"
            if let index = protocolsByEndpoint.firstIndex(where: { $0.endpoint == endpoint }) {
                protocolsByEndpoint[index].protocols.append(name)
            } else {
                protocolsByEndpoint.append((endpoint, [name]))
            }
        }
        add(snapshot.httpEnabled, snapshot.httpHost, snapshot.httpPort, "HTTP")
        add(snapshot.httpsEnabled, snapshot.httpsHost, snapshot.httpsPort, "HTTPS")
        add(snapshot.socksEnabled, snapshot.socksHost, snapshot.socksPort, "SOCKS")

        var descriptions = protocolsByEndpoint.map { entry in
            let protocols = entry.protocols.joined(separator: ", ")
            return "\(entry.endpoint) (\(protocols))"
        }
        if snapshot.pacEnabled {
            descriptions.append(
                snapshot.pacURL.isEmpty
                    ? String(localized: "Automatic proxy configuration", bundle: RockxyLocalization.bundle)
                    : String(
                        localized: "Automatic proxy configuration (\(snapshot.pacURL))",
                        bundle: RockxyLocalization.bundle
                    )
            )
        }
        if snapshot.autoDiscoveryEnabled {
            descriptions.append(String(localized: "Auto proxy discovery", bundle: RockxyLocalization.bundle))
        }
        return descriptions
    }
}

// MARK: - PreviousProxyRestorePresenter

@MainActor
enum PreviousProxyRestorePresenter {
    // MARK: Internal

    /// Asks whether to restore the previous settings and writes them only if the user agrees.
    /// Nothing is written without that answer: the current settings came from another app or
    /// from a person, and either may be the one the user wants.
    static func resolve(_ report: SystemProxyRestoreReport) async {
        guard report.needsDecision else {
            return
        }
        let entries = report.unrestoredPreviousProxies
        let unreachablePorts = await unreachableLoopbackPorts(in: entries)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = AppIconProvider.appIcon
        alert.messageText = String(
            localized: "Restore your previous proxy settings?",
            bundle: RockxyLocalization.bundle
        )
        alert.informativeText = informativeText(
            lines: PreviousProxyRestoreSummary.lines(for: entries),
            unreachablePorts: unreachablePorts
        )
        let restoreButton = alert.addButton(
            withTitle: String(localized: "Restore Previous Settings", bundle: RockxyLocalization.bundle)
        )
        let keepButton = alert.addButton(
            withTitle: String(localized: "Keep Current Settings", bundle: RockxyLocalization.bundle)
        )
        // A previous proxy nothing is serving would cut the Mac off the network, so Return keeps
        // the current settings in that case and restoring takes a deliberate click.
        if !unreachablePorts.isEmpty {
            restoreButton.keyEquivalent = ""
            keepButton.keyEquivalent = "\r"
        }

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            logger.info("Kept the current proxy settings for \(entries.count) service(s)")
            return
        }

        do {
            let result = try await SystemProxyManager.shared.restorePreviousProxySettings(entries)
            logger.info(
                "Restored previous proxy settings on \(result.restoredServices.count) service(s); \(result.changedServices.count) changed again"
            )
            if !result.changedServices.isEmpty {
                presentChangedAgain(services: result.changedServices)
            }
        } catch {
            logger.error("Could not restore previous proxy settings: \(error.localizedDescription)")
            presentFailure(error: error)
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "PreviousProxyRestore"
    )

    private static func informativeText(lines: [String], unreachablePorts: [Int]) -> String {
        var paragraphs = [
            String(
                // swiftlint:disable:next line_length
                localized: "Rockxy left your proxy settings as they are because another app or a person changed them while Rockxy was capturing. Your settings before capture were:",
                bundle: RockxyLocalization.bundle
            ),
            lines.joined(separator: "\n"),
        ]
        for port in unreachablePorts {
            paragraphs.append(
                String(
                    localized: "Nothing is listening on 127.0.0.1:\(String(port)) right now. Restoring it can block network access until the app that provides it is running again.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
        return paragraphs.joined(separator: "\n\n")
    }

    /// Loopback endpoints with no visible listener. Other outcomes, including an unanswered
    /// probe, give no reason to steer the user away from restoring.
    private static func unreachableLoopbackPorts(in entries: [UnrestoredPreviousProxy]) async -> [Int] {
        let ports = LoopbackProxyOwnershipPolicy.enabledLoopbackPorts(in: entries.map(\.previous))
        guard !ports.isEmpty else {
            return []
        }
        return await Task.detached(priority: .userInitiated) {
            ports.filter { LoopbackProxyListenerResolver.listener(onPort: $0) == .none }
        }.value
    }

    private static func presentChangedAgain(services: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(
            localized: "Some proxy settings changed again",
            bundle: RockxyLocalization.bundle
        )
        alert.informativeText = String(
            localized: "Rockxy did not change \(services.joined(separator: ", ")) because its proxy settings changed while you were deciding.",
            bundle: RockxyLocalization.bundle
        )
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
        alert.runModal()
    }

    private static func presentFailure(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "Rockxy could not restore your previous proxy settings",
            bundle: RockxyLocalization.bundle
        )
        alert.informativeText = String(
            localized: "Change them in System Settings > Network > (your network) > Details > Proxies.\n\n\(error.localizedDescription)",
            bundle: RockxyLocalization.bundle
        )
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
        alert.runModal()
    }
}
