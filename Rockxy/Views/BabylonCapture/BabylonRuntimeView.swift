import SwiftUI

struct BabylonRuntimeView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Runtime Events"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Clear")) {
                    store.clear()
                }
                .disabled(store.events.isEmpty)
            }
            .padding()

            Divider()

            if store.events.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Runtime Events"),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(String(localized: "Start a Babylon trace to see events here."))
                )
            } else {
                List(store.events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.kind.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(event.name)
                                .fontWeight(.medium)
                            Spacer()
                            Text(event.createdAt, style: .time)
                                .foregroundStyle(.secondary)
                        }
                        Text(event.source.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let errorMessage = event.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 420)
    }

    // MARK: Private

    @State private var store = BabylonRuntimeEventStore.shared
}
