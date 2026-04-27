import CoreFoundation
import Foundation
import Sparkle

enum SoftwareUpdateReleaseNotesContent: Equatable {
    case loading
    case html(String, baseURL: URL?)
    case plainText(String)
    case unavailable(String)

    static func from(appcastItem: SUAppcastItem) -> Self {
        guard let itemDescription = appcastItem.itemDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !itemDescription.isEmpty
        else {
            return .loading
        }

        let rawFormat = appcastItem.itemDescriptionFormat?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if rawFormat == "plain-text" {
            return .plainText(itemDescription)
        }

        return .html(itemDescription, baseURL: appcastItem.releaseNotesURL)
    }

    static func from(downloadData: SPUDownloadData) -> Self {
        guard let text = decodeText(from: downloadData.data, encodingName: downloadData.textEncodingName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return .unavailable(
                String(localized: "Release notes are unavailable for this update.")
            )
        }

        if isHTML(mimeType: downloadData.mimeType) {
            return .html(text, baseURL: downloadData.url)
        }

        return .plainText(text)
    }

    private static func isHTML(mimeType: String?) -> Bool {
        guard let mimeType else {
            return false
        }

        return mimeType.localizedCaseInsensitiveContains("html")
            || mimeType.localizedCaseInsensitiveContains("xml")
    }

    private static func decodeText(from data: Data, encodingName: String?) -> String? {
        if let encodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                if let decoded = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) {
                    return decoded
                }
            }
        }

        for encoding in [String.Encoding.utf8, .utf16, .ascii] {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }

        return nil
    }
}
