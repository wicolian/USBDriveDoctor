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
    case trying(secondsLeft: Int)
    case success
    case timedOut
    case disconnected
    case failed(String)
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
