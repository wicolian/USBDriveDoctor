import Foundation

/// Runs a subprocess with a hard timeout so a hung `diskutil` call
/// (which can block for minutes on a flaky USB drive) never freezes the app.
enum ProcessRunner {

    struct Output {
        let text: String
        let timedOut: Bool
        let terminationStatus: Int32
    }

    /// Runs a command, collecting output incrementally (never blocks waiting
    /// for EOF), and kills it after `timeout` seconds if it hasn't finished.
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval, completion: @escaping (Output) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let bufferLock = NSLock()
        var buffer = Data()
        var timedOut = false
        var finished = false

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                bufferLock.lock()
                buffer.append(data)
                bufferLock.unlock()
            }
        }

        let timeoutItem = DispatchWorkItem {
            if process.isRunning {
                timedOut = true
                process.terminate()
                // Give it a moment, then force-kill if still alive.
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
        }

        process.terminationHandler = { proc in
            guard !finished else { return }
            finished = true
            timeoutItem.cancel()
            pipe.fileHandleForReading.readabilityHandler = nil
            bufferLock.lock()
            let text = String(data: buffer, encoding: .utf8) ?? ""
            bufferLock.unlock()
            completion(Output(text: text, timedOut: timedOut, terminationStatus: proc.terminationStatus))
        }

        do {
            try process.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        } catch {
            finished = true
            completion(Output(text: "", timedOut: false, terminationStatus: -1))
        }
    }
}

/// Streams a long-running command line-by-line (e.g. `log stream`), forever,
/// until stopped. Never waits for the process to exit.
final class LineStreamer {
    private var process: Process?
    private var pipe: Pipe?
    private var leftover = ""

    func start(_ launchPath: String, _ args: [String], onLine: @escaping (String) -> Void) {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self.leftover += chunk
            let lines = self.leftover.components(separatedBy: "\n")
            self.leftover = lines.last ?? ""
            for line in lines.dropLast() where !line.isEmpty {
                DispatchQueue.main.async { onLine(line) }
            }
        }

        do {
            try process.run()
            self.process = process
            self.pipe = pipe
        } catch {
            // Silently fail to start; UI will just show no log lines.
        }
    }

    func stop() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        pipe = nil
        leftover = ""
    }

    deinit { stop() }
}
