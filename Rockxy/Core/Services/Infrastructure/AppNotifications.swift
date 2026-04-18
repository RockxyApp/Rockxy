import Foundation

/// Application-wide `NotificationCenter` names for cross-component communication.
/// Used where direct dependency injection would create tight coupling between
/// the proxy engine, certificate manager, session buffer, and UI layers.
extension Notification.Name {
    private static let identity = RockxyIdentity.current

    static let proxyDidStart = identity.notificationName("proxyDidStart")
    static let proxyDidStop = identity.notificationName("proxyDidStop")
    static let systemProxyDidChange = identity.notificationName("systemProxyDidChange")
    static let certificateStatusChanged = identity.notificationName("certificateStatusChanged")
    static let helperStatusChanged = identity.notificationName("helperStatusChanged")
    static let sessionCleared = identity.notificationName("sessionCleared")
    static let bufferEvictionRequested = identity.notificationName("bufferEvictionRequested")
    static let showCertificateWizard = identity.notificationName("showCertificateWizard")
    static let welcomeDidComplete = identity.notificationName("welcomeDidComplete")
    static let showWelcomeSheet = identity.notificationName("showWelcomeSheet")
    static let systemProxyVPNWarning = identity.notificationName("systemProxyVPNWarning")
    static let rootCANotTrusted = identity.notificationName("rootCANotTrusted")
    static let tlsMitmRejected = identity.notificationName("tlsMitmRejected")
    static let bypassProxyListDidChange = identity.notificationName("bypassProxyListDidChange")
    static let breakpointHit = identity.notificationName("breakpointHit")
    static let rulesDidChange = identity.notificationName("rulesDidChange")
    static let openDiffWindow = identity.notificationName("openDiffWindow")
    static let openComposeWindow = identity.notificationName("openComposeWindow")
    static let openBlockListWindow = identity.notificationName("openBlockListWindow")
    static let openAllowListWindow = identity.notificationName("openAllowListWindow")
    static let openMapLocalWindow = identity.notificationName("openMapLocalWindow")
    static let openMapRemoteWindow = identity.notificationName("openMapRemoteWindow")
    static let openNetworkConditionsWindow = identity.notificationName("openNetworkConditionsWindow")
    static let openBreakpointRulesWindow = identity.notificationName("openBreakpointRulesWindow")
    static let openScriptingListWindow = identity.notificationName("openScriptingListWindow")
    static let openScriptEditorWindow = identity.notificationName("openScriptEditorWindow")
    static let mcpServerDidStart = identity.notificationName("mcpServerDidStart")
    static let mcpServerDidStop = identity.notificationName("mcpServerDidStop")
}
