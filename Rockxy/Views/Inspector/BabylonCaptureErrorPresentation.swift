import SwiftUI

enum BabylonCaptureErrorPresentation {
    static func field(from metadata: BabylonCaptureMetadata) -> ContextTableField? {
        guard metadata.errorCode != nil || metadata.errorDomain != nil || metadata.failurePhase != nil
            || metadata.errorMessage != nil else
        {
            return nil
        }

        let value = [
            metadata.errorDomain,
            metadata.errorCode.map(String.init),
            metadata.failurePhase,
            metadata.errorMessage,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        return ContextTableField(
            label: String(localized: "Captured Error", bundle: RockxyLocalization.bundle),
            value: value,
            monospaced: false,
            color: .red
        )
    }
}
