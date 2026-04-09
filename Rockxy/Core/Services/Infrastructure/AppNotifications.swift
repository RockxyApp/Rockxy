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
    static let allowListDidChange = identity.notificationName("allowListDidChange")
    static let breakpointHit = identity.notificationName("breakpointHit")
    static let breakpointRuleCreated = identity.notificationName("breakpointRuleCreated")
    static let rulesDidChange = identity.notificationName("rulesDidChange")
    static let openDiffWindow = identity.notificationName("openDiffWindow")
    static let openComposeWindow = identity.notificationName("openComposeWindow")
    static let openBlockListWindow = identity.notificationName("openBlockListWindow")
    static let openMapLocalWindow = identity.notificationName("openMapLocalWindow")
    static let openMapRemoteWindow = identity.notificationName("openMapRemoteWindow")
    static let openNetworkConditionsWindow = identity.notificationName("openNetworkConditionsWindow")
}
