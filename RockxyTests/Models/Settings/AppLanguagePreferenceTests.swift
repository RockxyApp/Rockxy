import Foundation
@testable import Rockxy
import Testing

// MARK: - AppLanguagePreferenceTests

struct AppLanguagePreferenceTests {
    @Test("Available languages come from the app bundle and keep System Default first")
    func availableLanguagesAreBundleDriven() {
        let options = AppLanguagePreference.availableOptions(
            localizations: ["zh-Hans", "Base", "en", "fr", "en"],
            displayLocale: Locale(identifier: "en")
        )

        #expect(options.first?.id == AppLanguageOption.systemID)
        #expect(Set(options.dropFirst().map(\.id)) == ["en", "fr", "zh-Hans"])
        #expect(options.count == 4)
        #expect(options.dropFirst().allSatisfy { !$0.nativeDisplayName.isEmpty })
    }

    @Test("Language identifiers use Bundle fallback matching")
    func languageIdentifiersUseBundleFallbackMatching() {
        let available = ["en", "zh-Hans"]

        #expect(AppLanguagePreference.resolvedLocalizationID(
            optionID: AppLanguageOption.systemID,
            availableLocalizations: available,
            preferredLanguages: ["zh-CN"]
        ) == "zh-Hans")
        #expect(AppLanguagePreference.resolvedLocalizationID(
            optionID: "en-GB",
            availableLocalizations: available
        ) == "en")
    }

    @Test("Applying a language writes and removes Rockxy's app preference")
    func applyingLanguagePersistsAppPreference() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "AppLanguagePreferenceTests.")
        let defaultsKey = "selectedLanguage"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppLanguagePreference.apply(
            optionID: "zh-Hans",
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ))
        #expect(defaults.string(forKey: defaultsKey) == "zh-Hans")
        #expect(AppLanguagePreference.selectedOptionID(
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ) == "zh-Hans")

        #expect(AppLanguagePreference.apply(
            optionID: AppLanguageOption.systemID,
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ))
        #expect(defaults.object(forKey: defaultsKey) == nil)
    }

    @Test("System Default removes a stale app-specific AppleLanguages override")
    func systemDefaultRemovesAppLanguageOverride() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "AppLanguagePreferenceTests.")
        let defaultsKey = "selectedLanguage"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["zh-Hans"], forKey: AppLanguagePreference.appleLanguagesDefaultsKey)

        #expect(AppLanguagePreference.apply(
            optionID: AppLanguageOption.systemID,
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ))
        #expect(
            defaults.persistentDomain(forName: suiteName)?[AppLanguagePreference.appleLanguagesDefaultsKey] == nil
        )
    }

    @Test("Unsupported language identifiers are rejected without replacing the current choice")
    func unsupportedLanguageIsRejected() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "AppLanguagePreferenceTests.")
        let defaultsKey = "selectedLanguage"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("en", forKey: defaultsKey)

        #expect(!AppLanguagePreference.apply(
            optionID: "de",
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ))
        #expect(defaults.string(forKey: defaultsKey) == "en")
    }

    @MainActor
    @Test("The runtime controller changes string catalogs without relaunching the app")
    func runtimeControllerChangesLanguageImmediately() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "AppLanguagePreferenceTests.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = AppLanguageController(
            defaults: defaults,
            bundle: .main,
            defaultsKey: "selectedLanguage"
        )

        #expect(controller.select(optionID: "zh-Hans"))
        #expect(String(localized: "General", bundle: controller.localizedBundle) == "通用")

        #expect(controller.select(optionID: "en"))
        #expect(String(localized: "General", bundle: controller.localizedBundle) == "General")
    }

    @MainActor
    @Test("System Default keeps the Mac's full locale while an explicit choice pins the language")
    func systemDefaultLocaleFollowsTheMac() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "AppLanguagePreferenceTests.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = AppLanguageController(
            defaults: defaults,
            bundle: .main,
            defaultsKey: "selectedLanguage"
        )

        // System Default must not collapse the environment locale onto a
        // region-less language locale; regional formatting follows the Mac.
        #expect(controller.locale.identifier == Locale.current.identifier)

        // An explicit choice changes the language and keeps the Mac's region formats.
        #expect(controller.select(optionID: "en"))
        #expect(controller.locale.language.languageCode == .english)
        #expect(controller.locale.region == Locale.current.region)
        #expect(controller.locale.decimalSeparator == Locale.current.decimalSeparator)
        #expect(controller.locale.hourCycle == Locale.current.hourCycle)

        #expect(controller.select(optionID: AppLanguageOption.systemID))
        #expect(controller.locale.identifier == Locale.current.identifier)
    }

    @Test("An explicit language keeps the region's number, clock, and week formats")
    func explicitLanguageKeepsRegionalFormats() {
        let germany = Locale(identifier: "de_DE")
        let chinese = AppLanguagePreference.formattingLocale(languageIdentifier: "zh-Hans", regionalBase: germany)
        #expect(chinese.language.languageCode == .chinese)
        #expect(chinese.decimalSeparator == ",")
        #expect(chinese.groupingSeparator == ".")
        #expect(chinese.hourCycle == germany.hourCycle)
        #expect(chinese.firstDayOfWeek == .monday)
        #expect(12_345.formatted(.number.locale(chinese)) == "12.345")

        let unitedStates = Locale(identifier: "en_US")
        let vietnamese = AppLanguagePreference.formattingLocale(languageIdentifier: "vi", regionalBase: unitedStates)
        #expect(vietnamese.language.languageCode == .vietnamese)
        #expect(vietnamese.decimalSeparator == ".")
        #expect(vietnamese.hourCycle == unitedStates.hourCycle)
        #expect(vietnamese.firstDayOfWeek == .sunday)
    }

    @MainActor
    @Test("System Default ignores a stale Chinese process preference and follows the Mac")
    func systemDefaultUsesGlobalMacLanguageOrder() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "AppLanguagePreferenceTests.")
        let defaultsKey = "selectedLanguage"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("zh-Hans", forKey: defaultsKey)
        defaults.set(["zh-Hans"], forKey: AppLanguagePreference.appleLanguagesDefaultsKey)
        let controller = AppLanguageController(
            defaults: defaults,
            bundle: .main,
            defaultsKey: defaultsKey,
            systemPreferredLanguages: ["en-VN", "zh-Hans-VN"]
        )

        #expect(String(localized: "General", bundle: controller.localizedBundle) == "通用")

        #expect(controller.select(optionID: AppLanguageOption.systemID))
        #expect(String(localized: "General", bundle: controller.localizedBundle) == "General")
        #expect(controller.locale.identifier == Locale.current.identifier)
    }
}
