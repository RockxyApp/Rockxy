import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Tools ▸ Import / Export Settings: saves every debugging tool's rules to one file and imports
// such a file after the user chooses to add to or replace the current settings.

// MARK: - SettingsBackupFlow

@MainActor
enum SettingsBackupFlow {
    // MARK: Internal

    static func exportSettings(onlyEnabledRules: Bool) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Settings", bundle: RockxyLocalization.bundle)
        panel.message = onlyEnabledRules
            ? String(
                localized: "Save the rules that are turned on in every debugging tool.",
                bundle: RockxyLocalization.bundle
            )
            : String(
                localized: "Save the rules and switches of every debugging tool.",
                bundle: RockxyLocalization.bundle
            )
        panel.nameFieldStringValue = String(localized: "Rockxy Settings", bundle: RockxyLocalization.bundle) + ".json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task { @MainActor in
            let document = await SettingsBackupService.makeBackup(onlyEnabledRules: onlyEnabledRules)
            do {
                try write(document, to: url)
            } catch {
                showError(
                    String(localized: "The settings could not be exported.", bundle: RockxyLocalization.bundle),
                    error
                )
            }
        }
    }

    static func importSettings(proxyPort: Int) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Settings", bundle: RockxyLocalization.bundle)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let document: SettingsBackupDocument
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= SettingsBackupDocument.maxFileSize else {
                throw SettingsBackupError.tooLarge
            }
            document = try SettingsBackupDocument.decode(Data(contentsOf: url))
        } catch {
            showError(
                String(localized: "The settings could not be imported.", bundle: RockxyLocalization.bundle),
                error
            )
            return
        }
        guard let mode = confirmImport(document, fileName: url.lastPathComponent) else {
            return
        }
        Task { @MainActor in
            let report = await SettingsBackupService.importBackup(document, mode: mode, proxyPort: proxyPort)
            showReport(report)
        }
    }

    /// Writes the backup readable only by the current user; it can hold header values and bodies.
    static func write(_ document: SettingsBackupDocument, to url: URL) throws {
        try document.encoded().write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func summary(of document: SettingsBackupDocument) -> String {
        let settings = document.settings
        var parts: [String] = []
        func add(_ count: Int, _ text: String) {
            if count > 0 {
                parts.append(text)
            }
        }
        let rules = settings.rules.count
        add(rules, inflected("^[\(rules) rule](inflect: true)"))
        let hosts = (settings.sslProxying?.rules.count ?? 0) + (settings.sslProxying?.applicationRules.count ?? 0)
        add(hosts, inflected("^[\(hosts) HTTPS decryption entry](inflect: true)"))
        let allowed = settings.allowList?.rules.count ?? 0
        add(allowed, inflected("^[\(allowed) Allow List rule](inflect: true)"))
        let bypass = settings.bypassDomains.count
        add(bypass, inflected("^[\(bypass) bypassed domain](inflect: true)"))
        let reverse = settings.reverseProxies.count
        add(reverse, inflected("^[\(reverse) reverse proxy](inflect: true)"))
        let dns = settings.dnsSpoofing.count
        add(dns, inflected("^[\(dns) DNS Spoofing rule](inflect: true)"))
        let scripts = document.scripts.count
        add(scripts, inflected("^[\(scripts) script](inflect: true)"))
        guard !parts.isEmpty else {
            return String(localized: "The backup contains no rules.", bundle: RockxyLocalization.bundle)
        }
        let list = ListFormatter.localizedString(byJoining: parts)
        return String(localized: "The backup contains \(list).", bundle: RockxyLocalization.bundle)
    }

    // MARK: Private

    private static func inflected(_ text: String.LocalizationValue) -> String {
        String(AttributedString(
            localized: text,
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    private static func confirmImport(
        _ document: SettingsBackupDocument,
        fileName: String
    )
        -> SettingsBackupImportMode?
    {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Import settings from “\(fileName)”?", bundle: RockxyLocalization.bundle)
        var details = [summary(of: document)]
        details.append(String(
            localized: "Add them to your current settings, or replace your current rules and switches with the backup.",
            bundle: RockxyLocalization.bundle
        ))
        if !document.scripts.isEmpty {
            details.append(String(
                localized: "Imported scripts are added turned off. Review each script before you turn it on.",
                bundle: RockxyLocalization.bundle
            ))
        }
        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "Add to Current Settings", bundle: RockxyLocalization.bundle))
        let replace = alert.addButton(withTitle: String(
            localized: "Replace Current Settings",
            bundle: RockxyLocalization.bundle
        ))
        replace.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .append
        case .alertSecondButtonReturn: return .replace
        default: return nil
        }
    }

    private static func showReport(_ report: SettingsBackupImportReport) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Settings Imported", bundle: RockxyLocalization.bundle)
        var lines = [
            report.ruleCount > 0
                ? inflected("^[\(report.ruleCount) rule](inflect: true) imported.")
                : String(localized: "No new rules were added; the backup's rules are already here.", bundle: RockxyLocalization.bundle),
        ]
        if report.scriptCount > 0 {
            lines.append(inflected("^[\(report.scriptCount) script](inflect: true) added, turned off."))
        }
        if report.skippedCount > 0 {
            lines.append(inflected(
                "^[\(report.skippedCount) entry](inflect: true) skipped because it was invalid or conflicted with a current setting."
            ))
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.runModal()
    }

    private static func showError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

// MARK: - SettingsBackupMenu

/// Tools ▸ Import / Export Settings submenu.
struct SettingsBackupMenu: View {
    var body: some View {
        Menu(String(localized: "Import / Export Settings", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Export Settings…", bundle: RockxyLocalization.bundle)) {
                SettingsBackupFlow.exportSettings(onlyEnabledRules: false)
            }
            Button(String(localized: "Export Enabled Rules Only…", bundle: RockxyLocalization.bundle)) {
                SettingsBackupFlow.exportSettings(onlyEnabledRules: true)
            }
            Divider()
            Button(String(localized: "Import Settings…", bundle: RockxyLocalization.bundle)) {
                SettingsBackupFlow.importSettings(proxyPort: AppSettingsManager.shared.settings.proxyPort)
            }
        }
    }
}
