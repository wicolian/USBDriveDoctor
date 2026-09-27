import Foundation

enum DiskService {

    /// Lists /dev/diskN and /dev/diskNsM device names cheaply, straight from
    /// the filesystem - never shells out to `diskutil list`, which is the
    /// command that hangs when a flaky drive is attached.
    static func listDeviceNames() -> (wholeDisks: [String], partitions: [String: [String]]) {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else {
            return ([], [:])
        }
        let wholeRegex = try! NSRegularExpression(pattern: "^disk[0-9]+$")
        let partRegex = try! NSRegularExpression(pattern: "^(disk[0-9]+)s[0-9]+$")

        var wholeDisks: [String] = []
        var partitions: [String: [String]] = [:]

        for name in entries {
            let range = NSRange(name.startIndex..., in: name)
            if wholeRegex.firstMatch(in: name, range: range) != nil {
                wholeDisks.append(name)
            } else if let match = partRegex.firstMatch(in: name, range: range),
                      let wholeRange = Range(match.range(at: 1), in: name) {
                let whole = String(name[wholeRange])
                partitions[whole, default: []].append(name)
            }
        }
        wholeDisks.sort()
        for k in partitions.keys { partitions[k]?.sort() }
        return (wholeDisks, partitions)
    }

    /// Parses `diskutil info <node>` output into a [String: String] of its
    /// "Label:  Value" lines. Wrapped with a timeout so a stuck drive can't
    /// freeze the caller.
    static func fetchInfo(node: String, timeout: TimeInterval = 8, completion: @escaping ([String: String]?, _ timedOut: Bool) -> Void) {
        ProcessRunner.run("/usr/sbin/diskutil", ["info", node], timeout: timeout) { output in
            if output.timedOut {
                completion(nil, true)
                return
            }
            completion(parseInfoBlock(output.text), false)
        }
    }

    private static func parseInfoBlock(_ text: String) -> [String: String] {
        var dict: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let colonRange = line.range(of: ":") else { continue }
            let key = line[line.startIndex..<colonRange.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                dict[key] = value
            }
        }
        return dict
    }

    /// Runs `ioreg -p IOUSB -w0 -l` and maps each USB device's product name
    /// to its negotiated link speed. Fast and never hangs even with a flaky
    /// drive attached, because it just reads kernel-exposed properties.
    static func fetchUSBSpeeds(timeout: TimeInterval = 5, completion: @escaping ([String: Double]) -> Void) {
        ProcessRunner.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-w0", "-l"], timeout: timeout) { output in
            guard !output.timedOut else { completion([:]); return }
            completion(parseIORegSpeeds(output.text))
        }
    }

    private static func parseIORegSpeeds(_ text: String) -> [String: Double] {
        var result: [String: Double] = [:]
        var currentName: String?
        var currentSpeed: Double?

        func flush() {
            if let name = currentName, let speed = currentSpeed {
                result[name] = speed
            }
            currentName = nil
            currentSpeed = nil
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("+-o "), line.contains("<class IOUSBHostDevice") {
                flush()
                continue
            }
            if line.hasPrefix("\"USB Product Name\" =") || line.hasPrefix("\"kUSBProductString\" =") {
                if let value = extractQuotedValue(line) {
                    currentName = value
                }
            }
            if line.hasPrefix("\"UsbLinkSpeed\" =") {
                let numeric = line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces)
                if let numeric, let value = Double(numeric) {
                    currentSpeed = value
                }
            }
        }
        flush()
        return result
    }

    private static func extractQuotedValue(_ line: String) -> String? {
        let parts = line.components(separatedBy: "=")
        guard parts.count > 1 else { return nil }
        var value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return value
    }

    /// Attempts a READ-ONLY mount of a single partition device. Never passes
    /// any write/erase/repair option. Runs on a timeout so a hung diskutil
    /// call surfaces as "timed out", not a frozen UI.
    ///
    /// SAFETY INVARIANT: this is one of exactly two diskutil calls this whole
    /// app is allowed to make (the other is `diskutil info`, which is
    /// read-only by nature). Every invocation of `diskutil mount` in this
    /// codebase MUST include "readOnly". Never add erase, format, repair, or
    /// First Aid anywhere - see README.md's "Permanent safety invariant".
    static func mountReadOnly(node: String, timeout: TimeInterval = 30, completion: @escaping (MountAttemptState) -> Void) {
        ProcessRunner.run("/usr/sbin/diskutil", ["mount", "readOnly", node], timeout: timeout) { output in
            if output.timedOut {
                completion(nodeExists(node) ? .timedOut : .disconnected)
                return
            }
            if output.terminationStatus == 0 {
                completion(.success)
            } else if !nodeExists(node) {
                completion(.disconnected)
            } else {
                completion(.failed(output.text.isEmpty ? "diskutil reported an error" : output.text))
            }
        }
    }

    /// Cheap existence check (no shelling out) used to tell "the drive fell
    /// off the bus mid-attempt" apart from "diskutil returned a real error".
    static func nodeExists(_ node: String) -> Bool {
        FileManager.default.fileExists(atPath: node)
    }
}
