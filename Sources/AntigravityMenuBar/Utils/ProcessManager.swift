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
        return !isRunning()
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
