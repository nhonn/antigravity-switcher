import SwiftUI

@main
struct AntigravityMenuBarApp: App {
    @StateObject private var accountManager = AccountManager.shared
    @State private var lastError: AppError?
    @State private var showErrorAlert = false
    
    var body: some Scene {
        MenuBarExtra("Antigravity", systemImage: "person.2.circle") {
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
                ForEach(Array(accountManager.accounts.enumerated()), id: \.element.id) { index, account in
                    Menu {
                        Button("Switch to this account") {
                            switchAccount(account)
                        }
                        // Only add keyboard shortcuts for first 9 accounts
                        if index < 9 {
                            Button("") {}
                                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                                .hidden()
                        }
                        
                        Button("Rename...") {
                            renameAccount(account)
                        }
                        
                        Divider()
                        
                        Button("Remove Account", role: .destructive) {
                            confirmRemoveAccount(account)
                        }
                    } label: {
                        HStack {
                            if account.email == "Unknown" {
                                Image(systemName: "person.circle")
                            } else {
                                Image(systemName: "person.fill")
                            }
                            VStack(alignment: .leading) {
                                Text(account.name)
                                if let email = account.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
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
            
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("Preferences...")
                }
                .keyboardShortcut(",")
            } else {
                Button("Preferences...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",")
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
        
        // Settings Window
        Settings {
            SettingsView()
        }
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
    
    private func renameAccount(_ account: Account) {
        let alert = NSAlert()
        alert.messageText = "Rename Account"
        alert.informativeText = "Enter a new name for this account:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = account.name
        textField.placeholderString = "Account name"
        alert.accessoryView = textField
        
        // Make the text field the first responder
        alert.window.initialFirstResponder = textField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != account.name {
                accountManager.renameAccount(id: account.id, newName: newName)
            }
        }
    }
    
    private func confirmRemoveAccount(_ account: Account) {
        let alert = NSAlert()
        alert.messageText = "Remove Account Backup?"
        alert.informativeText = "Are you sure you want to remove the backup for \"\(account.name)\"? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        // Make the Remove button destructive (red on macOS Ventura+)
        if let removeButton = alert.buttons.first {
            removeButton.hasDestructiveAction = true
        }
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            do {
                try accountManager.removeAccount(id: account.id)
            } catch {
                print("Error removing account: \(error)")
            }
        }
    }
    
    @MainActor
    private func showError(_ error: AppError) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
