import Foundation
@testable import Rockxy
import Testing

// Regression tests for `Storage` in the core storage layer.

// MARK: - InMemorySessionBufferTests

struct InMemorySessionBufferTests {
    @Test("append and retrieve by ID")
    func appendAndRetrieve() async {
        let buffer = InMemorySessionBuffer()
        let transaction = TestFixtures.makeTransaction()

        await buffer.append(transaction)
        let retrieved = await buffer.transaction(for: transaction.id)

        #expect(retrieved != nil)
        #expect(retrieved?.id == transaction.id)
    }

    @Test("count increments on append")
    func countIncrementsOnAppend() async {
        let buffer = InMemorySessionBuffer()

        await buffer.append(TestFixtures.makeTransaction(url: "https://example.com/1"))
        await buffer.append(TestFixtures.makeTransaction(url: "https://example.com/2"))
        await buffer.append(TestFixtures.makeTransaction(url: "https://example.com/3"))

        let count = await buffer.count
        #expect(count == 3)
    }

    @Test("clear resets buffer")
    func clearResetsBuffer() async {
        let buffer = InMemorySessionBuffer()

        await buffer.append(TestFixtures.makeTransaction())
        await buffer.append(TestFixtures.makeTransaction())
        await buffer.clear()

        let count = await buffer.count
        let all = await buffer.allTransactions()
        #expect(count == 0)
        #expect(all.isEmpty)
    }

    @Test("eviction at capacity limit")
    func evictionAtCapacity() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)

        for i in 0 ..< 110 {
            await buffer.append(
                TestFixtures.makeTransaction(url: "https://example.com/\(i)")
            )
        }

        let count = await buffer.count
        #expect(count <= 100)
    }

    @Test("allTransactions preserves insertion order")
    func allTransactionsPreservesOrder() async {
        let buffer = InMemorySessionBuffer()
        var ids: [UUID] = []

        for i in 0 ..< 5 {
            let transaction = TestFixtures.makeTransaction(url: "https://example.com/\(i)")
            ids.append(transaction.id)
            await buffer.append(transaction)
        }

        let all = await buffer.allTransactions()
        let retrievedIds = all.map(\.id)
        #expect(retrievedIds == ids)
    }

    @Test("duplicate ID overwrites existing entry")
    func duplicateIdOverwrites() async {
        let buffer = InMemorySessionBuffer()
        let transaction = TestFixtures.makeTransaction(statusCode: 200)

        await buffer.append(transaction)
        transaction.response = TestFixtures.makeResponse(statusCode: 404)
        await buffer.append(transaction)

        let count = await buffer.count
        let retrieved = await buffer.transaction(for: transaction.id)
        #expect(count == 1)
        #expect(retrieved?.response?.statusCode == 404)
    }
}

// MARK: - AppSettingsStorageTests

struct AppSettingsStorageTests {
    // MARK: Internal

    @Test("save and load roundtrip preserves values")
    func saveAndLoadRoundtrip() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        var settings = AppSettings()
        settings.proxyPort = Self.testPort
        settings.autoStartProxy = true
        settings.recordOnLaunch = false
        settings.onlyListenOnLocalhost = false
        settings.listenIPv6 = true
        settings.autoSelectPort = true
        settings.appTheme = .dark
        settings.appUI = AppUISettings(
            fontSize: 20,
            tabWidth: 4,
            useMonospacedFont: true,
            bodyWordWrap: false,
            bodyShowInvisibles: true,
            bodyShowMinimap: true,
            bodyScrollBeyondLastLine: true
        )
        settings.appUI.useAlternatingRowBackgroundColors = false
        settings.lastExportedRootCAPath = "/tmp/RockxyRootCA.pem"

        AppSettingsStorage.save(settings)
        let loaded = AppSettingsStorage.load()

        #expect(loaded.proxyPort == Self.testPort)
        #expect(loaded.autoStartProxy == true)
        #expect(loaded.recordOnLaunch == false)
        #expect(loaded.onlyListenOnLocalhost == false)
        #expect(loaded.listenIPv6 == true)
        #expect(loaded.autoSelectPort == true)
        #expect(loaded.appTheme == .dark)
        #expect(loaded.appUI.fontSize == 20)
        #expect(loaded.appUI.tabWidth == 4)
        #expect(loaded.appUI.useMonospacedFont == true)
        #expect(loaded.appUI.bodyWordWrap == false)
        #expect(loaded.appUI.bodyShowInvisibles == true)
        #expect(loaded.appUI.bodyShowMinimap == true)
        #expect(loaded.appUI.bodyScrollBeyondLastLine == true)
        #expect(loaded.appUI.useAlternatingRowBackgroundColors == false)
        #expect(loaded.lastExportedRootCAPath == "/tmp/RockxyRootCA.pem")

