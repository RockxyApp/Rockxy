import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - RootCAShareSheet

struct RootCAShareSheet: View {
    let session: RootCADownloadSession
    let fingerprint: String?
    let onCopyURL: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Share CA for Device"))
                        .font(.title3.weight(.semibold))
                    Text(
                        String(
                            localized: """
                            This link serves only your public Rockxy Root CA from this Mac. \
                            It expires automatically. Do not install certificates from unknown sources.
                            """
                        )
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                qrCode

                VStack(alignment: .leading, spacing: 10) {
                    infoRow(title: String(localized: "URL"), value: session.publicURL.absoluteString)
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        infoRow(title: String(localized: "Expires"), value: expiryText(at: context.date))
                    }
                    infoRow(title: String(localized: "Fingerprint"), value: fingerprint ?? String(localized: "Unavailable"))

                    Text(
                        String(
                            localized: """
                            On the device, open this link in Safari, install the downloaded profile, then \
                            enable Full Trust in Settings > General > About > Certificate Trust Settings.
                            """
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button {
                    onCopyURL()
                } label: {
                    Label(String(localized: "Copy URL"), systemImage: "doc.on.doc")
                }

                Spacer()

                Button(String(localized: "Stop Sharing"), role: .destructive) {
                    onStop()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func expiryText(at date: Date) -> String {
        let remaining = max(0, Int(session.expiresAt.timeIntervalSince(date).rounded(.down)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(localized: "\(minutes)m \(seconds)s remaining")
    }

    @ViewBuilder private var qrCode: some View {
        if let image = Self.makeQRCode(from: session.publicURL.absoluteString) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 160, height: 160)
                .padding(8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.8))
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 176, height: 176)
                .overlay {
                    Text(String(localized: "QR unavailable"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }

    private static func makeQRCode(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let representation = NSCIImageRep(ciImage: transformed)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
