import Foundation
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - RawOutputADBRunner

/// Answers each `adb` invocation with exact bytes, so a test can hand the marker scanner output
/// that is long, or not valid UTF-8, without going through a `String` round trip.
private final class RawOutputADBRunner: SimulatorCommandRunning, @unchecked Sendable {
    // MARK: Lifecycle

    init(output: @escaping @Sendable ([String]) -> Data) {
        self.output = output
    }

    // MARK: Internal

    func run(executable _: URL, arguments: [String]) async throws -> SimulatorCommandOutput {
        SimulatorCommandOutput(status: 0, standardOutput: output(arguments), standardError: Data())
    }

    // MARK: Private

    private let output: @Sendable ([String]) -> Data
}

// MARK: - AndroidSystemTrustMarkerTests

/// The trust script echoes its success marker last, and an error marker last before exiting, so
/// both land at the end of the captured output. Reading only a head slice of it meant a chatty
/// script turned a successful install into "System trust was not applied." with no detail, on the
/// certificate-trust path a user needs to diagnose.
struct AndroidSystemTrustMarkerTests {
    // MARK: Internal

    @Test("a success marker behind more than 4 KiB of script noise still counts as success")
    func seesSuccessMarkerAfterLongOutput() async throws {
        let runner = RawOutputADBRunner { arguments in
            if arguments.suffix(2) == ["id", "-u"] {
                return Data("0\n".utf8)
            }
            guard arguments.contains("sh") else {
                return Data()
            }
            return Self.noisy(then: AndroidSystemTrust.installedMarker)
        }

        let results = try await Self.controller(runner).trustSystemWide(
            [Self.emulator],
            certificatePEM: Self.certificatePEM()
        )

        #expect(Self.isSuccess(results[Self.emulator]))
    }

    @Test("an error marker behind more than 4 KiB of script noise keeps its reason")
    func reportsErrorDetailAfterLongOutput() async throws {
        let runner = RawOutputADBRunner { arguments in
            if arguments.suffix(2) == ["id", "-u"] {
                return Data("0\n".utf8)
            }
            guard arguments.contains("sh") else {
                return Data()
            }
            return Self.noisy(then: "\(AndroidSystemTrust.errorMarker) mount failed")
        }

        let results = try await Self.controller(runner).trustSystemWide(
            [Self.emulator],
            certificatePEM: Self.certificatePEM()
        )

        // The reason, not a bare `.systemTrustFailed(nil)`, which is what a head slice produced.
        #expect(Self.failure(results[Self.emulator]) == .systemTrustFailed("mount failed"))
    }

    @Test("removal sees its own marker behind long output too")
    func seesRemovalMarkerAfterLongOutput() async {
        let runner = RawOutputADBRunner { arguments in
            if arguments.suffix(2) == ["id", "-u"] {
                return Data("0\n".utf8)
            }
            guard arguments.contains("sh") else {
                return Data()
            }
            return Self.noisy(then: AndroidSystemTrust.removedMarker)
        }

        let results = await Self.controller(runner).removeSystemTrust([Self.emulator])

        #expect(Self.isSuccess(results[Self.emulator]))
    }

    /// The runner caps each stream at a byte count, so a capture can end mid-character. A strict
    /// whole-buffer decode would return nil for that and lose a marker that is plainly present.
    @Test("output that is not valid UTF-8 does not erase the marker")
    func seesMarkerInUndecodableOutput() async throws {
        let runner = RawOutputADBRunner { arguments in
            if arguments.suffix(2) == ["id", "-u"] {
                return Data("0\n".utf8)
            }
            guard arguments.contains("sh") else {
                return Data()
            }
            var bytes = Data("\(AndroidSystemTrust.installedMarker)\n".utf8)
            // A lone continuation byte: a truncated multi-byte character.
            bytes.append(0x80)
            return bytes
        }

        let results = try await Self.controller(runner).trustSystemWide(
            [Self.emulator],
            certificatePEM: Self.certificatePEM()
        )

        #expect(Self.isSuccess(results[Self.emulator]))
    }

    // MARK: Private

    private static let emulator = AndroidEmulator(serial: "emulator-5554")

    private static func controller(_ runner: SimulatorCommandRunning) -> AndroidEmulatorProxyController {
        AndroidEmulatorProxyController(
            runner: runner,
            environment: ["ANDROID_HOME": "/opt/sdk"],
            isExecutable: { _ in true }
        )
    }

    /// Well past the 4 KiB the scanner used to read, with the marker where the script puts it.
    private static func noisy(then marker: String) -> Data {
        Data((String(repeating: "mount: remounting /system\n", count: 400) + marker + "\n").utf8)
    }

    private static func isSuccess(_ result: Result<Void, AndroidEmulatorError>?) -> Bool {
        if case .success = result {
            return true
        }
        return false
    }

    private static func failure(_ result: Result<Void, AndroidEmulatorError>?) -> AndroidEmulatorError? {
        if case let .failure(error) = result {
            return error
        }
        return nil
    }

    private static func certificatePEM() throws -> String {
        let root = try RootCAGenerator.generate()
        var serializer = DER.Serializer()
        try root.certificate.serialize(into: &serializer)
        return PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
    }
}
