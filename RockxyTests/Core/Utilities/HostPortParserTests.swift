import Foundation
@testable import Rockxy
import Testing

struct HostPortParserTests {
    // MARK: - Valid Inputs

    @Test("Parses standard host:port")
    func standardHostPort() throws {
        let result = try HostPortParser.parse("example.com:443")
        #expect(result.host == "example.com")
        #expect(result.port == 443)
    }

    @Test("Parses host:port with non-standard port")
    func nonStandardPort() throws {
        let result = try HostPortParser.parse("api.example.com:8080")
        #expect(result.host == "api.example.com")
        #expect(result.port == 8_080)
    }

    @Test("Parses bare host with default port")
    func bareHostDefaultPort() throws {
        let result = try HostPortParser.parse("example.com")
        #expect(result.host == "example.com")
        #expect(result.port == 443)
    }

    @Test("Parses bare host with custom default port")
    func bareHostCustomDefault() throws {
        let result = try HostPortParser.parse("example.com", defaultPort: 80)
        #expect(result.host == "example.com")
        #expect(result.port == 80)
    }

    @Test("Parses IPv4 host:port")
    func ipv4HostPort() throws {
        let result = try HostPortParser.parse("192.168.1.1:9090")
        #expect(result.host == "192.168.1.1")
        #expect(result.port == 9_090)
    }

    @Test("Parses IPv6 bracket notation with port")
    func ipv6WithPort() throws {
        let result = try HostPortParser.parse("[::1]:8080")
        #expect(result.host == "::1")
        #expect(result.port == 8_080)
    }

    @Test("Parses IPv6 bracket notation without port")
    func ipv6WithoutPort() throws {
        let result = try HostPortParser.parse("[::1]")
        #expect(result.host == "::1")
        #expect(result.port == 443)
    }

    @Test("Parses full IPv6 address with port")
    func fullIPv6WithPort() throws {
        let result = try HostPortParser.parse("[2001:db8::1]:443")
        #expect(result.host == "2001:db8::1")
        #expect(result.port == 443)
    }

    @Test("Trims whitespace from URI")
    func trimsWhitespace() throws {
        let result = try HostPortParser.parse("  example.com:443  ")
        #expect(result.host == "example.com")
        #expect(result.port == 443)
    }

    @Test("Parses port 1 (minimum)")
    func minimumPort() throws {
        let result = try HostPortParser.parse("example.com:1")
        #expect(result.port == 1)
    }

    @Test("Parses port 65535 (maximum)")
    func maximumPort() throws {
        let result = try HostPortParser.parse("example.com:65535")
        #expect(result.port == 65_535)
    }

    // MARK: - Invalid Inputs

    @Test("Rejects empty URI")
    func emptyURI() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("")
        }
    }

    @Test("Rejects whitespace-only URI")
    func whitespaceOnlyURI() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("   ")
        }
    }

    @Test("Rejects empty host with port")
    func emptyHostWithPort() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse(":443")
        }
    }

    @Test("Rejects non-numeric port")
    func nonNumericPort() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("example.com:abc")
        }
    }

    @Test("Rejects port 0")
    func portZero() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("example.com:0")
        }
    }

    @Test("Rejects port 65536")
    func portTooHigh() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("example.com:65536")
        }
    }

    @Test("Rejects negative port")
    func negativePort() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("example.com:-1")
        }
    }

    @Test("Rejects host with control characters")
    func hostWithControlChars() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("example\u{0000}.com:443")
        }
    }

    @Test("Rejects host with spaces")
    func hostWithSpaces() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("example .com:443")
        }
    }

    @Test("Rejects empty brackets")
    func emptyBrackets() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("[]:443")
        }
    }

    @Test("Rejects missing closing bracket")
    func missingClosingBracket() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("[::1:8080")
        }
    }

    @Test("Rejects trailing colon with no port")
    func trailingColonNoPort() {
        #expect(throws: HostPortParser.ParseError.self) {
            try HostPortParser.parse("example.com:")
        }
    }
}
