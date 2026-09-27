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
    @Published var mountProgress: [String: MountProgress] = [:]
    /// Whether "keep trying automatically" is currently active for a given
    /// partition. On by default the moment a mount is requested - Koushik's
    /// words were "auto try and mount regardless what" - and stays on across
    /// retries until either it succeeds or the user explicitly stops it.
    @Published var autoRetryEnabled: [String: Bool] = [:]
    @Published private(set) var overallStatus: OverallStatus = .quiet

    private var mountTickers: [String: Timer] = [:]      // 1s elapsed/watchdog ticker per partition
    private var retryWaitTimers: [String: Timer] = [:]   // backoff countdown between attempts
    private var throughputMonitors: [String: LineStreamer] = [:]
    /// Bumped every time a fresh attempt starts for a partition. A completion
    /// handler checks its captured generation before applying anything, so a
    /// stale result from an attempt that's already been superseded by a
    /// retry (or cancelled) can't clobber newer state.
    private var mountGeneration: [String: Int] = [:]
    private var activeMountProcesses: [String: Process] = [:]
    private var retryCounts: [String: Int] = [:]

    private var refreshTimer: Timer?
    private var statusTimer: Timer?
    private var lastWarningAt: Date?
    private let streamer = LineStreamer()

    /// Escalating pause between auto-retry attempts: a drive that just
    /// disconnected benefits from a few seconds' rest, not an instant
    /// re-slam, but we also don't want minutes of silence. Caps out rather
    /// than growing forever.
    private func backoffSeconds(forAttempt attempt: Int) -> Int {
        min(3 * attempt, 30)
    }

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
        for timer in mountTickers.values { timer.invalidate() }
        for timer in retryWaitTimers.values { timer.invalidate() }
        for monitor in throughputMonitors.values { monitor.stop() }
        for process in activeMountProcesses.values where process.isRunning { process.terminate() }
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
                    self.mountProgress.removeValue(forKey: key)
                    self.autoRetryEnabled.removeValue(forKey: key)
                    self.retryCounts.removeValue(forKey: key)
                    self.mountGeneration.removeValue(forKey: key)
                    self.mountTickers[key]?.invalidate()
                    self.mountTickers.removeValue(forKey: key)
                    self.retryWaitTimers[key]?.invalidate()
                    self.retryWaitTimers.removeValue(forKey: key)
                    self.throughputMonitors[key]?.stop()
                    self.throughputMonitors.removeValue(forKey: key)
                    self.activeMountProcesses[key]?.terminate()
                    self.activeMountProcesses.removeValue(forKey: key)
                }
                self.recomputeStatus()
            }
        }
    }

    /// Starts (or restarts) a read-only mount attempt for a partition, with
    /// auto-retry on by default: "auto try and mount regardless what" means
    /// a failure, a timeout, or the drive disconnecting mid-attempt all lead
    /// to another attempt after a short rest, not a dead end that waits for
    /// another click. `resetRetries` is false when this is called internally
    /// by the retry loop itself, so the attempt counter keeps climbing
    /// instead of resetting to 1 every time.
    func tryMount(_ partition: PartitionDevice, resetRetries: Bool = true) {
        let id = partition.id
        let node = partition.node

        if resetRetries {
            retryCounts[id] = 0
            autoRetryEnabled[id] = true
        }
        retryWaitTimers[id]?.invalidate()
        retryWaitTimers[id] = nil

        let attempt = (retryCounts[id] ?? 0) + 1
        retryCounts[id] = attempt
        let generation = (mountGeneration[id] ?? 0) + 1
        mountGeneration[id] = generation

        mountStates[id] = .trying
        mountProgress[id] = MountProgress(attempt: attempt, secondsElapsed: 0, throughputMBps: nil,
                                           phase: "Starting mount attempt…")
        recomputeStatus()

        startThroughputMonitor(for: id, wholeDisk: node.replacingOccurrences(of: "/dev/", with: "").wholeDiskName, generation: generation)

        mountTickers[id]?.invalidate()
        mountTickers[id] = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mountGeneration[id] == generation else { return }

                if !DiskService.nodeExists(node) {
                    self.finishAttempt(.disconnected, partitionId: id, generation: generation)
                    return
                }

                var progress = self.mountProgress[id] ?? MountProgress(attempt: attempt)
                progress.secondsElapsed += 1
                if progress.secondsElapsed >= 3 {
                    progress.phase = progress.throughputMBps != nil
                        ? MountProgress.indexingPhase
                        : "Still connecting…"
                }
                self.mountProgress[id] = progress
            }
        }

        let process = DiskService.mountReadOnly(node: node) { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                self.finishAttempt(state, partitionId: id, generation: generation)
            }
        }
        activeMountProcesses[id] = process
    }

    /// Turns off auto-retry for a partition and, if an attempt is currently
    /// in flight or waiting out a backoff pause, stops that too. This is the
    /// user's "stop retrying" control - auto-retry is generous by default,
    /// but never a trap with no way out.
    func stopRetrying(_ partitionId: String) {
        autoRetryEnabled[partitionId] = false
        retryWaitTimers[partitionId]?.invalidate()
        retryWaitTimers[partitionId] = nil

        if case .retryWaiting = mountStates[partitionId] ?? .idle {
            mountStates[partitionId] = .idle
            mountProgress.removeValue(forKey: partitionId)
        }

        activeMountProcesses[partitionId]?.terminate()
        activeMountProcesses.removeValue(forKey: partitionId)
        recomputeStatus()
    }

    /// Common landing point for every attempt outcome (success, real
    /// failure, timeout, or disconnect), whether it came from the diskutil
    /// completion handler or from this app's own faster disconnect watchdog.
    /// Guards on `generation` so a stale result from a superseded attempt
    /// can never overwrite newer state.
    private func finishAttempt(_ state: MountAttemptState, partitionId: String, generation: Int) {
        guard mountGeneration[partitionId] == generation else { return }

        mountTickers[partitionId]?.invalidate()
        mountTickers[partitionId] = nil
        stopThroughputMonitor(for: partitionId)
        activeMountProcesses.removeValue(forKey: partitionId)

        mountStates[partitionId] = state
        recomputeStatus()

        switch state {
        case .success, .idle:
            mountProgress.removeValue(forKey: partitionId)
            retryCounts[partitionId] = 0
        case .timedOut, .disconnected, .failed:
            if autoRetryEnabled[partitionId] == true {
                scheduleRetry(partitionId: partitionId, generation: generation)
            } else {
                mountProgress.removeValue(forKey: partitionId)
            }
        case .trying, .retryWaiting:
            break // not a terminal state; shouldn't reach here
        }
    }

    private func scheduleRetry(partitionId: String, generation: Int) {
        let attempt = retryCounts[partitionId] ?? 1
        var secondsLeft = backoffSeconds(forAttempt: attempt)
        mountStates[partitionId] = .retryWaiting(resumesIn: secondsLeft)
        recomputeStatus()

        retryWaitTimers[partitionId]?.invalidate()
        retryWaitTimers[partitionId] = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, self.mountGeneration[partitionId] == generation,
                      self.autoRetryEnabled[partitionId] == true else {
                    timer.invalidate()
                    return
                }
                secondsLeft -= 1
                if secondsLeft <= 0 {
                    timer.invalidate()
                    self.retryWaitTimers[partitionId] = nil
                    // Look up the current partition by id - if the drive is
                    // truly gone (not just resting), it won't be found, and
                    // we stop rather than retry into thin air.
                    guard let partition = self.disks.flatMap(\.partitions).first(where: { $0.id == partitionId }) else {
                        self.mountStates[partitionId] = .disconnected
                        self.recomputeStatus()
                        return
                    }
                    self.tryMount(partition, resetRetries: false)
                } else {
                    self.mountStates[partitionId] = .retryWaiting(resumesIn: secondsLeft)
                }
            }
        }
    }

    private func startThroughputMonitor(for partitionId: String, wholeDisk: String, generation: Int) {
        stopThroughputMonitor(for: partitionId)
        let monitor = LineStreamer()
        throughputMonitors[partitionId] = monitor
        monitor.start("/usr/sbin/iostat", ["-w", "1", wholeDisk]) { [weak self] line in
            guard let self, self.mountGeneration[partitionId] == generation,
                  let mbps = DiskService.parseIostatMBps(line) else { return }
            var progress = self.mountProgress[partitionId] ?? MountProgress()
            progress.throughputMBps = mbps
            progress.phase = MountProgress.indexingPhase
            self.mountProgress[partitionId] = progress
        }
    }

    private func stopThroughputMonitor(for partitionId: String) {
        throughputMonitors[partitionId]?.stop()
        throughputMonitors.removeValue(forKey: partitionId)
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
            case .timedOut, .disconnected, .failed, .retryWaiting: return true
            default: return false
            }
        }
        overallStatus = (recentWarning || mountTrouble) ? .struggling : .healthy
    }
}
