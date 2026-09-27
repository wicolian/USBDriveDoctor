import SwiftUI
import AppKit

/// The compact popover that drops down from the menu bar icon. Kept
/// deliberately small - one line per disk, one line of tip text max, and a
/// button to open the full diagnostic window for anything deeper.
struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if model.disks.isEmpty {
                Text("No external disks attached.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.disks) { disk in
                            DiskSummaryRow(disk: disk)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 240)
            }

            Divider()

            HStack {
                Button("Open Full Diagnostics…") {
                    openWindow(id: "details")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(10)
        }
        .frame(width: 320)
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: model.disks)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.overallStatus.symbolName)
                .foregroundStyle(color(for: model.overallStatus))
            Text("USB Drive Doctor")
                .fontWeight(.semibold)
            Spacer()
            statusLabel
        }
        .padding(12)
    }

    private var statusLabel: some View {
        Group {
            switch model.overallStatus {
            case .quiet:
                Text("Idle").foregroundStyle(.secondary)
            case .healthy:
                Text("Healthy").foregroundStyle(.green)
            case .struggling:
                Text("Struggling").foregroundStyle(.red)
            }
        }
        .font(.caption)
        .fontWeight(.medium)
    }

    private func color(for status: OverallStatus) -> Color {
        switch status {
        case .quiet: return .secondary
        case .healthy: return .green
        case .struggling: return .red
        }
    }
}

private struct DiskSummaryRow: View {
    let disk: DiskDevice

    private var mountedPartitionCount: Int {
        disk.partitions.filter(\.mounted).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(disk.mediaName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(disk.sizeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(disk.usbSpeed.label) · \(mountedPartitionCount)/\(disk.partitions.count) mounted")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if disk.usbSpeed.usesUAS {
                Text("On SuperSpeed (UAS) — try USB 2.0 if it struggles")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
    }
}
