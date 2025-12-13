import SwiftUI

/// View for menu bar label with real-time countdown
struct MenuBarLabelView: View {
    @ObservedObject var menuBarState = MenuBarState.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.circle")
            if !menuBarState.countdown.isEmpty {
                Text(menuBarState.countdown)
            }
        }
    }
}

@main
struct AntigravityMenuBarApp: App {
    @StateObject private var accountManager = AccountManager.shared
    @State private var lastError: AppError?
    @State private var showErrorAlert = false
    
    var body: some Scene {
        MenuBarExtra {
            // Header
            Text("Antigravity Switcher")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            // Account List
            if accountManager.accounts.isEmpty {
                Text("No backups found")
                    .foregroundColor(.gray)
            } else {
                ForEach(accountManager.accounts) { account in
                    Menu {
                        Button("Switch to this account") {
                            switchAccount(account)
                        }
                        
                        // Show Reset if active countdown, otherwise Update Time Limit
                        if hasActiveCountdown(account) {
                            Button("Reset") {
                                accountManager.updateTimeLimit(id: account.id, date: nil)
                            }
                        } else {
                            Button("Update Time Limit") {
                                showTimeLimitDialog(for: account)
                            }
                        }

                        Button("Check Quota") {
                            checkQuota(account)
                        }
                        
                        Divider()
                        
                        Button("Remove Account") {
                            removeAccount(account)
                        }
                    } label: {
                        HStack {
                            // Show checkmark for active account
                            if account.email == accountManager.currentEmail {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                            // if account.email == "Unknown" {
                            //     Image(systemName: "person.circle")
                            // } else {
                            //     Image(systemName: "person.fill")
                            // }
                            // Build display name with countdown if applicable
                            Text(accountDisplayName(account))
                        }
                    }
                }
            }
            
            Divider()
            
            // Actions
            Button("Backup Current Account") {
                backupCurrent()
            }
            .keyboardShortcut("b")
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.menu) // Dropdown menu style
        // Note: Alerts in MenuBarExtra are tricky. Standard SwiftUI .alert might not show up over a menu bar app easily.
        // We often need a workaround or a window. For simplicity in this native macOS app improvement, we can try using a basic NSAlert from logic or use a window if needed.
        // However, since SwiftUI's MenuBarExtra in .menu style actually renders NSMenuItems, standard SwiftUI alerts won't work inside the menu construction block directly in the same way.
        // But for the sake of improved architecture, we will handle the error in the Task. 
        // Showing a real UI alert from a menu bar app often requires bringing the app to front or using NSAlert.
    }
    
    private func switchAccount(_ account: Account) {
        Task {
            do {
                try await accountManager.switchAccount(id: account.id)
            } catch let error as AppError {
                showError(error)
            } catch {
                print("Unexpected error: \(error)")
            }
        }
    }
    
    private func backupCurrent() {
        Task {
            do {
                _ = try await accountManager.addCurrentAccount()
            } catch let error as AppError {
                showError(error)
            } catch {
                print("Unexpected error: \(error)")
            }
        }
    }
    
    private func accountDisplayName(_ account: Account) -> String {
        var displayName = account.name
        
        // Append countdown if time_limit is set and not expired
        if let timeLimitStr = account.time_limit,
           let timeLimit = ISO8601DateFormatter().date(from: timeLimitStr),
           let countdown = TimeLimitFormatter.formatCountdown(to: timeLimit) {
            displayName += " \(countdown)"
        }
        
        return displayName
    }
    
    private func hasActiveCountdown(_ account: Account) -> Bool {
        guard let timeLimitStr = account.time_limit,
              let timeLimit = ISO8601DateFormatter().date(from: timeLimitStr) else {
            return false
        }
        return timeLimit > Date()  // Active if not expired
    }
    
    private func removeAccount(_ account: Account) {
        do {
            try accountManager.removeAccount(id: account.id)
        } catch {
            print("Error removing account: \(error)")
        }
    }

    private func checkQuota(_ account: Account, forceRefresh: Bool = false) {
        Task {
            do {
                if !forceRefresh, let cached = accountManager.cachedQuota(id: account.id) {
                    await MainActor.run {
                        showQuotaDialog(snapshot: cached, account: account, isCached: true)
                    }
                    return
                }

                let proceed = await MainActor.run {
                    confirmQuotaCheck(for: account)
                }
                guard proceed else { return }

                let panel = await MainActor.run { () -> ProgressPanel in
                    let p = ProgressPanel(title: "Checking Quota", message: "Fetching quota data…")
                    p.show()
                    return p
                }
                defer {
                    Task { @MainActor in
                        panel.close()
                    }
                }

                let snapshot = try await accountManager.checkQuota(id: account.id)

                await MainActor.run {
                    showQuotaDialog(snapshot: snapshot, account: account, isCached: false)
                }
            } catch let error as AppError {
                await MainActor.run {
                    showError(error)
                }
            } catch {
                print("Unexpected error: \(error)")
            }
        }
    }
    
    @MainActor
    private func showError(_ error: AppError) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    @MainActor
    private func showQuotaDialog(snapshot: QuotaSnapshot, account: Account, isCached: Bool) {
        let alert = NSAlert()
        alert.messageText = "Quota – \(account.name)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Refresh")

        let headerLines: [String] = [
            snapshot.userEmail.map { "Email: \($0)" } ?? "Email: (unknown)",
            snapshot.planName.map { "Plan: \($0)" } ?? "Plan: (unknown)",
            snapshot.teamsTier.map { "Tier: \($0)" } ?? "Tier: (unknown)",
            "Fetched at: \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))" + (isCached ? " (cached)" : "")
        ]

        var lines: [String] = headerLines

        if let pc = snapshot.promptCredits {
            lines.append("")
            lines.append(String(format: "Prompt credits: %.0f / %.0f (%.1f%%)", pc.available, pc.monthly, pc.remainingPercentage))
        }

        let models = snapshot.models.sorted { (a, b) in
            let ap = a.remainingPercentage ?? 101
            let bp = b.remainingPercentage ?? 101
            if ap == bp { return a.label < b.label }
            return ap < bp
        }

        if !models.isEmpty {
            lines.append("")
            lines.append("Models:")

            for m in models {
                let pct = m.remainingPercentage.map { String(format: "%.1f%%", $0) } ?? "N/A"
                let reset = m.resetTime.map { formatTimeUntil($0) } ?? "N/A"
                let exhausted = m.isExhausted ? " (exhausted)" : ""
                lines.append("- \(m.label): \(pct), resets in: \(reset)\(exhausted)")
            }
        } else {
            lines.append("")
            lines.append("No model quota data returned.")
        }

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = lines.joined(separator: "\n")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        alert.accessoryView = scrollView
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            checkQuota(account, forceRefresh: true)
        }
    }

    @MainActor
    private func confirmQuotaCheck(for account: Account) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Check Quota"

        let active = account.email != nil && account.email == accountManager.currentEmail
        if active {
            alert.informativeText = "This will fetch quota for the currently active Antigravity account."
        } else {
            alert.informativeText = "This may temporarily switch Antigravity to this account and restart Antigravity to fetch quota. Continue?"
        }

        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func formatTimeUntil(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "Ready" }
        let mins = Int(ceil(diff / 60))
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        let rem = mins % 60
        return "\(hours)h \(rem)m"
    }
    
    @MainActor
    private func showTimeLimitDialog(for account: Account) {
        let alert = NSAlert()
        alert.messageText = "Update Time Limit"
        alert.informativeText = "Enter time (HH:mm) and date (dd.MM.yyyy)\nLeave empty to clear time limit."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        // Create stack view for inputs
        let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 260, height: 60))
        stackView.orientation = .vertical
        stackView.spacing = 8
        
        // Time input row
        let timeRow = NSStackView()
        timeRow.orientation = .horizontal
        timeRow.spacing = 8
        
        let timeLabel = NSTextField(labelWithString: "Time:")
        timeLabel.frame = NSRect(x: 0, y: 0, width: 50, height: 22)
        
        let timeField = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        timeField.placeholderString = "HH:mm"
        timeField.stringValue = TimeLimitFormatter.defaultTimeString()
        
        timeRow.addArrangedSubview(timeLabel)
        timeRow.addArrangedSubview(timeField)
        
        // Date input row
        let dateRow = NSStackView()
        dateRow.orientation = .horizontal
        dateRow.spacing = 8
        
        let dateLabel = NSTextField(labelWithString: "Date:")
        dateLabel.frame = NSRect(x: 0, y: 0, width: 50, height: 22)
        
        let dateField = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        dateField.placeholderString = "dd.MM.yyyy"
        dateField.stringValue = TimeLimitFormatter.defaultDateString()
        
        dateRow.addArrangedSubview(dateLabel)
        dateRow.addArrangedSubview(dateField)
        
        stackView.addArrangedSubview(timeRow)
        stackView.addArrangedSubview(dateRow)
        
        alert.accessoryView = stackView
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let timeValue = timeField.stringValue.trimmingCharacters(in: .whitespaces)
            let dateValue = dateField.stringValue.trimmingCharacters(in: .whitespaces)
            
            // Clear time limit if both empty
            if timeValue.isEmpty && dateValue.isEmpty {
                accountManager.updateTimeLimit(id: account.id, date: nil)
                return
            }
            
            // Validate and parse
            guard let parsedDate = TimeLimitFormatter.parse(time: timeValue, date: dateValue) else {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Invalid Format"
                errorAlert.informativeText = "Please enter time as HH:mm (e.g., 14:30) and date as dd.MM.yyyy (e.g., 31.12.2026)"
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
                return
            }
            
            accountManager.updateTimeLimit(id: account.id, date: parsedDate)
        }
    }
}
