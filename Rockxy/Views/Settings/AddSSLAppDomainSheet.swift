import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AddSSLAppDomainSheet

/// Sheet for browsing running applications and their observed domains,
/// then adding selected domains to the SSL Proxying list.
/// When no observed domains are available for a selected app, the user
/// is prompted to enter a domain manually via the Add Domain sheet.
struct AddSSLAppDomainSheet: View {
    // MARK: Lifecycle

    init(onAdd: @escaping ([String]) -> Void) {
        self.onAdd = onAdd
    }

    // MARK: Internal

    let onAdd: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            searchSection
            Divider()
            listSection
            footerHint
            Divider()
            buttonBar
        }
        .frame(width: 500, height: 520)
        .onAppear { refreshRunningApps() }
        .sheet(isPresented: $showAddDomainSheet) {
            AddSSLDomainSheet { domain in
                onAdd([domain])
                dismiss()
            }
        }
    }

    // MARK: Private

    private struct RunningAppItem: Identifiable, Hashable {
        let id: String
        let name: String
        let bundleIdentifier: String?
        let icon: NSImage?

        static func == (lhs: RunningAppItem, rhs: RunningAppItem) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var runningApps: [RunningAppItem] = []
    @State private var selectedDomains: Set<String> = []
    @State private var showAddDomainSheet = false
    @FocusState private var isSearchFocused: Bool

    private var filteredApps: [RunningAppItem] {
        guard !searchText.isEmpty else {
            return runningApps
        }
        let query = searchText
        return runningApps.filter { app in
            app.name.localizedCaseInsensitiveContains(query)
                || (app.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var headerSection: some View {
        HStack {
            Text(String(localized: "Add favorite app or domain"))
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var searchSection: some View {
        HStack {
            TextField(
                String(localized: "Search app or domain"),
                text: $searchText,
                prompt: Text(String(localized: "Search app or domain (⌘⇧F)"))
            )
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .onAppear { isSearchFocused = true }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var listSection: some View {
        List {
            Section {
                ForEach(filteredApps) { app in
                    HStack(spacing: 8) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                        }

                        Text(app.name)
                            .font(.system(size: 12))
                            .lineLimit(1)

                        Spacer()

                        if let bundleID = app.bundleIdentifier {
                            Text(bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        showAddDomainSheet = true
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                    Text(String(localized: "Apps"))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(filteredApps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var footerHint: some View {
        HStack {
            Spacer()
            Text(String(localized: "Double-click an app or use Add Domain to enter a host pattern"))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var buttonBar: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(String(localized: "Add Domain…")) {
                showAddDomainSheet = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func refreshRunningApps() {
        let workspace = NSWorkspace.shared
        var seen = Set<String>()
        var apps: [RunningAppItem] = []

        for app in workspace.runningApplications {
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else {
                continue
            }
            let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
            let key = name.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)

            apps.append(RunningAppItem(
                id: app.bundleIdentifier ?? name,
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                icon: app.icon
            ))
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        runningApps = apps
    }
}
