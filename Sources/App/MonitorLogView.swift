import SwiftUI

// Read-only view of the monitor extension's callback journal, newest first,
// with a share action so the text can leave the device. The extension has no
// console; this is the only way to see which thresholds fired and when.
struct MonitorLogView: View {
    @State private var lines = SharedStore.shared.monitorLog.reversed()

    var body: some View {
        List {
            if lines.isEmpty {
                Text("No monitor callbacks recorded yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
            }
        }
        .navigationTitle("Monitor journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: lines.joined(separator: "\n"))
                    .disabled(lines.isEmpty)
            }
        }
        .onAppear { lines = SharedStore.shared.monitorLog.reversed() }
    }
}
