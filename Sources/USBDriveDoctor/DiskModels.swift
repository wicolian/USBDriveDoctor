import Foundation

enum USBSpeed: Equatable {
    case highSpeed        // 480 Mbps - USB 2.0, never uses UAS/streams
    case superSpeed       // 5 Gbps - USB 3.0, uses UAS/streams
    case superSpeedPlus    // 10 Gbps+
    case unknown

    static func from(linkSpeedHz: Double?) -> USBSpeed {
        guard let v = linkSpeedHz else { return .unknown }
        if v >= 10_000_000_000 { return .superSpeedPlus }
        if v >= 5_000_000_000 { return .superSpeed }
        if v >= 480_000_000 { return .highSpeed }
        return .unknown
    }

    var label: String {
        switch self {
        case .highSpeed: return "USB 2.0 High-Speed (480 Mbps)"
        case .superSpeed: return "USB 3.0 SuperSpeed (5 Gbps)"
        case .superSpeedPlus: return "USB 3.1+ SuperSpeed+ (10 Gbps)"
        case .unknown: return "Unknown speed"
        }
    }

    /// UAS (USB Attached SCSI) with its "streams" feature only exists at
    /// SuperSpeed and above. At High-Speed, drives always fall back to the
    /// older, more forgiving Bulk-Only Transport.
    var usesUAS: Bool {
        self == .superSpeed || self == .superSpeedPlus
    }
}

struct PartitionDevice: Identifiable, Equatable {
    let id: String // e.g. "disk4s2"
    var node: String { "/dev/\(id)" }
    var volumeName: String = "-"
    var fileSystem: String = "-"
    var mounted: Bool = false
    var sizeString: String = "-"
}

struct DiskDevice: Identifiable, Equatable {
    let id: String // e.g. "disk4"
    var node: String { "/dev/\(id)" }
    var mediaName: String = "Unknown device"
    var sizeString: String = "-"
    var protocolName: String = "-"
    var usbSpeed: USBSpeed = .unknown
    var smartStatus: String = "-"
    var content: String = "-"
    var isExternal: Bool = true
    var partitions: [PartitionDevice] = []
}

enum MountAttemptState: Equatable {
    case idle
    /// Live detail (attempt number, elapsed time, throughput, phase text)
    /// lives in `MountProgress`, keyed separately in `AppModel` - this case
    /// just marks "an attempt is in flight."
    case trying
    /// Auto-retry is paused between attempts, counting down to the next one.
    case retryWaiting(resumesIn: Int)
    case success
    case timedOut
    case disconnected
    case failed(String)
}

/// Real, honest signal about an in-flight mount attempt. No fabricated
/// percentage or ETA - `diskutil mount` doesn't expose one, and guessing
/// one would be exactly the kind of false hope this app exists to avoid.
/// Elapsed time and live read throughput (from `iostat`) are the only two
/// numbers we can actually know, so those are what's shown.
struct MountProgress: Equatable {
    var attempt: Int = 1
    var secondsElapsed: Int = 0
    var throughputMBps: Double?
    var phase: String = "Starting mount attempt…"

    /// Once a drive is actually transferring data, the overwhelmingly likely
    /// reason a read-only exFAT/NTFS mount is still running is that it's
    /// walking every folder's directory entries across the whole volume -
    /// this is real, not a guess (verified by hand tonight with `iostat`
    /// against Koushik's actual drive: steady throughput, ~39 minutes, for
    /// 1.8TB of files). Only speak to that once there's actually a nonzero
    /// read rate to point to.
    static let indexingPhase = "Reading directory tables… large or struggling drives can take a long time here."
}

extension String {
    /// "disk4s2" -> "disk4". Whole-disk `iostat` needs the disk name without
    /// its partition suffix.
    var wholeDiskName: String {
        guard let sRange = range(of: "s", options: .backwards) else { return self }
        let suffix = self[sRange.upperBound...]
        return suffix.allSatisfy(\.isNumber) && !suffix.isEmpty ? String(self[..<sRange.lowerBound]) : self
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let text: String
    let isWarning: Bool

    static let warningPhrases = [
        "hardware connection lost",
        "abortGated",
        "aborting",
        "transaction error",
        "terminateDevice",
    ]

    static func make(_ text: String) -> LogEntry {
        let flagged = warningPhrases.contains { text.localizedCaseInsensitiveContains($0) }
        return LogEntry(text: text, isWarning: flagged)
    }
}

/// Overall at-a-glance health, driven by the live log stream and any mount
/// attempts in flight. This is what the menu bar icon reflects.
enum OverallStatus {
    case quiet       // no external disks attached
    case healthy     // disks attached, nothing concerning seen recently
    case struggling  // a disconnect/abort was seen recently, or a mount attempt failed/timed out/disconnected

    var symbolName: String {
        switch self {
        case .quiet: return "externaldrive"
        case .healthy: return "externaldrive.fill"
        case .struggling: return "externaldrive.badge.exclamationmark"
        }
    }
}
