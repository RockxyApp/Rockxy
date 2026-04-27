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
