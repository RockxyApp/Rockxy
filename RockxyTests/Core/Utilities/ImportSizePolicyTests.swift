import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ImportSizePolicy` in the core utilities layer.

struct ImportSizePolicyTests {
    @Test("File under limit passes validation")
    func underLimitPasses() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).har")
        try "small content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = ImportSizePolicy.validateFileSize(
            at: tempFile,
            maxSize: ImportSizePolicy.maxHARFileSize
        )
        if case .failure = result {
            Issue.record("Small file should pass validation")
        }
    }

    @Test("File over limit fails validation")
    func overLimitFails() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).har")
        try "x".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = ImportSizePolicy.validateFileSize(at: tempFile, maxSize: 0)
        if case .success = result {
            Issue.record("File exceeding limit should fail validation")
        }
    }

    @Test("Missing file returns attribute error")
    func missingFile() {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)")
        let result = ImportSizePolicy.validateFileSize(
            at: fakeURL,
            maxSize: ImportSizePolicy.maxHARFileSize
        )
        if case .success = result {
            Issue.record("Missing file should return error")
        }
    }

    @Test("Error description includes sizes")
    func errorDescription() {
        let error = ImportSizeError.fileTooLarge(
            actualBytes: 150 * 1_024 * 1_024,
            limitBytes: 100 * 1_024 * 1_024
        )
        let desc = error.localizedDescription
        #expect(desc.contains("150"))
        #expect(desc.contains("100"))
    }
}
