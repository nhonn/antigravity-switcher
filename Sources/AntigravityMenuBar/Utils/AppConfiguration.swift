import Foundation

final class AppConfiguration {
    static var shared = AppConfiguration()
    
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
    
    // MARK: - UserDefaults Keys
    private enum UserDefaultsKeys {
        static let autoBackupBeforeSwitch = "autoBackupBeforeSwitch"
        static let launchAtLogin = "launchAtLogin"
        static let showNotifications = "showNotifications"
    }
    
    // MARK: - Settings
    var autoBackupBeforeSwitch: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoBackupBeforeSwitch) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.autoBackupBeforeSwitch) }
    }
    
    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKeys.launchAtLogin) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.launchAtLogin) }
    }
    
    var showNotifications: Bool {
        get { UserDefaults.standard.object(forKey: UserDefaultsKeys.showNotifications) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.showNotifications) }
    }
    
    private init() {}
}
