import Foundation

struct Account: Codable, Identifiable {
    let id: String
    var name: String
    var email: String?
    let backup_file: String
    let created_at: String
    var last_used: String?
    var time_limit: String?  // ISO8601 format for expiration date
}

/// Separate class for menu bar countdown to avoid triggering menu content refresh
class MenuBarState: ObservableObject {
    static let shared = MenuBarState()
    @Published var countdown: String = ""
    private init() {}
}

class AccountManager: ObservableObject {
    static let shared = AccountManager()
    
    @Published var accounts: [Account] = []
    @Published var currentEmail: String? = nil  // Currently active account email
    private var refreshTimer: Timer?
    
    private init() {
        loadAccounts()
        updateCurrentEmail()
        startRefreshTimer()
    }
    
    private struct QuotaCacheEntry {
        let snapshot: QuotaSnapshot
        let fetchedAt: Date
    }
    private var quotaCache: [String: QuotaCacheEntry] = [:]
    private let quotaCacheLock = NSLock()
    
    /// Update current email from database
    func updateCurrentEmail() {
        currentEmail = DBManager.shared.getCurrentAccountEmail()
    }
    
    private func startRefreshTimer() {
        // Create timer in common run loop mode so it runs even when menu is open
        refreshTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarCountdown()
        }
        // Add to common run loop mode for background updates
        RunLoop.main.add(refreshTimer!, forMode: .common)
        
