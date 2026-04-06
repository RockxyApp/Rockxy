import os
import SwiftUI

/// Waterfall timeline visualization of HTTP request phases (DNS, TCP, TLS, TTFB, Transfer).
/// Each transaction renders as a horizontally-scaled bar with color-coded segments,
/// similar to the Chrome DevTools Network timing view.
struct RequestTimelineView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        if coordinator.transactions.isEmpty {
            ContentUnavailableView(
                String(localized: "No Timeline Data"),
                systemImage: "chart.bar.xaxis",
                description: Text(String(localized: "Capture traffic to see the request timeline"))
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                legendBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                timelineContent
            }
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RequestTimelineView")

    private let phaseColors: [(String, Color)] = [
        ("DNS", .cyan),
        ("TCP", .green),
        ("TLS", .purple),
        ("TTFB", .orange),
        ("Transfer", .blue)
    ]

    private let rowHeight: CGFloat = 28
    private let labelWidth: CGFloat = 220
    private let barAreaMinWidth: CGFloat = 300

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 16) {
            ForEach(phaseColors, id: \.0) { name, color in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 12, height: 12)
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        let timedTransactions = coordinator.transactions.filter { $0.timingInfo != nil }
        let maxDuration = timedTransactions
            .compactMap { $0.timingInfo?.totalDuration }
            .max() ?? 1.0

        return ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                timeAxis(maxDuration: maxDuration)
                    .padding(.leading, labelWidth)

                ForEach(Array(timedTransactions.enumerated()), id: \.element.id) { index, transaction in
                    timelineRow(
                        transaction: transaction,
                        maxDuration: maxDuration,
                        isAlternate: index.isMultiple(of: 2)
                    )
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Time Axis

    private func timeAxis(maxDuration: TimeInterval) -> some View {
        let tickCount = 5
        return GeometryReader { geometry in
            let barWidth = max(geometry.size.width, barAreaMinWidth)
            ZStack(alignment: .leading) {
                ForEach(0 ... tickCount, id: \.self) { tick in
                    let fraction = Double(tick) / Double(tickCount)
                    let xOffset = fraction * barWidth
                    let timeMs = fraction * maxDuration * 1000

                    Text(formatMs(timeMs))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .position(x: xOffset, y: 10)
                }
            }
        }
        .frame(height: 20)
        .frame(minWidth: barAreaMinWidth)
    }

    // MARK: - Timeline Row

    private func timelineRow(
        transaction: HTTPTransaction,
        maxDuration: TimeInterval,
        isAlternate: Bool
    )
        -> some View
    {
        HStack(spacing: 0) {
            requestLabel(transaction)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, 8)

            GeometryReader { geometry in
                let barWidth = max(geometry.size.width, barAreaMinWidth)
                timelineBar(
                    timing: transaction.timingInfo,
                    maxDuration: maxDuration,
                    totalWidth: barWidth
                )
            }
            .frame(minWidth: barAreaMinWidth)
        }
        .frame(height: rowHeight)
        .background(isAlternate ? Color.primary.opacity(0.03) : Color.clear)
    }

    private func requestLabel(_ transaction: HTTPTransaction) -> some View {
        HStack(spacing: 4) {
            Text(transaction.request.method)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(transaction.request.host + transaction.request.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Bar Rendering

    private func timelineBar(
        timing: TimingInfo?,
        maxDuration: TimeInterval,
        totalWidth: CGFloat
    )
        -> some View
    {
        guard let timing else {
            return AnyView(EmptyView())
        }

        let scale = maxDuration > 0 ? totalWidth / maxDuration : 0
        let phases: [(TimeInterval, Color)] = [
            (timing.dnsLookup, .cyan),
            (timing.tcpConnection, .green),
            (timing.tlsHandshake, .purple),
            (timing.timeToFirstByte, .orange),
            (timing.contentTransfer, .blue)
        ]

        return AnyView(
            HStack(spacing: 0) {
                ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                    let width = phase.0 * scale
                    if width > 0.5 {
                        Rectangle()
                            .fill(phase.1)
                            .frame(width: width)
                    }
                }
                Spacer()
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .padding(.vertical, (rowHeight - 14) / 2)
        )
    }

    // MARK: - Formatting

    private func formatMs(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.1fs", ms / 1000)
        }
        return String(format: "%.0fms", ms)
    }
}
