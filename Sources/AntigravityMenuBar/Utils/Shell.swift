import Foundation

enum ShellError: LocalizedError {
    case nonZeroExit(command: String, exitCode: Int32, stderr: String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let command, let exitCode, let stderr):
            return "Command failed (exit \(exitCode)): \(command)\n\(stderr)"
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

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Simple timeout
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let cmd = ([launchPath] + arguments).joined(separator: " ")
            throw ShellError.nonZeroExit(command: cmd, exitCode: process.terminationStatus, stderr: stderr)
        }

        return (stdout: stdout, stderr: stderr)
    }
}
