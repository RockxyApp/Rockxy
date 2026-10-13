import Combine
import Foundation

// Observes the upstream proxy configuration for the External Proxy menu items.

// MARK: - ExternalProxyMenuState

@MainActor
final class ExternalProxyMenuState: ObservableObject {
    // MARK: Lifecycle

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        let configuration = UpstreamProxyStore.shared.configuration
        self.isEnabled = configuration.isEnabled
        self.modeSummary = Self.modeSummary(for: configuration)
        observer = notificationCenter.addObserver(
            forName: .upstreamProxyConfigurationDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    // MARK: Internal

    @Published private(set) var isEnabled: Bool
    /// Which route new traffic takes while External Proxy is on, for example "HTTP 127.0.0.1:7890".
    @Published private(set) var modeSummary: String?

    /// `nil` when External Proxy is off. Never includes credentials: the PAC URL is reduced to its host.
    static func modeSummary(for configuration: UpstreamProxyConfiguration) -> String? {
        guard configuration.isEnabled else {
            return nil
        }
        switch configuration.type {
        case .automatic:
            if let host = configuration.resolvedPACURL?.host() {
                return String(localized: "Automatic (PAC from \(host))", bundle: RockxyLocalization.bundle)
            }
            return String(localized: "Automatic (PAC)", bundle: RockxyLocalization.bundle)
        case .http,
             .https,
             .socks5:
            let host = configuration.host.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(configuration.type.displayName) \(host):\(String(configuration.port))"
        }
    }

    func refresh() {
        let configuration = UpstreamProxyStore.shared.configuration
        isEnabled = configuration.isEnabled
        modeSummary = Self.modeSummary(for: configuration)
    }

    // MARK: Private

    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
}
