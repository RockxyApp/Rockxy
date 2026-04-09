import SwiftUI

/// Bottom control bar for the Diff workspace. Contains compare target picker,
/// presentation mode picker, and difference count summary.
struct DiffControlBar: View {
    @Bindable var viewModel: DiffViewModel

    var body: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Compare"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $viewModel.compareTarget) {
                ForEach(CompareTarget.allCases, id: \.self) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .controlSize(.small)

            Spacer()

            Text(String(localized: "View"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $viewModel.presentationMode) {
                ForEach(PresentationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .controlSize(.small)

            let result = viewModel.activeDiffResult
            if result.addedCount > 0 {
                Label("+\(result.addedCount)", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if result.removedCount > 0 {
                Label("-\(result.removedCount)", systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("(\(result.differenceCount) \(result.differenceCount == 1 ? "difference" : "differences"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
