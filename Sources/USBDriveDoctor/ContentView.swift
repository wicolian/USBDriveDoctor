import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.md) {
                PulseTrace(entries: model.logEntries, status: model.overallStatus)
                    .frame(width: 140)
                statusBadge
                Spacer(minLength: Theme.Space.md)
                readOnlyBadge
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
            .background(Theme.surface1)
            .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .bottom)

            HSplitView {
                diskListPanel
                    .frame(minWidth: 360, idealWidth: 420)
                logPanel
                    .frame(minWidth: 400)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Theme.canvas)
    }

    private var statusBadge: some View {
        HStack(spacing: Theme.Space.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.vitalLabel)
                .foregroundStyle(Theme.textSecondary)
        }
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
        case .quiet: return "NO DRIVES ATTACHED"
        case .healthy: return "SIGNAL STEADY"
        case .struggling: return "DRIVE STRUGGLING"
        }
    }

    /// The permanent safety guarantee - this is always true, so it reads as
    /// a calm structural fact (a small badge with the app's accent color),
    /// never as an alert. Alert colors are earned, not given away for free.
    private var readOnlyBadge: some View {
        HStack(spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 11, weight: .medium))
                Text("Read-only · never erases or repairs")
                    .font(.vitalMeta)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(0.12))
            .clipShape(Capsule())

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .disabled(model.isRefreshing)
            .frame(width: 22, height: 22)
        }
    }

    private var diskListPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if model.isRefreshing && model.disks.isEmpty {
                    HStack(spacing: Theme.Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Scanning attached drives…").font(.vitalMeta).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(Theme.Space.lg)
                } else if model.disks.isEmpty {
                    emptyState
                } else {
                    ForEach(model.disks) { disk in
                        DiskCard(disk: disk, model: model)
                    }
                }
            }
            .padding(Theme.Space.md)
            .animation(.spring(response: 0.35, dampingFraction: 1.0), value: model.disks)
        }
        .background(Theme.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "externaldrive")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textMuted)
            Text("No external drives attached")
                .font(.vitalDisplay)
                .foregroundStyle(Theme.textSecondary)
            Text("Plug one in - it'll appear here the moment macOS sees it.")
                .font(.vitalMeta)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xxl)
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LIVE SIGNAL")
                    .vitalLabelStyle()
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(model.isStreaming ? "Stop" : "Start") {
                    model.isStreaming ? model.stopLogStream() : model.startLogStream()
                }
                .font(.vitalMeta)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            .padding(Theme.Space.md)

            Text("A red line means something real just happened: the drive disconnected on its own, or a read was aborted mid-transfer. Everything else is quiet, healthy signal.")
                .font(.vitalMeta)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.md)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(model.logEntries) { entry in
                            LogLineView(entry: entry).id(entry.id)
                        }
                    }
                    .padding(Theme.Space.md)
                }
                .background(Theme.inset)
                .onChange(of: model.logEntries.count) { _ in
                    if let last = model.logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Theme.surface1)
    }
}

private extension Text {
    /// Small trailing-aligned note under a mount action - failure detail,
    /// timeout explanation, etc.
    func terminalNote(_ color: Color) -> some View {
        self.font(.vitalMeta).foregroundStyle(color)
    }
}

private struct LogLineView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.logTimestamp)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 62, alignment: .leading)
            Text(entry.text)
                .font(.logLine)
                .foregroundStyle(entry.isWarning ? Theme.critical : Theme.textSecondary)
                .fontWeight(entry.isWarning ? .semibold : .regular)
                .textSelection(.enabled)
        }
    }
}