        settings.lastExportedRootCAPath = nil
        AppSettingsStorage.save(settings)
        let reloaded = AppSettingsStorage.load()
        #expect(reloaded.lastExportedRootCAPath == nil)
    }

    @Test("default values match AppSettings initializer")
    func defaultValues() {
        let defaultSettings = AppSettings()
        #expect(defaultSettings.proxyPort == Self.defaultPort)
        #expect(defaultSettings.recordOnLaunch == true)
        #expect(defaultSettings.onlyListenOnLocalhost == true)
        #expect(defaultSettings.autoStartProxy == false)
        #expect(defaultSettings.listenIPv6 == false)
        #expect(defaultSettings.autoSelectPort == true)
        #expect(defaultSettings.appTheme == .system)
        #expect(defaultSettings.appUI == .default)
        #expect(defaultSettings.appUI.fontSize == 13)
        #expect(defaultSettings.lastExportedRootCAPath == nil)
    }

    @Test("missing appearance font size key loads new readable default")
    func missingAppearanceFontSizeKeyLoadsDefault() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        UserDefaults.standard.removeObject(forKey: RockxyIdentity.current.defaultsKey("appearance.fontSize"))

        let loaded = AppSettingsStorage.load()

        #expect(loaded.appUI.fontSize == 13)
    }

    @Test("explicit compact appearance font size is respected")
    func explicitCompactAppearanceFontSizeIsRespected() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        UserDefaults.standard.set(12, forKey: RockxyIdentity.current.defaultsKey("appearance.fontSize"))

        let loaded = AppSettingsStorage.load()

        #expect(loaded.appUI.fontSize == 12)
    }

    @Test("appearance settings reject invalid stored menu values")
    func invalidAppearanceStoredValuesFallBackToDefaults() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        let defaults = UserDefaults.standard
        defaults.set("neon", forKey: RockxyIdentity.current.defaultsKey("appTheme"))
        defaults.set(99, forKey: RockxyIdentity.current.defaultsKey("appearance.fontSize"))
        defaults.set(3, forKey: RockxyIdentity.current.defaultsKey("appearance.tabWidth"))

        let loaded = AppSettingsStorage.load()

        #expect(loaded.appTheme == .system)
        #expect(loaded.appUI.fontSize == AppUISettings.defaultFontSize)
        #expect(loaded.appUI.tabWidth == AppUISettings.defaultTabWidth)
    }

    @Test("appearance persistence updates only appearance values")
    func appearancePersistenceUpdatesOnlyAppearanceValues() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        var settings = AppSettings()
        settings.proxyPort = 8_181
        settings.recordOnLaunch = false
        settings.githubGistAskBeforePublishing = false
        AppSettingsStorage.save(settings)

        var appUI = AppUISettings.default
        appUI.fontSize = 20
        appUI.tabWidth = 4
        appUI.useMonospacedFont = true
        AppSettingsStorage.saveAppearance(appTheme: .dark, appUI: appUI)

        let loaded = AppSettingsStorage.load()

        #expect(loaded.proxyPort == 8_181)
        #expect(loaded.recordOnLaunch == false)
        #expect(loaded.githubGistAskBeforePublishing == false)
        #expect(loaded.appTheme == .dark)
        #expect(loaded.appUI.fontSize == 20)
        #expect(loaded.appUI.tabWidth == 4)
        #expect(loaded.appUI.useMonospacedFont == true)
    }

    @MainActor
    @Test("appearance manager split state stays coherent with settings snapshot")
    func appearanceManagerSplitStateStaysCoherentWithSettingsSnapshot() {
        let cleanup = installSettingsTestGuard()
        let originalSettings = AppSettingsManager.shared.settings
        defer {
            AppSettingsManager.shared.settings = originalSettings
            cleanup()
        }

        var settings = AppSettings()
        settings.appTheme = .light
        settings.appUI.fontSize = 12
        AppSettingsManager.shared.settings = settings

        #expect(AppSettingsManager.shared.appTheme == .light)
        #expect(AppSettingsManager.shared.appUI.fontSize == 12)

        var updatedUI = AppSettingsManager.shared.appUI
        updatedUI.fontSize = 20
        AppSettingsManager.shared.updateAppUI(updatedUI)
        AppSettingsManager.shared.updateAppTheme(.dark)

        #expect(AppSettingsManager.shared.appUI.fontSize == 20)
        #expect(AppSettingsManager.shared.settings.appUI.fontSize == 20)
        #expect(AppSettingsManager.shared.appTheme == .dark)
        #expect(AppSettingsManager.shared.settings.appTheme == .dark)
    }

    @MainActor
    @Test("restore appearance defaults resets only appearance values")
    func restoreAppearanceDefaults() {
        let cleanup = installSettingsTestGuard()
        defer {
            AppSettingsManager.shared.settings = AppSettingsStorage.load()
            cleanup()
        }

        var settings = AppSettings()
        settings.proxyPort = 8_181
        settings.appTheme = .dark
        settings.appUI = AppUISettings(
            fontSize: 24,
            tabWidth: 4,
            useMonospacedFont: true,
            bodyWordWrap: false,
            bodyShowInvisibles: true,
            bodyShowMinimap: true,
            bodyScrollBeyondLastLine: true
        )
        settings.appUI.useAlternatingRowBackgroundColors = false
        AppSettingsManager.shared.settings = settings

        AppSettingsManager.shared.restoreAppearanceDefaults()

        #expect(AppSettingsManager.shared.settings.proxyPort == 8_181)
        #expect(AppSettingsManager.shared.settings.appTheme == .system)
        #expect(AppSettingsManager.shared.settings.appUI == .default)
        #expect(AppSettingsManager.shared.settings.appUI.fontSize == 13)
    }

    // MARK: Private

    // swiftlint:disable:next number_separator
    private static let testPort = 8_888
    // swiftlint:disable:next number_separator
    private static let defaultPort = 9_090
}
