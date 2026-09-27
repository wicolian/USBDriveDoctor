import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            disclaimerBanner

            HSplitView {
                diskListPanel
                    .frame(minWidth: 340, idealWidth: 400)
                logPanel
                    .frame(minWidth: 380)
            }
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    private var disclaimerBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
            Text("Read-only. Never erases or repairs.")
                .fontWeight(.semibold)
            Spacer()
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
        }
        .padding(10)
        .background(.orange.opacity(0.18))
    }

    private var diskListPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.isRefreshing && model.disks.isEmpty {
                    ProgressView("Scanning attached disks…")
                        .padding()
                } else if model.disks.isEmpty {
                    Text("No external disks detected.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(model.disks) { disk in
                        DiskCard(disk: disk, model: model)
                    }
                }
            }
            .padding(12)
            .animation(.spring(response: 0.35, dampingFraction: 1.0), value: model.disks)
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live diagnostic log")
                    .font(.headline)
                Spacer()
                Button(model.isStreaming ? "Stop" : "Start") {
                    model.isStreaming ? model.stopLogStream() : model.startLogStream()
                }
            }
            .padding([.top, .horizontal], 10)

            Text("Red lines are the exact signals that mean a drive is struggling: it disconnected on its own, or a data transfer was aborted mid-read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.logEntries) { entry in
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(entry.isWarning ? Color.red : Color.primary)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.logEntries.count) { _ in
                    if let last = model.logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct DiskCard: View {
    let disk: DiskDevice
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(disk.mediaName)
                    .font(.headline)
                Spacer()
                Text(disk.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow { Text("Size").foregroundStyle(.secondary); Text(disk.sizeString) }
                GridRow { Text("Protocol").foregroundStyle(.secondary); Text(disk.protocolName) }
                GridRow { Text("USB speed").foregroundStyle(.secondary); Text(disk.usbSpeed.label) }
                GridRow { Text("SMART").foregroundStyle(.secondary); Text(disk.smartStatus) }
                GridRow { Text("Partition scheme").foregroundStyle(.secondary); Text(disk.content) }
            }
            .font(.system(size: 12))

            if disk.usbSpeed.usesUAS {
                Text("Tip: this drive is on SuperSpeed (UAS). If the diagnostic log shows red \"aborting\" or \"stream\" lines for it, try moving it to a USB 2.0 port or hub — that skips UAS entirely and can fix this exact failure.")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(6)
                    .background(.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !disk.partitions.isEmpty {
                Divider()
                ForEach(disk.partitions) { part in
                    PartitionRow(partition: part, model: model)
                }
            }
        }
        .padding(12)
        .background(.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PartitionRow: View {
    let partition: PartitionDevice
    @ObservedObject var model: AppModel

    private var state: MountAttemptState {
        model.mountStates[partition.id] ?? .idle
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(partition.volumeName)
                        .fontWeight(.medium)
                    Text(partition.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(partition.fileSystem) · \(partition.sizeString) · \(partition.mounted ? "Mounted" : "Not mounted")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actionArea
        }
        .padding(8)
        .background(.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: state)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch state {
        case .idle, .failed, .timedOut, .disconnected:
            VStack(alignment: .trailing, spacing: 2) {
                if partition.mounted {
                    Label("Mounted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Try mount (read-only)") {
                        model.tryMount(partition)
                    }
                }
                if case .timedOut = state {
                    Text("Timed out — drive may be unstable").font(.caption2).foregroundStyle(.orange)
                }
                if case .disconnected = state {
                    Text("Drive disconnected mid-attempt").font(.caption2).foregroundStyle(.red)
                }
                if case .failed(let msg) = state {
                    Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }
        case .trying(let secondsLeft):
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Trying… \(secondsLeft)s").font(.caption)
            }
        case .success:
            Label("Mounted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
