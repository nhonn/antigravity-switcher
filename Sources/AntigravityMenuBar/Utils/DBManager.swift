import Foundation
import SQLite3

class DBManager {
    static let shared = DBManager()
    
    // Keys to backup, matching Python version
    private let keysToBackup = [
        "antigravityAuthStatus",
        "jetskiStateSync.agentManagerInitState"
    ]
    
    private init() {}
    
    // Get Antigravity DB Paths
    private func getDBPaths() -> [String] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        // Standard path: ~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb
        let standardPath = home.appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb").path
        
        // Fallback path
        let fallbackPath = home.appendingPathComponent("Library/Application Support/Antigravity/state.vscdb").path
        
        return [standardPath, fallbackPath]
    }
    
    // Backup data from DB to dictionary
    func backupData() -> [String: String]? {
        let dbPaths = getDBPaths()
        guard let dbPath = dbPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            print("❌ Database not found")
            return nil
        }
        
        print("📂 Opening database: \(dbPath)")
        
        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Error opening database")
            return nil
        }
        defer { sqlite3_close(db) }
        
        var data: [String: String] = [:]
        
        for key in keysToBackup {
            let query = "SELECT value FROM ItemTable WHERE key = ?"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(statement, 0) {
                        let value = String(cString: cString)
                        data[key] = value
                    }
                }
            }
            sqlite3_finalize(statement)
        }
        
        // Try to get email for metadata
        // 1. antigravityAuthStatus
        if let authStatus = data["antigravityAuthStatus"] {
            // Simple string search for email to avoid full JSON parsing if possible, or parse it properly
            // Python version does simple check. We'll parse in AccountManager.
        }
        
        return data
    }
    
    // Restore data from dictionary to DB
    func restoreData(_ data: [String: String]) -> Bool {
        let dbPaths = getDBPaths()
        var success = false
        
        for dbPath in dbPaths {
            // Check main DB
            if FileManager.default.fileExists(atPath: dbPath) {
                if restoreSingleDB(path: dbPath, data: data) {
                    success = true
                }
            }
            
            // Check backup DB
            let backupPath = dbPath + ".backup"
            if FileManager.default.fileExists(atPath: backupPath) {
                _ = restoreSingleDB(path: backupPath, data: data)
            }
        }
        
        return success
    }
    
    private func restoreSingleDB(path: String, data: [String: String]) -> Bool {
        print("♻️ Restoring database: \(path)")
        
        var db: OpaquePointer?
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("❌ Error opening database for restore")
            return false
        }
        defer { sqlite3_close(db) }
        
        for (key, value) in data {
            // Only restore known keys
            if keysToBackup.contains(key) {
                let query = "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)"
                var statement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (value as NSString).utf8String, -1, nil)
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        print("❌ Error writing key: \(key)")
                    }
                }
                sqlite3_finalize(statement)
            }
        }
        
        return true
    }
    
    // Get current account info (email)
    func getCurrentAccountEmail() -> String? {
        // Reuse backupData logic to fetch values
        guard let data = backupData() else { return nil }
        
        // 1. Check antigravityAuthStatus
        if let val = data["antigravityAuthStatus"],
           let email = extractEmail(from: val) {
            return email
        }
        
        return nil
    }
    
    private func extractEmail(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        
        if let email = json["email"] as? String {
            return email
        }
        
        return nil
    }
}
