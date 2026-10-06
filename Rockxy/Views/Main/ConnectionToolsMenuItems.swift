import SwiftUI

// MARK: - ConnectionToolsMenuItems

/// Tools menu items for Reverse Proxy, DNS Spoofing, TLS Key Log, and settings backup.
struct ConnectionToolsMenuItems: View {
    // MARK: Internal

    var body: some View {
        Button(String(localized: "Reverse Proxy…", bundle: RockxyLocalization.bundle)) {
            openWindow(id: "reverseProxy")
        }
        Button(String(localized: "DNS Spoofing…", bundle: RockxyLocalization.bundle)) {
            openWindow(id: "dnsSpoofing")
        }
        Button(String(localized: "TLS Key Log…", bundle: RockxyLocalization.bundle)) {
            openWindow(id: "tlsKeyLog")
        }

        SettingsBackupMenu()
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
}
