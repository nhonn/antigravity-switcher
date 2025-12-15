import Foundation
import AppKit

class ProcessManager {
    static let shared = ProcessManager()
    
    private init() {}
    
    // Check if Antigravity is running
    func isRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            if let name = app.localizedName?.lowercased(), name.contains("antigravity") {
                return true
            }
            if let bundleId = app.bundleIdentifier?.lowercased(), bundleId.contains("antigravity") {
                return true
            }
        }
        return false
    }
    
    // Close Antigravity
    func closeApp() -> Bool {
        print("🛑 Closing Antigravity...")
        
        // Find running instances by Bundle ID
        let bundleIds = AppConfiguration.shared.antigravityBundleIds
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            if let bid = app.bundleIdentifier {
                return bundleIds.contains(bid)
            }
            return false
        }
        
        if runningApps.isEmpty {
            print("⚠️ No running Antigravity instances found.")
            return true
        }
        
        for app in runningApps {
            print("Attempting to close: \(app.localizedName ?? "Unknown") (\(app.bundleIdentifier ?? ""))")
            
            // 1. Try standard terminate
            app.terminate()
            
            // 2. Wait and check
            var attempts = 0
            while !app.isTerminated && attempts < 10 {
                Thread.sleep(forTimeInterval: 0.5)
                attempts += 1
            }
            
            // 3. Force terminate if still running
            if !app.isTerminated {
                print("⚠️ Application stuck, forcing termination...")
                app.forceTerminate()
            }
        }
        
        // Final verification
        Thread.sleep(forTimeInterval: 1.0)
        // Antigravity sometimes leaves the language server running briefly.
        // Best-effort cleanup to avoid stale account state.
        terminateLanguageServers()
        return !isRunning()
    }

    /// Best-effort termination of Antigravity language server processes.
    ///
    /// When switching accounts, a leftover language server can keep the previous
    /// session and cause quota checks to reflect the old account.
    func terminateLanguageServers() {
        do {
            let ps = try Shell.run("/bin/ps", ["-ax", "-o", "pid=,command="], timeoutSeconds: 6)
            let lines = ps.stdout.split(separator: "\n").map(String.init)

            let candidates: [(pid: Int, cmd: String)] = lines.compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return nil }
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
                let cmd = String(parts[1])
                let lower = cmd.lowercased()

                // Prefer the specific Antigravity extension language server.
                if lower.contains("/extensions/antigravity/bin/language_server") ||
                    lower.contains("language_server_macos") ||
                    (lower.contains("language_server") && lower.contains("--csrf_token")) {
                    return (pid: pid, cmd: cmd)
                }
                return nil
            }

            guard !candidates.isEmpty else { return }
            print("🧹 Terminating language server(s): \(candidates.map { String($0.pid) }.joined(separator: ", "))")

            for (pid, _) in candidates {
                _ = try? Shell.run("/bin/kill", ["-TERM", String(pid)], timeoutSeconds: 2)
            }

            // Wait a bit for graceful shutdown, then force kill if needed.
            for (pid, _) in candidates {
                var alive = true
                for _ in 0..<25 {
                    if (try? Shell.run("/bin/kill", ["-0", String(pid)], timeoutSeconds: 1)) == nil {
                        alive = false
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                if alive {
                    print("⚠️ Language server \(pid) still running, forcing...")
                    _ = try? Shell.run("/bin/kill", ["-KILL", String(pid)], timeoutSeconds: 2)
                }
            }
        } catch {
            // Best-effort only.
            return
        }
    }
    
    // Start Antigravity
    func startApp() {
        print("🚀 Starting Antigravity...")
        
        // Method 1: Try URI scheme (Original behavior)
        if let url = URL(string: AppConfiguration.shared.antigravityLinkScheme) {
            print("Trying URL scheme: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            // Give it a moment to see if it launches
            Thread.sleep(forTimeInterval: 1.0)
            if isRunning() {
                print("✅ Started via URL scheme")
                return
            }
        }
        
        // Method 2: Open by Bundle ID
        for bundleId in AppConfiguration.shared.antigravityBundleIds {
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                
                NSWorkspace.shared.openApplication(at: appUrl, configuration: config) { app, error in
                    if let error = error {
                        print("❌ Failed to open by Bundle ID \(bundleId): \(error.localizedDescription)")
                    } else {
                        print("✅ Started \(app?.localizedName ?? "App")")
                    }
                }
                return
            }
        }
        
        // Method 3: Fallback to simple shell command "open -a Antigravity"
        print("⚠️ Bundle ID launch failed, trying 'open -a Antigravity'...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Antigravity"]
        try? process.run()
    }
}
