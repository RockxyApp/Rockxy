import Foundation
@testable import Rockxy
import Testing

// MARK: - SOCKS5ParserTests

struct SOCKS5ParserTests {
    @Test("Greeting requires SOCKS5 and reports whether no-auth is offered")
    func greeting() {
        #expect(SOCKS5Parser.parseGreeting([0x05]) == .needMoreData)
        #expect(SOCKS5Parser.parseGreeting([0x05, 0x02, 0x00]) == .needMoreData)
        #expect(SOCKS5Parser.parseGreeting([0x05, 0x02, 0x02, 0x00]) == .parsed(true, consumed: 4))
        #expect(SOCKS5Parser.parseGreeting([0x05, 0x01, 0x02]) == .parsed(false, consumed: 3))
        #expect(SOCKS5Parser.parseGreeting([0x04, 0x01, 0x00]) == .rejected(reply: 0xFF))
    }

    @Test("CONNECT requests parse IPv4, domain, and IPv6 destinations")
    func connectRequests() {
        #expect(SOCKS5Parser.parseRequest([0x05, 0x01, 0x00, 0x01, 10, 0, 2, 2, 0x1F, 0x90])
            == .parsed(SOCKS5Request(host: "10.0.2.2", port: 8_080), consumed: 10))

        let domain = Array("echo.example.com".utf8)
        #expect(SOCKS5Parser.parseRequest([0x05, 0x01, 0x00, 0x03, UInt8(domain.count)] + domain + [0x01, 0xBB])
            == .parsed(SOCKS5Request(host: "echo.example.com", port: 443), consumed: 7 + domain.count))

        let loopbackV6: [UInt8] = Array(repeating: 0, count: 15) + [1]
        #expect(SOCKS5Parser.parseRequest([0x05, 0x01, 0x00, 0x04] + loopbackV6 + [0x00, 0x50])
            == .parsed(SOCKS5Request(host: "0:0:0:0:0:0:0:1", port: 80), consumed: 22))
    }

    @Test("Unsupported commands, address types, and hostile names are refused")
    func rejections() {
        #expect(SOCKS5Parser.parseRequest([0x05, 0x02, 0x00, 0x01, 1, 2, 3, 4, 0, 80]) == .rejected(reply: 0x07))
        #expect(SOCKS5Parser.parseRequest([0x05, 0x01, 0x00, 0x09, 1, 2, 3, 4, 0, 80]) == .rejected(reply: 0x08))
        let hostile = Array("evil.example.com/x".utf8)
        #expect(SOCKS5Parser.parseRequest([0x05, 0x01, 0x00, 0x03, UInt8(hostile.count)] + hostile + [0, 80])
            == .rejected(reply: 0x01))
        #expect(SOCKS5Parser.parseRequest([0x05, 0x01, 0x00, 0x01, 1, 2, 3, 4, 0, 0]) == .rejected(reply: 0x01))
        #expect(SOCKS5Parser.parseRequest([0x05, 0x01, 0x00, 0x03, 5, 0x61]) == .needMoreData)
    }
}