        // Initial update
        updateMenuBarCountdown()
    }
    func cachedQuota(id: String, maxAgeSeconds: TimeInterval = 300) -> QuotaSnapshot? {
        quotaCacheLock.lock()
        defer { quotaCacheLock.unlock() }
        guard let entry = quotaCache[id] else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) > maxAgeSeconds {
            return nil
        }
        return entry.snapshot
    }
    
    private func setCachedQuota(id: String, snapshot: QuotaSnapshot) {
        quotaCacheLock.lock()
        quotaCache[id] = QuotaCacheEntry(snapshot: snapshot, fetchedAt: Date())
        quotaCacheLock.unlock()
    }
    
    /// Call this when menu is about to open to refresh content
    func refreshMenuContent() {
        updateCurrentEmail()  // Update active account status
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    private var menuRefreshCounter = 0
    
    private func updateMenuBarCountdown() {
        // Find all accounts with active countdown
        let activeAccounts = accounts.compactMap { account -> (Account, Date)? in
            guard let timeLimitStr = account.time_limit,
                  let timeLimit = ISO8601DateFormatter().date(from: timeLimitStr),
                  timeLimit > Date() else {
                return nil
            }
            return (account, timeLimit)
        }
        
        // Get the one with shortest time remaining
        guard let shortest = activeAccounts.min(by: { $0.1 < $1.1 }) else {
            // If we were showing a countdown and it just expired, also refresh the menu content
            // so the per-account labels drop the countdown immediately.
            let wasShowingCountdown = !MenuBarState.shared.countdown.isEmpty
            if wasShowingCountdown {
                DispatchQueue.main.async {
                    MenuBarState.shared.countdown = ""
                }
                refreshMenuContent()
            }
            return
        }
        
        // Format compact countdown for menu bar
        let newText = TimeLimitFormatter.formatMenuBarCountdown(to: shortest.1)
        if newText != MenuBarState.shared.countdown {
            DispatchQueue.main.async {
                MenuBarState.shared.countdown = newText
            }
        }
        
        // Refresh menu content every 5 seconds (compromise: less disruptive but keeps data fresh)
        menuRefreshCounter += 1
        if menuRefreshCounter >= 5 {
            menuRefreshCounter = 0
            refreshMenuContent()
        }
    }
    
    private var appDataDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(AppConfiguration.shared.appDataDirectoryName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var accountsFile: URL {
        return appDataDir.appendingPathComponent(AppConfiguration.shared.accountsFileName)
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
    
    func addCurrentAccount() async throws -> Account {
        // 1. Get Info
        let email = DBManager.shared.getCurrentAccountEmail() ?? "Unknown"
        let name = email != "Unknown" ? email.components(separatedBy: "@").first ?? "Account" : "Account_\(Int(Date().timeIntervalSince1970))"
        
        // 2. Check existing
        var accountId = UUID().uuidString
        var backupPath = appDataDir.appendingPathComponent("\(AppConfiguration.shared.backupsDirectoryName)/\(accountId).json")
        
        if let existing = accounts.first(where: { $0.email == email }) {
            print("Update existing backup for \(email)")
            accountId = existing.id
            backupPath = URL(fileURLWithPath: existing.backup_file)
        } else {
            // Create backup dir
            let backupDir = appDataDir.appendingPathComponent(AppConfiguration.shared.backupsDirectoryName)
            if !FileManager.default.fileExists(atPath: backupDir.path) {
                try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            }
        }
        
        // 3. Backup DB
        let data: [String: String]
        switch DBManager.shared.backupData() {
        case .success(let d):
            data = d
        case .failure(let error):
            throw error
        }
        
        // Write JSON
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted])
        try jsonData.write(to: backupPath)
        
        // 4. Update List
        let newAccount = Account(
            id: accountId,
            name: name,
            email: email,
            backup_file: backupPath.path,
            created_at: Date().ISO8601Format(),
            last_used: Date().ISO8601Format()
        )
        
        let finalAccountId = accountId
        
        await MainActor.run {
            if let idx = accounts.firstIndex(where: { $0.id == finalAccountId }) {
                accounts[idx] = newAccount
            } else {
                accounts.append(newAccount)
            }
            saveAccounts()
        }
        
        return newAccount
    }
    
    func switchAccount(id: String) async throws {
        guard let account = accounts.first(where: { $0.id == id }) else {
            throw AppError.accountNotFound
        }
        
        print("🔄 Switching to \(account.name)...")
        
        // 1. Close App
        if ProcessManager.shared.isRunning() {
             let closed = ProcessManager.shared.closeApp()
             if !closed {
                 print("⚠️ Warn: Application might still be running")
             }
               // Ensure we don't reuse a stale language server between accounts.
               ProcessManager.shared.terminateLanguageServers()
        }
        
        // 2. Read Backup
        let backupUrl = URL(fileURLWithPath: account.backup_file)
        let data = try Data(contentsOf: backupUrl)
        
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
            throw AppError.failedToReadBackup(path: backupUrl.path)
        }
        
        // 3. Restore DB
        switch DBManager.shared.restoreData(json) {
        case .success:
            // Update active account email immediately so menu checkmark refreshes
            let activeEmail = DBManager.shared.getCurrentAccountEmail()
            await MainActor.run {
                self.currentEmail = activeEmail
            }

            // Update Last Used
            await MainActor.run {
                if let idx = accounts.firstIndex(where: { $0.id == id }) {
                    accounts[idx].last_used = Date().ISO8601Format()
                    saveAccounts()
                    loadAccounts() // Refresh sort
                }
            }
            
            // 4. Start App
            ProcessManager.shared.startApp()
            
        case .failure(let error):
            throw error
        }
    }

    /// Switch to a selected backed-up account, but first apply a time limit to the
    /// currently active account (the one active *before* switching).
    ///
    /// - Parameters:
    ///   - id: Target account id to switch to.
    ///   - limitDuration: Duration added to the current active account's time limit (default: 5 hours).
    func switchAccountApplyingLimitToCurrent(id: String, limitDuration: TimeInterval = 5 * 60 * 60) async throws {
        let activeEmail = DBManager.shared.getCurrentAccountEmail()

        if let activeEmail {
            await MainActor.run {
                if let current = self.accounts.first(where: { $0.email == activeEmail }) {
                    let newLimit = Date().addingTimeInterval(limitDuration)
                    self.updateTimeLimit(id: current.id, date: newLimit)
                }
            }
        }

        try await switchAccount(id: id)
    }
    
    func removeAccount(id: String) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return // Or throw error
        }
        
        let account = accounts[index]
        
        // 1. Remove Backup File
        let backupUrl = URL(fileURLWithPath: account.backup_file)
        if FileManager.default.fileExists(atPath: backupUrl.path) {
            try FileManager.default.removeItem(at: backupUrl)
        }
        
        // 2. Remove from List
        accounts.remove(at: index)
        saveAccounts()
        
        print("🗑️ Removed account: \(account.name)")
    }
    
    func updateTimeLimit(id: String, date: Date?) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        if let date = date {
            accounts[index].time_limit = date.ISO8601Format()
            print("⏱ Set time limit for \(accounts[index].name): \(date)")
        } else {
            accounts[index].time_limit = nil
            print("⏱ Cleared time limit for \(accounts[index].name)")
        }
        
        saveAccounts()
    }

    // MARK: - Quota

    /// Fetch Antigravity quota for a specific backed-up account.
    ///
    /// Implementation note: Antigravity quota is retrieved from the local language_server HTTPS endpoint.
    /// That endpoint reflects the currently active Antigravity account, so we temporarily restore the
    /// selected account into the DB, start Antigravity, fetch quota, then restore the original DB state.
    func checkQuota(id: String) async throws -> QuotaSnapshot {
        guard let target = accounts.first(where: { $0.id == id }) else {
            throw AppError.accountNotFound
        }

        // Fast path: if this account is currently active, avoid DB swapping.
        if let targetEmail = target.email,
           let activeEmail = currentEmail,
           targetEmail == activeEmail {
            let wasRunning = ProcessManager.shared.isRunning()
            do {
                if !wasRunning {
                    ProcessManager.shared.startApp()
                    let started = await waitForAntigravityRunning(timeoutSeconds: 12)
                    if !started {
                        throw AppError.languageServerNotFound
                    }
                }

                let snapshot = try await QuotaService.shared.fetchQuota()
                setCachedQuota(id: id, snapshot: snapshot)

                if !wasRunning {
                    _ = ProcessManager.shared.closeApp()
                }

                return snapshot
            } catch {
                if !wasRunning {
                    _ = ProcessManager.shared.closeApp()
                }
                throw error
            }
        }

        // Snapshot current DB so we can restore even if the current account isn't in our backups.
        let originalDB: [String: String]
        switch DBManager.shared.backupData() {
        case .success(let data):
            originalDB = data
        case .failure(let error):
            throw error
        }

        let wasRunning = ProcessManager.shared.isRunning()

        // Always try to leave the system in the original state.
        do {
            if wasRunning {
                _ = ProcessManager.shared.closeApp()
                ProcessManager.shared.terminateLanguageServers()
            }

            let targetBackup = try readBackupData(for: target)
            switch DBManager.shared.restoreData(targetBackup) {
            case .success:
                break
            case .failure(let error):
                throw error
            }

            ProcessManager.shared.startApp()
            let started = await waitForAntigravityRunning(timeoutSeconds: 12)
            if !started {
                throw AppError.languageServerNotFound
            }

            let snapshot = try await QuotaService.shared.fetchQuota()
            setCachedQuota(id: id, snapshot: snapshot)

            // Close Antigravity to avoid leaving the account active.
            _ = ProcessManager.shared.closeApp()
            ProcessManager.shared.terminateLanguageServers()

            // Restore original DB state.
            switch DBManager.shared.restoreData(originalDB) {
            case .success:
                break
            case .failure(let error):
                throw error
            }

            // Restore original running state.
            if wasRunning {
                ProcessManager.shared.startApp()
            }

            await MainActor.run {
                self.updateCurrentEmail()
                self.refreshMenuContent()
            }

            return snapshot
        } catch {
            // Best-effort rollback
            _ = ProcessManager.shared.closeApp()
            _ = DBManager.shared.restoreData(originalDB)
            if wasRunning {
                ProcessManager.shared.startApp()
            }
            throw error
        }
    }

    private func readBackupData(for account: Account) throws -> [String: String] {
        let backupUrl = URL(fileURLWithPath: account.backup_file)
        let data = try Data(contentsOf: backupUrl)
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
            throw AppError.failedToReadBackup(path: backupUrl.path)
        }
        return json
    }

    private func waitForAntigravityRunning(timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if ProcessManager.shared.isRunning() {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }
}
