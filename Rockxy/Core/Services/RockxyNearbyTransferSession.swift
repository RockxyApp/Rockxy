import Foundation

struct RockxyNearbyTransferSession: Codable {
    struct Metadata: Codable {
        var title: String
        var createdAt: String
        var appVersion: String?
        var deviceName: String?
    }

    struct Transaction: Codable {
        struct Message: Codable {
            struct Body: Codable {
                var size: Int
                var content: String?
            }

            var method: String?
            var url: String?
            var headers: [String: String]
            var body: Body?
            var statusCode: Int?
            var contentType: String?
        }

        struct Timing: Codable {
            var durationMs: Double
            var dnsMs: Double?
            var connectMs: Double?
            var tlsMs: Double?
            var ttfbMs: Double?
            var transferMs: Double?
        }

        var id: String
        var timestamp: String
        var request: Message
        var response: Message?
        var timing: Timing?
        var clientApp: String?
    }

    var version: String
    var metadata: Metadata
    var transactions: [Transaction]
}
