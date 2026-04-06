import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

// Application entry point. Declares the main window scene with `ContentView`,
// the macOS `Settings` scene, and the full set of custom menu bar commands.

// MARK: - AppLifecycleState

@MainActor @Observable
final class AppLifecycleState {
    var showWelcome = false
}

// MARK: - RockxyApp

@main
struct RockxyApp: App {
    // MARK: Internal

    private static let identity = RockxyIdentity.current

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Rockxy", id: "main") {
            MainWindowContent(lifecycleState: lifecycleState)
        }
        .commands {
            RockxyMenuCommands(lifecycleState: lifecycleState)
        }

        Window(String(localized: "Advanced Proxy Settings"), id: "advancedProxySettings") {
            AdvancedProxySettingsView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)

        Window(String(localized: "Map Local"), id: "mapLocal") {
            MapLocalWindowView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(String(localized: "Map Remote"), id: "mapRemote") {
            MapRemoteWindowView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Block List"), id: "blockList") {
            BlockListWindowView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Modify Headers"), id: "modifyHeaders") {
            ModifyHeaderWindowView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(String(localized: "Network Conditions"), id: "networkConditions") {
            NetworkConditionsWindowView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "SSL Proxying List"), id: "sslProxyingList") {
            SSLProxyingListView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(String(localized: "Bypass Proxy List"), id: "bypassProxyList") {
            BypassProxyListView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(String(localized: "Allow List"), id: "allowList") {
            AllowListView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(String(localized: "Diff"), id: "diff") {
            DiffWindowView()
        }
        .commandsRemoved()
        .defaultSize(width: 1_240, height: 820)
        .defaultPosition(.center)

        Window(String(localized: "Scripting"), id: "scripting") {
            ScriptingWindowView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(String(localized: "Custom Previewer Tabs"), id: "customPreviewerTabs") {
            CustomPreviewerTabView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(String(localized: "Custom Columns"), id: "customColumns") {
            CustomHeaderColumnsView()
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(String(localized: "Breakpoints"), id: "breakpoints") {
            BreakpointWindowView()
        }
        .commandsRemoved()
        .defaultSize(width: 800, height: 500)
        .defaultPosition(.center)

        composeWindow

        Settings {
            SettingsView()
        }
    }

    // MARK: Private

    @State private var lifecycleState = AppLifecycleState()

    private var composeWindow: some Scene {
        ComposeWindowScene()
    }
}

// MARK: - ComposeWindowScene

/// Compose window scene with restoration disabled on macOS 15+.
/// On macOS 14, the window may auto-restore on relaunch (acceptable degradation).
private struct ComposeWindowScene: Scene {
    // MARK: Internal

    var body: some Scene {
        composeWindow
    }

    // MARK: Private

    private var composeWindow: some Scene {
        let base = Window(String(localized: "Compose"), id: "compose") {
            ComposeWindowView()
        }
        .commandsRemoved()
        .defaultSize(width: 900, height: 600)
        .defaultPosition(.center)

        if #available(macOS 15.0, *) {
            return base.restorationBehavior(.disabled)
        } else {
            return base
        }
    }
}

// MARK: - MainWindowContent

private struct MainWindowContent: View {
    // MARK: Internal

    private static let identity = RockxyIdentity.current

    let lifecycleState: AppLifecycleState

    var body: some View {
        ContentView()
            .sheet(isPresented: Binding(
                get: { lifecycleState.showWelcome },
                set: { lifecycleState.showWelcome = $0 }
            )) {
                WelcomeView(isFirstLaunch: true, onComplete: {
                    lifecycleState.showWelcome = false
                })
            }
            .task {
                guard !setupChecked else {
                    return
                }
                setupChecked = true

                // Migration backfill: if all setup steps are already satisfied, mark onboarding complete
                if !onboardingCompletedOnce {
                    let certInstalled = await CertificateManager.shared.isRootCAInstalled()
                    let certTrusted = await CertificateManager.shared.isRootCATrusted()
                    let helperOK = HelperManager.shared.status == .installedCompatible
                    let proxyOK = SystemProxyManager.shared.isSystemProxyEnabled()
                    if certInstalled, certTrusted, helperOK, proxyOK {
                        onboardingCompletedOnce = true
                    }
                }

                if !onboardingCompletedOnce {
                    lifecycleState.showWelcome = true
                } else if showWelcomeOnLaunch {
                    lifecycleState.showWelcome = true
                }
            }
    }

    // MARK: Private

    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true
    @AppStorage(RockxyIdentity.current.defaultsKey("onboardingCompletedOnce")) private var onboardingCompletedOnce = false
    @State private var setupChecked = false
}

// MARK: - RockxyMenuCommands

/// Defines Rockxy's full menu bar structure: File (session/export), Edit (copy as cURL),
/// View (layout/tabs), Flow (replay/clear), Tools (proxy control), Diff, Scripting,
/// Certificate, and Help. Actions are dispatched via `MainContentCommandActions`
/// through the focused scene value pattern.
struct RockxyMenuCommands: Commands {
    // MARK: Internal

    let lifecycleState: AppLifecycleState

    var body: some Commands {
        appMenu
        fileMenu
        editMenu
        viewMenu
        flowMenu
        toolsMenu
        diffMenu
        scriptingMenu
        certificateMenu
        helpMenu
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.commandActions) private var actions: MainContentCommandActions?

    @AppStorage(NoCacheHeaderMutator.userDefaultsKey) private var isNoCachingEnabled = false

    @State private var certificateError: String?
    @State private var showCertificateAlert = false

    private var appMenu: some Commands {
        CommandGroup(before: .appSettings) {
            Button(String(localized: "Check for Updates…")) {}
                .disabled(true)
                .help(String(localized: "Planned for future release"))

            Button(String(localized: "Change Logs…")) {
                openURL("https://github.com/LocNguyenHuu/Rockxy/blob/main/CHANGELOG.md")
            }

            Divider()
        }
    }

    private var fileMenu: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Tab")) {
                actions?.newWorkspaceTab()
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button(String(localized: "Close Tab")) {
                actions?.closeWorkspaceTab()
            }
            .keyboardShortcut("w", modifiers: [.command])

            Button(String(localized: "New Session")) {
                actions?.clearSession()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Open Session…")) {
                actions?.openSession()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button(String(localized: "Save Session…")) {
                actions?.saveSession()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Import HAR…")) {
                actions?.importHAR()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button(String(localized: "Export HAR…")) {
                actions?.exportHAR()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    private var editMenu: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button(String(localized: "Copy URL")) {
                actions?.copyURL()
            }
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(actions?.hasSelectedTransaction != true)

            Button(String(localized: "Copy as cURL")) {
                actions?.copyAsCURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(actions?.hasSelectedTransaction != true)

            Button(String(localized: "Focus on URL")) {
                actions?.toggleFilterBar()
            }
            .keyboardShortcut("l", modifiers: [.command])
        }
    }

    private var viewMenu: some Commands {
        CommandGroup(after: .toolbar) {
            Button(String(localized: "Filter Domain or App")) {
                actions?.toggleFilterBar()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Auto Select the Latest Request")) {
                actions?.toggleAutoSelect()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Toggle Source List Panel")) {
                actions?.toggleSourceList()
            }
            .keyboardShortcut("[", modifiers: [.command, .control])

            Divider()

            Button(String(localized: "Toggle Dock to Bottom Window")) {
                actions?.toggleInspectorBottom()
            }
            .keyboardShortcut("]", modifiers: [.command, .control])

            Button(String(localized: "Toggle Dock to Right Window")) {
                actions?.toggleInspectorRight()
            }
            .keyboardShortcut("\\", modifiers: [.command, .control])

            Divider()

            Button(String(localized: "Select Next Tab")) {
                actions?.nextWorkspaceTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button(String(localized: "Select Previous Tab")) {
                actions?.previousWorkspaceTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }

    private var flowMenu: some Commands {
        CommandMenu(String(localized: "Flow")) {
            Button(String(localized: "Repeat")) {
                actions?.replayRequest()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(actions?.hasSelectedTransaction != true)

            Button(String(localized: "Edit and Repeat…")) {
                actions?.editAndRepeat()
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(actions?.hasSelectedTransaction != true)

            Divider()

            Button(String(localized: "Save Requests")) {
                actions?.saveSession()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Menu(String(localized: "Export")) {
                Button(String(localized: "Export as HAR…")) {
                    actions?.exportHAR()
                }
            }

            Divider()

            Button(String(localized: "Add Comment…")) {
                actions?.addComment()
            }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(actions?.hasSelectedTransaction != true)

            Menu(String(localized: "Highlight")) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button(color.rawValue.capitalized) {
                        actions?.setHighlight(color)
                    }
                }
                Divider()
                Button(String(localized: "Remove Highlight")) {
                    actions?.setHighlight(nil)
                }
            }
            .disabled(actions?.hasSelectedTransaction != true)

            Divider()

            Button(String(localized: "Clear Session")) {
                actions?.clearSession()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option, .shift])

            Divider()

            Button(String(localized: "Delete")) {
                actions?.deleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(actions?.hasSelectedTransaction != true)

            Button(String(localized: "Delete All")) {
                actions?.deleteAll()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }

    private var toolsMenu: some Commands {
        CommandMenu(String(localized: "Tools")) {
            Button(String(localized: "Start Proxy")) {
                actions?.startProxy()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions?.isProxyRunning == true)

            Button(String(localized: "Stop Proxy")) {
                actions?.stopProxy()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(actions?.isProxyRunning != true)

            Button(String(localized: "Toggle Recording")) {
                actions?.toggleRecording()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Toggle(String(localized: "No Caching"), isOn: $isNoCachingEnabled)

            Divider()

            Button(String(localized: "SSL Proxying List…")) {
                openWindow(id: "sslProxyingList")
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button(String(localized: "Bypass Proxy List…")) {
                openWindow(id: "bypassProxyList")
            }
            .keyboardShortcut("b", modifiers: [.command, .option])

            Button(String(localized: "Allow List…")) {
                openWindow(id: "allowList")
            }
            .keyboardShortcut("a", modifiers: [.command, .option])

            Button(String(localized: "Map Local…")) {
                openWindow(id: "mapLocal")
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Button(String(localized: "Map Remote…")) {
                openWindow(id: "mapRemote")
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button(String(localized: "Block List…")) {
                openWindow(id: "blockList")
            }
            .keyboardShortcut("[", modifiers: [.command, .option])

            Button(String(localized: "Modify Headers…")) {
                openWindow(id: "modifyHeaders")
            }

            Button(String(localized: "Network Conditions…")) {
                openWindow(id: "networkConditions")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button(String(localized: "Breakpoints…")) {
                openWindow(id: "breakpoints")
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Custom Previewer Tabs…")) {
                openWindow(id: "customPreviewerTabs")
            }

            Button(String(localized: "Custom Header Columns…")) {
                openWindow(id: "customColumns")
            }
        }
    }

    private var diffMenu: some Commands {
        CommandMenu(String(localized: "Diff")) {
            Button(String(localized: "Open Diff View…")) {
                openWindow(id: "diff")
            }
            .keyboardShortcut("y", modifiers: [.command, .option])

            Divider()

            Button(String(localized: "Compare Selected")) {
                actions?.compareSelected()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(actions?.canCompareSelected != true)
        }
    }

    private var scriptingMenu: some Commands {
        CommandMenu(String(localized: "Scripting")) {
            Button(String(localized: "Script List…")) {
                openWindow(id: "scripting")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    private var certificateMenu: some Commands {
        CommandMenu(String(localized: "Certificate")) {
            Button(String(localized: "Install on This Mac…")) {
                Task {
                    do {
                        try await CertificateManager.shared.installAndTrust()
                    } catch {
                        certificateError = error.localizedDescription
                        showCertificateAlert = true
                    }
                }
            }

            Button(String(localized: "Export Root Certificate…")) {
                Task {
                    do {
                        guard let pem = try await CertificateManager.shared.getRootCAPEM() else {
                            certificateError = String(localized: "No root certificate found. Install one first.")
                            showCertificateAlert = true
                            return
                        }
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "RockxyCA.pem"
                        panel.allowedContentTypes = [.init(filenameExtension: "pem")].compactMap { $0 }
                        let response = panel.runModal()
                        if response == .OK, let url = panel.url {
                            try pem.write(to: url, atomically: true, encoding: .utf8)
                        }
                    } catch {
                        certificateError = error.localizedDescription
                        showCertificateAlert = true
                    }
                }
            }
        }
    }

    private var helpMenu: some Commands {
        CommandGroup(replacing: .help) {
            Button(String(localized: "Getting Started…")) {
                openWindow(id: "main")
                lifecycleState.showWelcome = true
            }

            Divider()

            Button(String(localized: "Homepage…")) {
                openURL("https://rockxy.io")
            }

            Button(String(localized: "Github…")) {
                openURL("https://github.com/LocNguyenHuu/Rockxy")
            }

            Button(String(localized: "Technical Documents…")) {
                openURL("https://github.com/LocNguyenHuu/Rockxy/wiki")
            }

            Divider()

            Button(String(localized: "Report Bug…")) {
                openURL("https://github.com/LocNguyenHuu/Rockxy/issues")
            }

            Button(String(localized: "Copy Debug Info…")) {
                copyDebugInfo()
            }
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func copyDebugInfo() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let info = "Rockxy \(version) (\(build)) / macOS \(osVersion)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
}
