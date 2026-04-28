import AppKit
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

    func resolvedForStaticDisplay(fallbackMessage: String) -> Self {
        switch self {
        case .loading:
            .unavailable(fallbackMessage)
        case .html,
             .plainText,
             .unavailable:
            self
        }
    }

    func nativeDisplayText(fallbackMessage: String? = nil) -> String? {
        switch self {
        case .loading:
            return fallbackMessage
        case let .html(html, _):
            return Self.makeNativeDisplayText(fromHTML: html) ?? fallbackMessage
        case let .plainText(text),
             let .unavailable(text):
            return Self.normalizeDisplayText(text) ?? fallbackMessage
        }
    }

    func nativeDisplayAttributedString(fallbackMessage: String? = nil) -> NSAttributedString? {
        switch self {
        case .loading:
            guard let fallbackMessage else {
                return nil
            }
            return Self.makePlainTextAttributedString(fallbackMessage)

        case let .html(html, _):
            return Self.makeNativeAttributedString(fromHTML: html)
                ?? fallbackMessage.map(Self.makePlainTextAttributedString)

        case let .plainText(text),
             let .unavailable(text):
            let normalizedText = Self.normalizeDisplayText(text) ?? fallbackMessage
            return normalizedText.map(Self.makePlainTextAttributedString)
        }
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

    private static func makeNativeDisplayText(fromHTML html: String) -> String? {
        makeNativeAttributedString(fromHTML: html).flatMap { normalizeDisplayText($0.string) }
    }

    private static func makeNativeAttributedString(fromHTML html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else {
            let fallbackText = normalizeDisplayText(stripHTMLTags(in: html))
            return fallbackText.map(makePlainTextAttributedString)
        }

        do {
            let attributedText = try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
            return normalizedNativeAttributedString(attributedText)
        } catch {
            let fallbackText = normalizeDisplayText(stripHTMLTags(in: html))
            return fallbackText.map(makePlainTextAttributedString)
        }
    }

    private static func stripHTMLTags(in html: String) -> String {
        var plainText = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let htmlEntityMap = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">",
        ]

        for (entity, replacement) in htmlEntityMap {
            plainText = plainText.replacingOccurrences(of: entity, with: replacement)
        }

        return plainText
    }

    private static func normalizeDisplayText(_ text: String) -> String? {
        let normalizedLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var compactedLines: [String] = []
        var previousLineWasBlank = false

        for line in normalizedLines {
            let isBlank = line.isEmpty
            if isBlank {
                guard !previousLineWasBlank else {
                    continue
                }
                compactedLines.append("")
            } else {
                compactedLines.append(line)
            }
            previousLineWasBlank = isBlank
        }

        let result = compactedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return result.isEmpty ? nil : result
    }

    private static func makePlainTextAttributedString(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.15
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.alignment = .natural
        paragraphStyle.lineBreakMode = .byWordWrapping

        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private static func normalizedNativeAttributedString(_ attributedText: NSAttributedString) -> NSAttributedString? {
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: mutableText.length)

        mutableText.beginEditing()
        mutableText.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            var updatedAttributes = attributes
            let sourceFont = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let normalizedFont = normalizedSystemFont(from: sourceFont)
            updatedAttributes[.font] = normalizedFont
            updatedAttributes[.foregroundColor] = NSColor.labelColor

            let paragraphStyle = ((attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.15
            paragraphStyle.paragraphSpacing = normalizedParagraphSpacing(for: sourceFont)
            paragraphStyle.paragraphSpacingBefore = normalizedParagraphSpacingBefore(for: sourceFont)
            paragraphStyle.alignment = .natural
            paragraphStyle.lineBreakMode = .byWordWrapping
            updatedAttributes[.paragraphStyle] = paragraphStyle

            mutableText.setAttributes(updatedAttributes, range: range)
        }
        mutableText.endEditing()

        return mutableText.length > 0 ? mutableText : nil
    }

    private static func normalizedSystemFont(from sourceFont: NSFont) -> NSFont {
        let fontManager = NSFontManager.shared
        let traits = fontManager.traits(of: sourceFont)
        let isBold = traits.contains(.boldFontMask)
        let isItalic = traits.contains(.italicFontMask)

        let mappedSize: CGFloat
        let mappedWeight: NSFont.Weight

        switch sourceFont.pointSize {
        case 22...:
            mappedSize = 24
            mappedWeight = .semibold
        case 17...21.99:
            mappedSize = 18
            mappedWeight = .semibold
        case 14...16.99:
            mappedSize = 14
            mappedWeight = .semibold
        default:
            mappedSize = 13
            mappedWeight = isBold ? .semibold : .regular
        }

        var font = NSFont.systemFont(ofSize: mappedSize, weight: mappedWeight)
        if isItalic {
            font = fontManager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    private static func normalizedParagraphSpacing(for sourceFont: NSFont) -> CGFloat {
        switch sourceFont.pointSize {
        case 22...:
            14
        case 17...21.99:
            10
        case 14...16.99:
            8
        default:
            6
        }
    }

    private static func normalizedParagraphSpacingBefore(for sourceFont: NSFont) -> CGFloat {
        switch sourceFont.pointSize {
        case 22...:
            4
        case 17...21.99:
            2
        default:
            0
        }
    }
}
