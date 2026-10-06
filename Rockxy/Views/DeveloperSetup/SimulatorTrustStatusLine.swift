import SwiftUI

// Live count of booted simulators and how many trust the Rockxy root.

// MARK: - SimulatorTrustStatusLine

/// Polls `simctl` while visible so the line follows simulators as they boot,
/// shut down, or are erased. Never creates a root certificate on its own.
struct SimulatorTrustStatusLine: View {
    // MARK: Internal

    let font: Font

    var body: some View {
        Text(summary ?? " ")
            .font(font)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("developerSetup.simulatorTrustStatus")
            .task {
                while !Task.isCancelled {
                    summary = await Self.currentSummary(installer: installer)
                    try? await Task.sleep(for: .seconds(3))
                }
            }
    }

    static func summary(booted: Int, trusted: Int, trustKnown: Bool) -> String {
        guard booted > 0 else {
            return String(
                localized: "No simulators are booted. Boot one from Xcode or the Simulator app.",
                bundle: RockxyLocalization.bundle
            )
        }
        let bootedText = String(AttributedString(
            localized: "^[\(booted) booted simulator](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
        guard trustKnown else {
            return bootedText
        }
        return String(
            localized: "\(bootedText) · \(String(trusted)) with the Rockxy certificate",
            bundle: RockxyLocalization.bundle
        )
    }

    // MARK: Private

    @State private var summary: String?

    private let installer = SimulatorCertificateInstaller()

    private static func currentSummary(installer: SimulatorCertificateInstaller) async -> String? {
        guard let simulators = try? await installer.bootedSimulators() else {
            return nil
        }
        guard let pem = try? await CertificateManager.shared.getRootCAPEM() else {
            return summary(booted: simulators.count, trusted: 0, trustKnown: false)
        }
        let statuses = installer.trustStatus(of: simulators, certificatePEM: pem)
        let trusted = statuses.values.filter { $0 == .trusted }.count
        let known = !statuses.values.contains(.unknown)
        return summary(booted: simulators.count, trusted: trusted, trustKnown: known)
    }
}
