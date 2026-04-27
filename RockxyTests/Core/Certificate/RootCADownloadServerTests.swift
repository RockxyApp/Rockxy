import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

// MARK: - RootCADownloadSessionTests

struct RootCADownloadSessionTests {
    @Test("valid token is accepted until expiry")
    func validTokenAcceptedUntilExpiry() throws {
        let now = Date()
        let session = try RootCADownloadSession.make(host: "192.168.1.10", port: 12_345, now: now, ttl: 600)

        #expect(session.validates(token: session.token, at: now.addingTimeInterval(599)))
        #expect(session.validates(token: session.token, at: now.addingTimeInterval(600)) == false)
        #expect(session.validates(token: "\(session.token)x", at: now) == false)
    }

    @Test("public URL includes token without storing private material")
    func publicURLIncludesToken() throws {
        let session = try RootCADownloadSession.make(host: "192.168.1.10", port: 12_345)

        #expect(session.publicURL.absoluteString.hasPrefix("http://192.168.1.10:12345/root-ca.pem?token="))
        #expect(session.publicURL.absoluteString.contains(session.token))
        #expect(session.publicURL.absoluteString.contains("PRIVATE KEY") == false)
    }
}

// MARK: - RootCAFingerprintVerifierTests

struct RootCAFingerprintVerifierTests {
    @Test("PEM fingerprint validation requires matching fingerprint")
    func pemFingerprintValidation() throws {
        let derData = Data([0x30, 0x03, 0x02, 0x01, 0x05])
        let pem = """
        -----BEGIN CERTIFICATE-----
        \(derData.base64EncodedString())
        -----END CERTIFICATE-----
        """
        let fingerprint = KeychainHelper.computeFingerprintSHA256(derData)

        #expect(try RootCAFingerprintVerifier.verifiedFingerprint(
            certificatePEM: pem,
            expectedFingerprint: fingerprint
        ) == fingerprint)
        do {
            _ = try RootCAFingerprintVerifier.verifiedFingerprint(
                certificatePEM: pem,
                expectedFingerprint: KeychainHelper.computeFingerprintSHA256(Data([0x01, 0x02, 0x03]))
            )
            Issue.record("Expected fingerprint mismatch to throw")
        } catch RootCAShareValidationError.fingerprintMismatch {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - RootCADownloadServerAddressTests

struct RootCADownloadServerAddressTests {
    @Test("LAN address ranking prefers physical interfaces over virtual interfaces")
    func lanAddressRankingPrefersPhysicalInterfaces() {
        let candidates = RootCADownloadServer.rankedLANIPv4AddressCandidates(from: [
            (interfaceName: "lo0", address: "127.0.0.1"),
            (interfaceName: "utun4", address: "100.64.0.2"),
            (interfaceName: "bridge100", address: "192.168.64.1"),
            (interfaceName: "en1", address: "192.168.1.20"),
            (interfaceName: "en0", address: "192.168.1.10"),
            (interfaceName: "vmnet8", address: "172.16.0.1"),
        ])

        #expect(candidates.map(\.interfaceName) == ["en0", "en1", "bridge100", "utun4", "vmnet8"])
        #expect(candidates.first?.address == "192.168.1.10")
    }

    @Test("LAN address ranking keeps fallback interfaces when no physical interface is available")
    func lanAddressRankingKeepsFallbackInterfaces() {
        let candidates = RootCADownloadServer.rankedLANIPv4AddressCandidates(from: [
            (interfaceName: "utun4", address: "100.64.0.2"),
            (interfaceName: "bridge100", address: "192.168.64.1"),
        ])

        #expect(candidates.map(\.address) == ["192.168.64.1", "100.64.0.2"])
    }
}

// MARK: - RootCADownloadResponderTests

struct RootCADownloadResponderTests {
    @Test("valid token returns public PEM with download headers")
    func validTokenReturnsPublicPEM() throws {
        let now = Date()
        let session = try RootCADownloadSession.make(host: "192.168.1.10", port: 12_345, now: now)
        let pem = """
        -----BEGIN CERTIFICATE-----
        public-test-cert
        -----END CERTIFICATE-----
        """

        let response = RootCADownloadResponder.response(
            method: .GET,
            uri: "/root-ca.pem?token=\(session.token)",
            session: session,
            certificatePEM: pem,
            now: now
        )

        #expect(response.status == .ok)
        #expect(header("Content-Type", in: response)?.contains("application/x-pem-file") == true)
        #expect(header("Content-Disposition", in: response) == "attachment; filename=\"RockxyRootCA.pem\"")
        #expect(header("Cache-Control", in: response) == "no-store")
        #expect(header("X-Content-Type-Options", in: response) == "nosniff")
        #expect(String(decoding: response.body, as: UTF8.self) == pem)
        #expect(String(decoding: response.body, as: UTF8.self).contains("PRIVATE KEY") == false)
    }

    @Test("invalid token is rejected as not found")
    func invalidTokenRejected() throws {
        let now = Date()
        let session = try RootCADownloadSession.make(host: "192.168.1.10", port: 12_345, now: now)

        let response = RootCADownloadResponder.response(
            method: .GET,
            uri: "/root-ca.pem?token=wrong",
            session: session,
            certificatePEM: "-----BEGIN CERTIFICATE-----",
            now: now
        )

        #expect(response.status == .notFound)
        #expect(header("Cache-Control", in: response) == "no-store")
    }

    @Test("expired token is rejected as gone")
    func expiredTokenRejected() throws {
        let now = Date()
        let session = try RootCADownloadSession.make(host: "192.168.1.10", port: 12_345, now: now, ttl: 10)

        let response = RootCADownloadResponder.response(
            method: .GET,
            uri: "/root-ca.pem?token=\(session.token)",
            session: session,
            certificatePEM: "-----BEGIN CERTIFICATE-----",
            now: now.addingTimeInterval(11)
        )

        #expect(response.status == .gone)
        #expect(String(decoding: response.body, as: UTF8.self).contains("expired"))
    }

    @Test("wrong method or path does not expose certificate")
    func wrongMethodOrPathRejected() throws {
        let now = Date()
        let session = try RootCADownloadSession.make(host: "192.168.1.10", port: 12_345, now: now)
        let pem = "-----BEGIN CERTIFICATE-----"

        let postResponse = RootCADownloadResponder.response(
            method: .POST,
            uri: "/root-ca.pem?token=\(session.token)",
            session: session,
            certificatePEM: pem,
            now: now
        )
        let pathResponse = RootCADownloadResponder.response(
            method: .GET,
            uri: "/not-root-ca.pem?token=\(session.token)",
            session: session,
            certificatePEM: pem,
            now: now
        )

        #expect(postResponse.status == .methodNotAllowed)
        #expect(pathResponse.status == .notFound)
        #expect(String(decoding: postResponse.body, as: UTF8.self).contains("BEGIN CERTIFICATE") == false)
        #expect(String(decoding: pathResponse.body, as: UTF8.self).contains("BEGIN CERTIFICATE") == false)
    }

    private func header(_ name: String, in response: RootCADownloadResponse) -> String? {
        response.headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }
}
