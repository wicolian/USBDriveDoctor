import SwiftUI
import AppKit

/// The compact popover that drops down from the menu bar icon. Same
/// instrument-panel language as the full window, just condensed: one pulse
/// trace, one line per disk, a button through to the full diagnostic view.
struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            PulseTrace(entries: model.logEntries, status: model.overallStatus)
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.sm)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            if model.disks.isEmpty {
                Text("No external drives attached.")
                    .font(.vitalMeta)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(Theme.Space.lg)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Space.xs) {
                        ForEach(model.disks) { disk in
                            DiskSummaryRow(disk: disk)
                        }
                    }
                    .padding(Theme.Space.sm)
                }
                .frame(maxHeight: 240)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack {
                Button("Open Full Diagnostics…") {
                    openWindow(id: "details")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .font(.vitalMeta)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
                    .font(.vitalMeta)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 320)
        .background(Theme.surface1)
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: model.disks)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: model.overallStatus.symbolName)
                .foregroundStyle(statusColor)
            Text("USB Drive Doctor")
                .font(.vitalDisplay)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(statusText)
                .font(.vitalLabel)
                .foregroundStyle(statusColor)
        }
        .padding(Theme.Space.md)
    }

    private var statusColor: Color {
        switch model.overallStatus {
        case .quiet: return Theme.textMuted
        case .healthy: return Theme.signalHealthy
        case .struggling: return Theme.critical
        }
    }

    private var statusText: String {
        switch model.overallStatus {
        case .quiet: return "IDLE"
        case .healthy: return "HEALTHY"
        case .struggling: return "STRUGGLING"
        }
    }
}

private struct DiskSummaryRow: View {
    let disk: DiskDevice

    private var mountedPartitionCount: Int {
        disk.partitions.filter(\.mounted).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(disk.mediaName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.sm)
                Text(disk.sizeString)
                    .font(.vitalMeta)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("\(disk.usbSpeed.label) · \(mountedPartitionCount)/\(disk.partitions.count) mounted")
                .font(.vitalMeta)
                .foregroundStyle(Theme.textTertiary)
            if disk.usbSpeed.usesUAS {
                Text("On SuperSpeed (UAS) — try USB 2.0 if it struggles")
                    .font(.vitalMeta)
                    .foregroundStyle(Theme.advisory)
            }
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}
