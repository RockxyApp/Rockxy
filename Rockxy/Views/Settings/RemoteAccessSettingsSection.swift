import AppKit
import SwiftUI

// Access Control settings shown in Advanced Proxy Settings.

// MARK: - RemoteAccessSettings

/// Persisted Access Control mode and allowed device addresses. Every change is pushed
/// to `RemoteAccessGate` at once, so a running proxy applies it to the next connection
/// without a restart.
@MainActor @Observable
final class RemoteAccessSettings {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard, gate: RemoteAccessGate = .shared) {
        self.defaults = defaults
        self.gate = gate
        mode = defaults.string(forKey: Self.modeKey).flatMap(RemoteAccessMode.init(rawValue:)) ?? .allowAll
        allowedEntries = defaults.stringArray(forKey: Self.entriesKey) ?? []
        publish()
    }

    // MARK: Internal

    static let shared = RemoteAccessSettings()

    private(set) var mode: RemoteAccessMode
    private(set) var allowedEntries: [String]
    /// Devices refused in listed-devices mode since launch, newest first.
    private(set) var refusedAddresses: [String] = []

    static func isValidEntry(_ entry: String) -> Bool {
        RemoteAccessAddressRange(entry) != nil
    }

    func setMode(_ mode: RemoteAccessMode) {
        guard mode != self.mode else {
            return
        }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        publish()
    }

    /// Adds a trimmed address or CIDR range. Returns `false` for an invalid or duplicate entry.
    @discardableResult
    func addEntry(_ entry: String) -> Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEntry(trimmed), !allowedEntries.contains(trimmed) else {
            return false
        }
        allowedEntries.append(trimmed)
        refusedAddresses.removeAll { address in
            RemoteAccessAddressRange.addressBytes(address)
                .map { RemoteAccessAddressRange(trimmed)?.contains($0) == true }
                ?? false
        }
        persistEntries()
        return true
    }

    func removeEntry(_ entry: String) {
        allowedEntries.removeAll { $0 == entry }
        persistEntries()
    }

    func recordRefused(_ address: String) {
        refusedAddresses.removeAll { $0 == address }
        refusedAddresses.insert(address, at: 0)
        if refusedAddresses.count > Self.maxRefusedAddresses {
            refusedAddresses.removeLast(refusedAddresses.count - Self.maxRefusedAddresses)
        }
    }

    /// Reports refused devices back to the app and offers to allow each one.
    func activate() {
        guard !isActivated else {
            return
        }
        isActivated = true
        gate.onListedDeviceRefused = { address in
            Task { @MainActor in
                RemoteAccessSettings.shared.handleRefused(address)
            }
        }
    }

    // MARK: Private

    private static let modeKey = RockxyIdentity.current.defaultsKey("remoteAccessMode")
    private static let entriesKey = RockxyIdentity.current.defaultsKey("remoteAccessAllowedAddresses")
    private static let maxRefusedAddresses = 20

    private let defaults: UserDefaults
    private let gate: RemoteAccessGate
    private var isActivated = false
    private var promptedAddresses: Set<String> = []

    private func persistEntries() {
        defaults.set(allowedEntries, forKey: Self.entriesKey)
        publish()
    }

    private func publish() {
        gate.update(mode: mode, allowedEntries: allowedEntries)
    }

    private func handleRefused(_ address: String) {
        recordRefused(address)
        guard mode == .listedDevices, promptedAddresses.insert(address).inserted,
              let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else
        {
            return
        }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "Allow the device at \(address)?",
            bundle: RockxyLocalization.bundle
        )
        alert.informativeText = String(
            localized: "It tried to connect to Rockxy, which only accepts listed devices. Allowing it adds its address to Access Control in Advanced Proxy Settings.",
            bundle: RockxyLocalization.bundle
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Allow", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Keep Blocked", bundle: RockxyLocalization.bundle))
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            Task { @MainActor in
                RemoteAccessSettings.shared.addEntry(address)
            }
        }
    }
}

// MARK: - RemoteAccessSettingsSection

struct RemoteAccessSettingsSection: View {
    // MARK: Internal

    let listensOnlyOnLocalhost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            Text(String(localized: "Access Control", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.tableHeaderFont())

            Text(listensOnlyOnLocalhost
                ? String(
                    localized: "Rockxy only listens on localhost, so other devices can't connect. These settings apply when it listens on every interface.",
                    bundle: RockxyLocalization.bundle
                )
                : String(
                    localized: "Choose which other devices on your network can use the proxy. Connections from this Mac are always accepted.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(
                String(localized: "Remote devices", bundle: RockxyLocalization.bundle),
                selection: Binding(get: { settings.mode }, set: { settings.setMode($0) })
            ) {
                Text(String(localized: "Allow all devices", bundle: RockxyLocalization.bundle))
                    .tag(RemoteAccessMode.allowAll)
                Text(String(localized: "Allow only listed devices", bundle: RockxyLocalization.bundle))
                    .tag(RemoteAccessMode.listedDevices)
                Text(String(localized: "Block all other devices", bundle: RockxyLocalization.bundle))
                    .tag(RemoteAccessMode.disallowAll)
            }
            .pickerStyle(.radioGroup)
            .font(toolMetrics.font())

            if settings.mode == .listedDevices {
                allowedList
                refusedList
            }
        }
        .padding(toolMetrics.formHorizontalPadding)
        .advancedProxyPanelStyle()
    }

    // MARK: Private

    @State private var settings = RemoteAccessSettings.shared
    @State private var newEntry = ""
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var trimmedEntry: String {
        newEntry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var entryIsValid: Bool {
        RemoteAccessSettings.isValidEntry(trimmedEntry)
    }

    private var allowedList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(settings.allowedEntries, id: \.self) { entry in
                HStack(spacing: toolMetrics.controlSpacing) {
                    Text(entry)
                        .font(toolMetrics.font(monospaced: true))
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        settings.removeEntry(entry)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Remove", bundle: RockxyLocalization.bundle))
                    .accessibilityLabel(String(localized: "Remove \(entry)", bundle: RockxyLocalization.bundle))
                }
            }

            HStack(spacing: toolMetrics.controlSpacing) {
                TextField(
                    String(localized: "192.168.1.20 or 192.168.1.0/24", bundle: RockxyLocalization.bundle),
                    text: $newEntry
                )
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font(monospaced: true))
                .onSubmit(addEntry)
                .accessibilityLabel(String(
                    localized: "Device IP address or range",
                    bundle: RockxyLocalization.bundle
                ))
                Button(String(localized: "Add", bundle: RockxyLocalization.bundle), action: addEntry)
                    .controlSize(.small)
                    .disabled(!entryIsValid)
            }

            if !trimmedEntry.isEmpty, !entryIsValid {
                Text(String(
                    localized: "Enter an IPv4 or IPv6 address, or a range such as 10.0.0.0/8.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var refusedList: some View {
        if !settings.refusedAddresses.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Recently blocked", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))
                ForEach(settings.refusedAddresses, id: \.self) { address in
                    HStack(spacing: toolMetrics.controlSpacing) {
                        Text(address)
                            .font(toolMetrics.font(monospaced: true))
                        Spacer(minLength: 0)
                        Button(String(localized: "Allow", bundle: RockxyLocalization.bundle)) {
                            settings.addEntry(address)
                        }
                        .controlSize(.small)
                        .accessibilityLabel(String(localized: "Allow \(address)", bundle: RockxyLocalization.bundle))
                    }
                }
            }
        }
    }

    private func addEntry() {
        if settings.addEntry(trimmedEntry) {
            newEntry = ""
        }
    }
}
