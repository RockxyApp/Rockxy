import SwiftUI

/// Visualizes request timing phases (DNS, TCP, TLS, TTFB, transfer) as color-coded
/// horizontal bars, providing a mini waterfall view for a single transaction.
struct TimingInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        if let timing = transaction.timingInfo {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    timingRow("DNS Lookup", duration: timing.dnsLookup, color: Theme.Timing.dns)
                    timingRow("TCP Connection", duration: timing.tcpConnection, color: Theme.Timing.tcp)
                    timingRow("TLS Handshake", duration: timing.tlsHandshake, color: Theme.Timing.tls)
                    timingRow("Time to First Byte", duration: timing.timeToFirstByte, color: Theme.Timing.ttfb)
                    timingRow("Content Transfer", duration: timing.contentTransfer, color: Theme.Timing.transfer)

                    Divider()

                    HStack {
                        Text("Total")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(DurationFormatter.format(seconds: timing.totalDuration))
                            .fontWeight(.semibold)
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Timing Data",
                systemImage: "clock",
                description: Text("Timing information is not available for this request")
            )
        }
    }

    // MARK: Private

    /// Bar width scales linearly at 200pt per second, with a 2pt minimum so zero-duration
    /// phases remain visible.
    private func timingRow(_ label: String, duration: TimeInterval, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: max(2, CGFloat(duration * 200)), height: 12)
            Text(DurationFormatter.format(seconds: duration))
                .font(.caption)
                .frame(width: 60, alignment: .trailing)
        }
    }
}
