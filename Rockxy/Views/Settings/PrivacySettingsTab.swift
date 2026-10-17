import AppKit
import SwiftUI

/// Privacy settings showing honest disclosure about data storage, exports, and telemetry.
struct PrivacySettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSection(String(localized: "Data Storage", bundle: RockxyLocalization.bundle)) {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Local Traffic Storage", bundle: RockxyLocalization.bundle))
                                .font(settingsMetrics.font(weight: .medium))
                            Text(
                                String(
                                    localized: """
                                    Captured traffic stays in memory for the current session and is \
                                    discarded when Rockxy quits. Flows you pin, save, or annotate are \
                                    stored in an unencrypted SQLite database on your Mac.
                                    """,
                                    bundle: RockxyLocalization.bundle
                                )
                            )
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            Text("~" + "/Library/Application Support/" + RockxyIdentity.current
                                .appSupportDirectoryName + "/rockxy.sqlite3")
                                .font(settingsMetrics.secondaryFont(monospaced: true))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "internaldrive")
                    }

                    Divider()

                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Large Response Bodies", bundle: RockxyLocalization.bundle))
                                .font(settingsMetrics.font(weight: .medium))
                            Text(String(
                                localized: "Stored request and response bodies larger than 1 MB are saved as separate files.",
                                bundle: RockxyLocalization.bundle
                            ))
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            Text("~" + "/Library/Application Support/" + RockxyIdentity.current
                                .appSupportDirectoryName + "/bodies/")
                                .font(settingsMetrics.secondaryFont(monospaced: true))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
            }

            SettingsSection(String(localized: "Exports & Sharing", bundle: RockxyLocalization.bundle)) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Exports Contain Full Traffic Data", bundle: RockxyLocalization.bundle))
                            .font(settingsMetrics.font(weight: .medium))
                        Text(
                            String(
                                localized: """
                                HAR, session, and Gist exports can include captured headers, cookies, \
                                authorization tokens, request/response bodies, and Babylon source, device, \
                                session, trace, and timing metadata when present. Review exports \
                                before sharing or publishing.
                                """, bundle: RockxyLocalization.bundle
                            )
                        )
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            SettingsSection(String(localized: "Analytics & Telemetry", bundle: RockxyLocalization.bundle)) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "No Telemetry", bundle: RockxyLocalization.bundle))
                                .font(settingsMetrics.font(weight: .medium))
                            Text(String(localized: "No Data Collected", bundle: RockxyLocalization.bundle))
                                .font(settingsMetrics.metadataFont(weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .rockxyChipStyle(tint: .green, isActive: true)
                        }
                        Text(
                            String(
                                localized: """
                                Rockxy does not collect analytics or crash reports. Captured traffic stays on your \
                                machine unless you explicitly export, share, or publish it.
                                """, bundle: RockxyLocalization.bundle
                            )
                        )
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "Privacy Policy", bundle: RockxyLocalization.bundle)) {
                    if let url = URL(string: "https://www.rockxy.io/privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }
        .font(settingsMetrics.font())
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
