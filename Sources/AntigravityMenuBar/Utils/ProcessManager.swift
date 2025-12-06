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
        
        // 1. AppleScript Graceful Exit
        let script = "tell application \"Antigravity\" to quit"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
        
        // Wait a bit
        Thread.sleep(forTimeInterval: 2.0)
        
        // 2. Check and Terminate if still running
        let apps = NSWorkspace.shared.runningApplications
        var stillRunning = false
        
        for app in apps {
            if let name = app.localizedName?.lowercased(), name.contains("antigravity") {
                if !app.isTerminated {
                    print("⚠️ Force terminating: \(app.localizedName ?? "")")
                    app.terminate()
                    stillRunning = true
                }
            }
        }
        
        if stillRunning {
            Thread.sleep(forTimeInterval: 1.0)
        }
        
        return true
    }
    
    // Start Antigravity
    func startApp() {
        print("🚀 Starting Antigravity...")
        
        // Use URI scheme
        if let url = URL(string: "antigravity://oauth-success") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback to open app by name
            let config = NSWorkspace.OpenConfiguration()
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ctrler.antigravity") ?? 
                           NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.antigravity.app") { // Guess bundle ID
                NSWorkspace.shared.openApplication(at: appUrl, configuration: config, completionHandler: nil)
            } else {
                 // Fallback shell command
                 let process = Process()
                 process.launchPath = "/usr/bin/open"
                 process.arguments = ["-a", "Antigravity"]
                 process.launch()
            }
        }
    }
}
