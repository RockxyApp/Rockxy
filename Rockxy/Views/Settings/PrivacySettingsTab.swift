import AppKit
import SwiftUI

/// Privacy settings showing honest disclosure about data storage, exports, and telemetry.
struct PrivacySettingsTab: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Local Traffic Storage"))
                                .font(.system(size: 13, weight: .medium))
                            Text(
                                String(
                                    localized: "All captured HTTP/HTTPS requests, responses, headers, and bodies are stored in an unencrypted SQLite database on your Mac."
                                )
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            Text("~/Library/Application Support/Rockxy/rockxy.sqlite3")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "internaldrive")
                    }

                    Divider()

                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Large Response Bodies"))
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "Responses larger than 1 MB are saved as separate files."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("~/Library/Application Support/Rockxy/bodies/")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
            } header: {
                Text(String(localized: "Data Storage"))
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Exports Contain Full Traffic Data"))
                            .font(.system(size: 13, weight: .medium))
                        Text(
                            String(
                                localized: """
                                HAR and session exports include all captured headers, cookies, \
                                authorization tokens, and request/response bodies. Review exports \
                                before sharing.
                                """
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            } header: {
                Text(String(localized: "Exports & Sharing"))
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "No Telemetry"))
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "No Data Collected"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                        Text(
                            String(
                                localized: "Rockxy does not collect analytics or crash reports. No data is sent to external servers. All captured traffic stays on your machine."
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                }
            } header: {
                Text(String(localized: "Analytics & Telemetry"))
            }

            Button(String(localized: "Privacy Policy")) {
                if let url = URL(string: "https://github.com/LocNguyenHuu/Rockxy/wiki/Privacy") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
        .formStyle(.grouped)
    }
}
