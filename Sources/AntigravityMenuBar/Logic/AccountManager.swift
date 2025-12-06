import Foundation

struct Account: Codable, Identifiable {
    let id: String
    var name: String
    var email: String?
    let backup_file: String
    let created_at: String
    var last_used: String?
}

class AccountManager: ObservableObject {
    static let shared = AccountManager()
    
    @Published var accounts: [Account] = []
    
    private init() {
        loadAccounts()
    }
    
    private var appDataDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".antigravity-agent")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var accountsFile: URL {
        return appDataDir.appendingPathComponent("antigravity_accounts.json")
    }
    
    func loadAccounts() {
        guard FileManager.default.fileExists(atPath: accountsFile.path),
              let data = try? Data(contentsOf: accountsFile),
              let json = try? JSONDecoder().decode([String: Account].self, from: data) else {
            self.accounts = []
            return
        }
        
        self.accounts = Array(json.values).sorted {
            ($0.last_used ?? "") > ($1.last_used ?? "")
        }
    }
    
    func saveAccounts() {
        var dict: [String: Account] = [:]
        for acc in accounts {
            dict[acc.id] = acc
        }
        
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: accountsFile)
        }
    }
    
    func addCurrentAccount() -> Bool {
        // 1. Get Info
        let email = DBManager.shared.getCurrentAccountEmail() ?? "Unknown"
        let name = email != "Unknown" ? email.components(separatedBy: "@").first ?? "Account" : "Account_\(Int(Date().timeIntervalSince1970))"
        
        // 2. Check existing
        var accountId = UUID().uuidString
        var backupPath = appDataDir.appendingPathComponent("backups/\(accountId).json")
        
        if let existing = accounts.first(where: { $0.email == email }) {
            print("Update existing backup for \(email)")
            accountId = existing.id
            backupPath = URL(fileURLWithPath: existing.backup_file)
        } else {
            // Create backup dir
            let backupDir = appDataDir.appendingPathComponent("backups")
            try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        }
        
        // 3. Backup DB
        guard let data = DBManager.shared.backupData() else {
            return false
        }
        
        // Write JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]) else {
            return false
        }
        
        do {
            try jsonData.write(to: backupPath)
        } catch {
            print("❌ Failed to write backup file: \(error)")
            return false
        }
        
        // 4. Update List
        let newAccount = Account(
            id: accountId,
            name: name,
            email: email,
            backup_file: backupPath.path,
            created_at: Date().ISO8601Format(),
            last_used: Date().ISO8601Format()
        )
        
        if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
            accounts[idx] = newAccount
        } else {
            accounts.append(newAccount)
        }
        
        saveAccounts()
        loadAccounts() // Refresh sort
        return true
    }
    
    func switchAccount(id: String) -> Bool {
        guard let account = accounts.first(where: { $0.id == id }) else { return false }
        
        print("🔄 Switching to \(account.name)...")
        
        // 1. Close App
        _ = ProcessManager.shared.closeApp()
        
        // 2. Read Backup
        let backupUrl = URL(fileURLWithPath: account.backup_file)
        guard let data = try? Data(contentsOf: backupUrl),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
            print("❌ Failed to read backup file")
            return false
        }
        
        // 3. Restore DB
        if DBManager.shared.restoreData(json) {
            // Update Last Used
            if let idx = accounts.firstIndex(where: { $0.id == id }) {
                accounts[idx].last_used = Date().ISO8601Format()
                saveAccounts()
                loadAccounts()
            }
            
            // 4. Start App
            ProcessManager.shared.startApp()
            return true
        }
        
        return false
    }
}
