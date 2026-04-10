import Foundation
import os
import Security

/// Validates that external system binaries are Apple-signed before execution.
/// Prevents path-hijack attacks where a malicious binary replaces a system tool
/// that the helper runs as root.
///
/// Validation results are cached per path for the lifetime of the helper process
/// since system binaries do not change during a single daemon run.
enum BinaryValidator {
    // MARK: Internal

    /// Validates that the binary at the given path has a valid Apple code signature.
    /// Returns `true` if the binary passes signature validation, `false` otherwise.
    /// Results are cached per path.
    static func validateAppleSignedBinary(at path: String) -> Bool {
        if let cached = cache[path] {
            return cached
        }

        let result = performValidation(path: path)
        cache[path] = result
        return result
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "BinaryValidator"
    )

    private static var cache: [String: Bool] = [:]

    private static func performValidation(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)

        guard createStatus == errSecSuccess, let code = staticCode else {
            logger.error(
                "SECURITY: Failed to create SecStaticCode for \(path): status \(createStatus)"
            )
            return false
        }

        // Validate the code signature is intact and valid
        let validityStatus = SecStaticCodeCheckValidity(code, SecCSFlags([]), nil)
        guard validityStatus == errSecSuccess else {
            logger.error(
                "SECURITY: Code signature validation failed for \(path): status \(validityStatus)"
            )
            return false
        }

        // Verify the binary is signed by Apple
        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(
            "anchor apple" as CFString,
            [],
            &requirement
        )

        guard reqStatus == errSecSuccess, let requirement else {
            logger.error(
                "SECURITY: Failed to create Apple anchor requirement: status \(reqStatus)"
            )
            return false
        }

        let anchorStatus = SecStaticCodeCheckValidity(code, SecCSFlags([]), requirement)
        guard anchorStatus == errSecSuccess else {
            logger.error(
                "SECURITY: Binary at \(path) is not Apple-signed: status \(anchorStatus)"
            )
            return false
        }

        logger.info("SECURITY: Validated Apple-signed binary at \(path)")
        return true
    }
}