private struct DiskCard: View {
    let disk: DiskDevice
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(disk.mediaName)
                    .font(.vitalDisplay)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.sm)
                Text(disk.id)
                    .font(.vitalMeta)
                    .foregroundStyle(Theme.textMuted)
            }

            vitalsGrid

            if disk.usbSpeed.usesUAS {
                advisoryTip
            }

            if !disk.partitions.isEmpty {
                Rectangle().fill(Theme.hairlineSoft).frame(height: 1)
                VStack(spacing: Theme.Space.xs) {
                    ForEach(disk.partitions) { part in
                        PartitionRow(partition: part, model: model)
                    }
                }
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var vitalsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Space.lg, verticalSpacing: 5) {
            GridRow { vitalLabel("SIZE"); vitalValue(disk.sizeString) }
            GridRow { vitalLabel("PROTOCOL"); vitalValue(disk.protocolName) }
            GridRow { vitalLabel("USB SPEED"); vitalValue(disk.usbSpeed.label) }
            GridRow { vitalLabel("SMART"); vitalValue(disk.smartStatus) }
            GridRow { vitalLabel("PARTITION SCHEME"); vitalValue(disk.content) }
        }
    }

    private func vitalLabel(_ s: String) -> some View {
        Text(s).vitalLabelStyle().foregroundStyle(Theme.textTertiary)
    }

    private func vitalValue(_ s: String) -> some View {
        Text(s).font(.vitalData).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
    }

    private var advisoryTip: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 11, weight: .medium))
                .padding(.top, 1)
            Text("On SuperSpeed (UAS). If the signal spikes red for this drive, moving it to a USB 2.0 port or hub skips UAS entirely and often clears it.")
                .font(.vitalMeta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.advisory)
        .padding(Theme.Space.sm)
        .background(Theme.advisory.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

private struct PartitionRow: View {
    let partition: PartitionDevice
    @ObservedObject var model: AppModel

    private var state: MountAttemptState {
        model.mountStates[partition.id] ?? .idle
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    Text(partition.volumeName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(partition.id)
                        .font(.vitalMeta)
                        .foregroundStyle(Theme.textMuted)
                }
                Text("\(partition.fileSystem) · \(partition.sizeString) · \(partition.mounted ? "Mounted" : "Not mounted")")
                    .font(.vitalMeta)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.sm)
            actionArea
                .layoutPriority(1)
        }
        .padding(Theme.Space.sm)
        .background(Theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: state)
    }

    private var progress: MountProgress? { model.mountProgress[partition.id] }

    @ViewBuilder
    private var actionArea: some View {
        switch state {
        case .idle:
            if partition.mounted {
                mountedLabel
            } else {
                Button("Try mount") { model.tryMount(partition) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
            }

        case .failed, .timedOut, .disconnected:
            // Auto-retry normally carries these straight into .retryWaiting -
            // this branch only shows once the user has stopped retrying, so
            // it needs to offer a manual way back in.
            VStack(alignment: .trailing, spacing: 3) {
                Button("Try mount") { model.tryMount(partition) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                if case .timedOut = state {
                    Text("Timed out - drive may be unstable").terminalNote(Theme.advisory)
                } else if case .disconnected = state {
                    Text("Disconnected mid-attempt").terminalNote(Theme.critical)
                } else if case .failed(let msg) = state {
                    Text(msg).terminalNote(Theme.critical).lineLimit(2).frame(maxWidth: 200, alignment: .trailing)
                }
            }

        case .trying:
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: Theme.Space.xs) {
                    ProgressView().controlSize(.small)
                    Text(elapsedLabel).font(.vitalData).foregroundStyle(Theme.textSecondary)
                    if let mbps = progress?.throughputMBps {
                        Text(String(format: "~%.0f MB/s", mbps))
                            .font(.vitalData).foregroundStyle(Theme.signalHealthy)
                    }
                }
                if let progress, progress.attempt > 1 {
                    Text("Attempt \(progress.attempt)").font(.vitalMeta).foregroundStyle(Theme.textTertiary)
                }
                Text(progress?.phase ?? "Starting mount attempt…")
                    .font(.vitalMeta).foregroundStyle(Theme.textTertiary)
                    .lineLimit(2).frame(maxWidth: 210, alignment: .trailing)
                stopRetryingButton
            }

        case .retryWaiting(let resumesIn):
            VStack(alignment: .trailing, spacing: 3) {
                Text("Retrying in \(resumesIn)s…").font(.vitalData).foregroundStyle(Theme.advisory)
                if let progress, progress.attempt > 1 {
                    Text("Attempt \(progress.attempt) didn't stick").font(.vitalMeta).foregroundStyle(Theme.textTertiary)
                }
                stopRetryingButton
            }

        case .success:
            mountedLabel
        }
    }

    private var elapsedLabel: String {
        let s = progress?.secondsElapsed ?? 0
        return s < 60 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
    }

    private var stopRetryingButton: some View {
        Button("Stop retrying") { model.stopRetrying(partition.id) }
            .buttonStyle(.plain)
            .font(.vitalMeta)
            .foregroundStyle(Theme.textTertiary)
    }

    private var mountedLabel: some View {
        Label("Mounted", systemImage: "checkmark.circle.fill")
            .font(.vitalMeta)
            .foregroundStyle(Theme.signalHealthy)
    }
}
