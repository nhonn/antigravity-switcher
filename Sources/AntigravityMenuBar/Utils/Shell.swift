import Foundation

enum ShellError: LocalizedError {
    case nonZeroExit(command: String, exitCode: Int32, stderr: String)
    case timeout(command: String, timeoutSeconds: TimeInterval)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let command, let exitCode, let stderr):
            return "Command failed (exit \(exitCode)): \(command)\n\(stderr)"
        case .timeout(let command, let timeoutSeconds):
            return "Command timed out after \(timeoutSeconds)s: \(command)"
        case .invalidOutput:
            return "Invalid command output"
        }
    }
}

final class Shell {
    static func run(_ launchPath: String, _ arguments: [String], timeoutSeconds: TimeInterval = 5) throws -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let commandString = ([launchPath] + arguments).joined(separator: " ")

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Read pipes incrementally while the process runs, to avoid deadlocks when output is large.
        var stdoutData = Data()
        var stderrData = Data()
        let lock = NSLock()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            lock.lock()
            stdoutData.append(chunk)
            lock.unlock()
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            lock.lock()
            stderrData.append(chunk)
            lock.unlock()
        }

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            done.signal()
        }

        try process.run()

        let waitResult = done.wait(timeout: .now() + timeoutSeconds)
        let didTimeout = (waitResult == .timedOut)
        if didTimeout {
            process.terminate()
            _ = done.wait(timeout: .now() + 1.0)
        }

        // Stop handlers and drain any remaining data.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        lock.lock()
        stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        lock.unlock()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if didTimeout {
            throw ShellError.timeout(command: commandString, timeoutSeconds: timeoutSeconds)
        }

        if process.terminationStatus != 0 {
            throw ShellError.nonZeroExit(command: commandString, exitCode: process.terminationStatus, stderr: stderr)
        }

        return (stdout: stdout, stderr: stderr)
    }
}
