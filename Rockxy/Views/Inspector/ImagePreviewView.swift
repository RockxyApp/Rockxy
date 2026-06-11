import SwiftUI

// Renders the image preview interface for the request and response inspector.

struct ImagePreviewView: View {
    let data: Data

    var body: some View {
        if let nsImage = NSImage(data: data) {
            VStack(spacing: 8) {
                Spacer()
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                let rep = nsImage.representations.first
                let width = rep?.pixelsWide ?? Int(nsImage.size.width)
                let height = rep?.pixelsHigh ?? Int(nsImage.size.height)
                Text("\(width) × \(height) — \(SizeFormatter.format(bytes: data.count))")
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        } else {
            ContentUnavailableView {
                Label(String(localized: "Cannot Display Image"), systemImage: "photo")
            } description: {
                Text(String(localized: "Image data could not be decoded"))
            }
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
