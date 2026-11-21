import Foundation
@testable import Rockxy
import Testing

struct LocalFileLocationLabelTests {
    @Test("Home locations omit account names; other locations show only the file name")
    func localLabels() {
        let home = URL(fileURLWithPath: "/Users/sample", isDirectory: true)
        #expect(LocalFileLocationLabel.label(for: home, homeDirectory: home) == "~")
        #expect(LocalFileLocationLabel.label(
            for: home.appendingPathComponent("Desktop/keys.log"), homeDirectory: home
        ) == "~/Desktop/keys.log")
        #expect(LocalFileLocationLabel.label(
            for: URL(fileURLWithPath: "/Users/sample-other/private/keys.log"), homeDirectory: home
        ) == "keys.log")
        #expect(LocalFileLocationLabel.label(
            for: URL(fileURLWithPath: "/external/private/keys.log"), homeDirectory: home
        ) == "keys.log")
        #expect(LocalFileLocationLabel.label(
            for: home.appendingPathComponent("Documents/../Desktop/keys.log"), homeDirectory: home
        ) == "~/Desktop/keys.log")
    }

    @Test("Unicode home locations and root directories retain a relative label")
    func unicodeAndRoot() {
        let home = URL(fileURLWithPath: "/Users/示例 用户", isDirectory: true)
        #expect(LocalFileLocationLabel.label(
            for: home.appendingPathComponent("Desktop/测试.log"), homeDirectory: home
        ) == "~/Desktop/测试.log")
        #expect(LocalFileLocationLabel.label(
            for: URL(fileURLWithPath: "/private/keys.log"),
            homeDirectory: URL(fileURLWithPath: "/", isDirectory: true)
        ) == "~/private/keys.log")
    }
}
