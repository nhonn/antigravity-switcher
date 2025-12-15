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
        "jetskiStateSync.agentManagerInitState",
        // Additional Antigravity state that can be account-specific and may affect quota/session behavior
        "antigravityUserSettings.allUserSettings",
        "antigravity_allowed_command_model_configs",
        "antigravityOnboarding",
        "antigravity.profileUrl",
        "antigravityChangelog/lastVersion",
        "antigravityAnalytics.lastUploadTime",
        "antigravity.agentViewContainerId.state.hidden"
    ]
    
    // MARK: - Bundle IDs
    let antigravityBundleIds = [
        "com.ctrler.antigravity",
        "com.google.antigravity"
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
