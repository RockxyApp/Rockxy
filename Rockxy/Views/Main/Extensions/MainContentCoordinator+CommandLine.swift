import Foundation

// Extends `MainContentCoordinator` with the actions `rockxy-cli` can run.

// MARK: - MainContentCoordinator + CommandLineControlTarget

extension MainContentCoordinator: CommandLineControlTarget {
    var cliIsProxyRunning: Bool {
        isProxyRunning
    }

    var cliProxyPort: Int {
        isProxyRunning ? activeProxyPort : AppSettingsManager.shared.settings.proxyPort
    }

    var cliIsRecording: Bool {
        isRecording
    }

    var cliIsSystemProxyOn: Bool {
        isSystemProxyConfigured
    }

    func cliStartProxy() {
        if canStartProxy {
            startProxy()
        }
    }

    func cliStopProxy() {
        if isProxyRunning {
            stopProxy()
        }
    }

    func cliSetSystemProxy(_ isOn: Bool) {
        if isOn, !isSystemProxyConfigured {
            switchOnSystemProxyOverride()
        } else if !isOn, isSystemProxyConfigured {
            switchOffSystemProxyOverride()
        }
    }

    func cliSetRecording(_ isRecording: Bool) {
        _ = mcpSetRecording(isRecording)
    }

    func cliClearSession() async {
        await clearSession()
    }

    func cliSetTool(_ tool: CommandLineTool, enabled: Bool) async {
        let gate = RulePolicyGate.shared
        switch tool {
        case .breakpoint: await gate.setBreakpointToolEnabled(enabled)
        case .maplocal: await gate.setMapLocalToolEnabled(enabled)
        case .mapremote: await gate.setMapRemoteToolEnabled(enabled)
        case .blocklist: await gate.setBlockListToolEnabled(enabled)
        case .networkconditions: await gate.setNetworkConditionsToolEnabled(enabled)
        case .modifyheaders: await gate.setModifyHeaderToolEnabled(enabled)
        case .allowlist: AllowListManager.shared.setActive(enabled)
        case .nocaching: UserDefaults.standard.set(enabled, forKey: NoCacheHeaderMutator.userDefaultsKey)
        case .scripting:
            var settings = AppSettingsStorage.load()
            settings.scriptingToolEnabled = enabled
            AppSettingsStorage.save(settings)
        }
    }

    func cliTransactions() -> [HTTPTransaction] {
        transactions
    }

    func cliWriteSession(_ transactions: [HTTPTransaction], to url: URL) throws {
        let metadata = SessionSerializer.makeMetadata(
            transactionCount: transactions.count,
            captureStartDate: transactions.first?.timestamp,
            captureEndDate: transactions.last?.timestamp
        )
        try SessionSerializer.serialize(transactions: transactions, logEntries: [], metadata: metadata)
            .write(to: url, options: .atomic)
    }
}
