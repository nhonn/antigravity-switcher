import Foundation

struct AppConfiguration {
    static let shared = AppConfiguration()
    
    // MARK: - Paths
    let appDataDirectoryName = ".antigravity-agent"
    let accountsFileName = "antigravity_accounts.json"
    let backupsDirectoryName = "backups"
    
    // MARK: - Data Keys
    let keysToBackup = [
        "antigravityAuthStatus",
        "jetskiStateSync.agentManagerInitState"
    ]
    
    // MARK: - Bundle IDs
    let antigravityBundleIds = [
        "com.ctrler.antigravity",
        "com.antigravity.app"
    ]
    let antigravityLinkScheme = "antigravity://oauth-success"
    
    // MARK: - DB Paths
    var standardDBPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb")
            .path
    }
    
    var fallbackDBPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/state.vscdb")
            .path
    }
    
    private init() {}
}
