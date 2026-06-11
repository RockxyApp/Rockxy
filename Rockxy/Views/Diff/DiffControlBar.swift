import SwiftUI

/// Bottom control bar for the Diff workspace. Contains compare target picker,
/// presentation mode picker, and difference count summary.
struct DiffControlBar: View {
    @Bindable var viewModel: DiffViewModel
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Compare"))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Picker("", selection: $viewModel.compareTarget) {
                ForEach(CompareTarget.allCases, id: \.self) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: toolMetrics.menuWidth(200))

            Spacer()

            Text(String(localized: "View"))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Picker("", selection: $viewModel.presentationMode) {
                ForEach(PresentationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: toolMetrics.menuWidth(160))

            let result = viewModel.activeDiffResult
            if result.addedCount > 0 {
                Label("+\(result.addedCount)", systemImage: "plus.circle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.green)
            }
            if result.removedCount > 0 {
                Label("-\(result.removedCount)", systemImage: "minus.circle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
            }
            Text("(\(result.differenceCount) \(result.differenceCount == 1 ? "difference" : "differences"))")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
        .font(toolMetrics.font())
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
