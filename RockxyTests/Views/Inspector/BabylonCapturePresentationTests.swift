import Foundation
@testable import Rockxy
import Testing

struct BabylonCapturePresentationTests {
    @Test("Inspector shows a captured Babylon error when no code was provided")
    func capturedErrorWithoutCodeRemainsVisible() throws {
        let base = BabylonCaptureMetadata(
            identity: BabylonCaptureIdentity(
                clientID: "client",
                sessionID: "transport",
                projectName: "Example",
                bundleIdentifier: "com.example.app",
                deviceName: "iPhone",
                deviceModel: "iPhone 17"
            ),
            capabilities: nil,
            correlation: nil,
            error: nil,
            compatibilityDiagnostics: []
        )
        var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        encoded["errorDomain"] = "NSURLErrorDomain"
        encoded["errorMessage"] = "TLS handshake failed"
        encoded["failurePhase"] = "response"
        let metadata = try JSONDecoder().decode(
            BabylonCaptureMetadata.self,
            from: JSONSerialization.data(withJSONObject: encoded)
        )

        let capturedError = try #require(BabylonCaptureErrorPresentation.field(from: metadata))

        #expect(capturedError.value.contains("NSURLErrorDomain"))
        #expect(capturedError.value.contains("response"))
        #expect(capturedError.value.contains("TLS handshake failed"))

        encoded.removeValue(forKey: "errorDomain")
        encoded.removeValue(forKey: "errorMessage")
        let phaseOnly = try JSONDecoder().decode(
            BabylonCaptureMetadata.self,
            from: JSONSerialization.data(withJSONObject: encoded)
        )
        #expect(BabylonCaptureErrorPresentation.field(from: phaseOnly)?.value == "response")
        #expect(BabylonCaptureErrorPresentation.field(from: base) == nil)
    }
}
