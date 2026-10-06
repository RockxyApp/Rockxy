import AppKit
import SwiftUI

// MARK: - ConnectionLogInspectorView

/// Request ▸ Connection Log: how Rockxy reached the server for the selected exchange, as a
/// selectable `curl -v`-style transcript with Open with / Save actions.
struct ConnectionLogInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        let lines = ConnectionLogFormatter.lines(for: ConnectionLogFormatter.Input(transaction: transaction))
        VStack(spacing: 0) {
            ConnectionLogTextView(
                lines: lines,
                fontSize: CGFloat(metrics.inspectorTextEditorSettings.fontSize)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(String(localized: "Connection Log", bundle: RockxyLocalization.bundle))
            Divider()
            PayloadActionsBar(
                payload: Data(lines.map(\.rendered).joined(separator: "\n").utf8),
                fileStem: "\(transaction.id.uuidString)-connection",
                fileExtension: "log",
                suggestedName: "connection-log",
                saveTitle: String(localized: "Save Log As…", bundle: RockxyLocalization.bundle)
            )
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - ConnectionLogTextView

/// Read-only, selectable text view so the whole log can be selected and copied at once.
struct ConnectionLogTextView: NSViewRepresentable {
    // MARK: Internal

    let lines: [ConnectionLogLine]
    let fontSize: CGFloat

    static func attributedText(for lines: [ConnectionLogLine], fontSize: CGFloat) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if !line.marker.isEmpty {
                result.append(NSAttributedString(
                    string: "\(line.marker) ",
                    attributes: [.font: font, .foregroundColor: Theme.ConnectionLog.markerNS]
                ))
            }
            appendText(of: line, font: font, to: result)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
        }
        return result
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.setAccessibilityIdentifier("connection-log-text")
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        let text = Self.attributedText(for: lines, fontSize: fontSize)
        guard textView.attributedString() != text else {
            return
        }
        textView.textStorage?.setAttributedString(text)
    }

    // MARK: Private

    private static func appendText(of line: ConnectionLogLine, font: NSFont, to result: NSMutableAttributedString) {
        switch line.role {
        case .requestHeader,
             .responseHeader:
            // Header rows color the field name; start lines ("GET / HTTP/1.1") stay plain.
            // Searching after the first character keeps HTTP/2 pseudo-headers (":path") whole.
            if let colon = line.text.dropFirst().firstIndex(of: ":"), !line.text[..<colon].contains(" ") {
                appendHeader(line.text, colon: colon, font: font, to: result)
            } else {
                result.append(NSAttributedString(
                    string: line.text,
                    attributes: [.font: font, .foregroundColor: NSColor.labelColor]
                ))
            }
        default:
            result.append(NSAttributedString(
                string: line.text,
                attributes: [.font: font, .foregroundColor: color(for: line.role)]
            ))
        }
    }

    private static func appendHeader(
        _ text: String,
        colon: String.Index,
        font: NSFont,
        to result: NSMutableAttributedString
    ) {
        result.append(NSAttributedString(
            string: String(text[..<colon]),
            attributes: [.font: font, .foregroundColor: Theme.ConnectionLog.headerNameNS]
        ))
        result.append(NSAttributedString(
            string: String(text[colon...]),
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        ))
    }

    private static func color(for role: ConnectionLogLine.Role) -> NSColor {
        switch role {
        case .event: Theme.ConnectionLog.eventNS
        case .host: Theme.ConnectionLog.hostNS
        case .tls: Theme.ConnectionLog.tlsNS
        case .success: Theme.ConnectionLog.successNS
        case .warning: Theme.ConnectionLog.warningNS
        case .failure: Theme.ConnectionLog.failureNS
        case .note: Theme.ConnectionLog.noteNS
        case .requestHeader,
             .responseHeader: NSColor.labelColor
        }
    }
}
