import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var disks: [DiskDevice] = []
    @Published var isRefreshing = false
    @Published var lastRefreshError: String?
    @Published var logEntries: [LogEntry] = []
    @Published var isStreaming = false
    @Published var mountStates: [String: MountAttemptState] = [:]
    @Published private(set) var overallStatus: OverallStatus = .quiet

    private var mountTimers: [String: Timer] = [:]
    private var refreshTimer: Timer?
    private var statusTimer: Timer?
    private var lastWarningAt: Date?
    private let streamer = LineStreamer()

    /// How long a warning line keeps the menu bar icon in the "struggling"
    /// state after it was last seen. Long enough to notice, short enough
    /// that a resolved problem doesn't look stuck forever.
    private let warningDecay: TimeInterval = 20

    // Broad-but-relevant predicate: USB subsystem senders, plus the specific
    // phrases that mean "this drive is struggling" even if they show up
    // outside a USB-tagged line (e.g. mass-storage driver messages).
    private let logPredicate = """
    (senderImagePath CONTAINS "USB") OR (composedMessage CONTAINS "hardware connection lost") OR (composedMessage CONTAINS "IOUSBMassStorage") OR (composedMessage CONTAINS "IOUSBHostStream")
    """

    init() {
        refresh()
        startLogStream()
        // Menu bar apps have no reliable "screen appeared" moment - a user
        // may never open the details window - so this app polls its own
        // cheap, non-hanging disk listing on a timer instead of waiting for
        // a view lifecycle event.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recomputeStatus() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        statusTimer?.invalidate()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefreshError = nil

        let (wholeDisks, partitionsByDisk) = DiskService.listDeviceNames()

        DiskService.fetchUSBSpeeds { [weak self] speeds in
            guard let self else { return }
            var built: [DiskDevice] = []
            let group = DispatchGroup()

            for diskName in wholeDisks {
                group.enter()
                DiskService.fetchInfo(node: "/dev/\(diskName)") { info, timedOut in
                    var device = DiskDevice(id: diskName)
                    if timedOut {
                        device.mediaName = "(timed out reading info - drive may be unstable)"
                    } else if let info {
                        device.mediaName = info["Device / Media Name"] ?? info["Media Name"] ?? "Unknown device"
                        device.sizeString = info["Disk Size"] ?? "-"
                        device.protocolName = info["Protocol"] ?? "-"
                        device.smartStatus = info["SMART Status"] ?? "-"
                        device.content = info["Content (IOContent)"] ?? info["Content"] ?? "-"
                        device.isExternal = (info["Device Location"] == "External")
                    }
                    device.usbSpeed = USBSpeed.from(linkSpeedHz: speeds[device.mediaName])

                    let partNames = partitionsByDisk[diskName] ?? []
                    let partGroup = DispatchGroup()
                    var parts: [PartitionDevice] = []
                    for partName in partNames {
                        partGroup.enter()
                        DiskService.fetchInfo(node: "/dev/\(partName)") { pinfo, ptimedOut in
                            var part = PartitionDevice(id: partName)
                            if ptimedOut {
                                part.volumeName = "(timed out)"
                            } else if let pinfo {
                                part.volumeName = pinfo["Volume Name"] ?? "-"
                                part.fileSystem = pinfo["File System Personality"] ?? pinfo["Type (Bundle)"] ?? pinfo["Partition Type"] ?? "-"
                                part.mounted = (pinfo["Mounted"] == "Yes")
                                part.sizeString = pinfo["Disk Size"] ?? "-"
                            }
                            DispatchQueue.main.async {
                                parts.append(part)
                                partGroup.leave()
                            }
                        }
                    }
                    partGroup.notify(queue: .main) {
                        device.partitions = parts.sorted { $0.id < $1.id }
                        built.append(device)
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                // Internal volumes (the boot APFS container, its snapshots,
                // Preboot/Recovery/VM) are real "disks" by the same /dev
                // scan, but they are not what this app is for and only add
                // noise ahead of the drive someone actually came here to
                // check. Show external media only.
                self.disks = built.filter(\.isExternal).sorted { $0.id < $1.id }
                self.isRefreshing = false
                // Drop mount-state and timer bookkeeping for partitions that
                // are no longer present, so a disconnected drive doesn't
                // leave stale "trying..." spinners behind.
                let present = Set(self.disks.flatMap { $0.partitions.map(\.id) })
                for key in self.mountStates.keys where !present.contains(key) {
                    self.mountStates.removeValue(forKey: key)
                    self.mountTimers[key]?.invalidate()
                    self.mountTimers.removeValue(forKey: key)
                }
                self.recomputeStatus()
            }
        }
    }

    func tryMount(_ partition: PartitionDevice) {
        let node = partition.node
        mountStates[partition.id] = .trying(secondsLeft: 30)

        var remaining = 30
        mountTimers[partition.id]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                remaining -= 1
                if case .trying = self.mountStates[partition.id] ?? .idle, remaining > 0 {
                    self.mountStates[partition.id] = .trying(secondsLeft: remaining)
                } else {
                    t.invalidate()
                }
            }
        }
        mountTimers[partition.id] = timer

        DiskService.mountReadOnly(node: node) { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                self.mountTimers[partition.id]?.invalidate()
                self.mountTimers[partition.id] = nil
                self.mountStates[partition.id] = state
                self.recomputeStatus()
            }
        }
    }

    func startLogStream() {
        guard !isStreaming else { return }
        isStreaming = true
        logEntries.removeAll()
        streamer.start("/usr/bin/log", ["stream", "--style", "compact", "--predicate", logPredicate]) { [weak self] line in
            guard let self else { return }
            let entry = LogEntry.make(line)
            self.logEntries.append(entry)
            if self.logEntries.count > 500 {
                self.logEntries.removeFirst(self.logEntries.count - 500)
            }
            if entry.isWarning {
                self.lastWarningAt = Date()
                self.recomputeStatus()
            }
        }
    }

    func stopLogStream() {
        isStreaming = false
        streamer.stop()
    }

    private func recomputeStatus() {
        if disks.isEmpty {
            overallStatus = .quiet
            return
        }
        let recentWarning = lastWarningAt.map { Date().timeIntervalSince($0) < warningDecay } ?? false
        let mountTrouble = mountStates.values.contains { state in
            switch state {
            case .timedOut, .disconnected, .failed: return true
            default: return false
            }
        }
        overallStatus = (recentWarning || mountTrouble) ? .struggling : .healthy
    }
}
