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
                ForEach(accountManager.accounts) { account in
                    Menu {
                        Button("Switch to this account") {
                            switchAccount(account)
                        }
                        
                        Divider()
                        
                        Button("Remove Account") {
                            removeAccount(account)
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
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
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
    
    private func removeAccount(_ account: Account) {
        do {
            try accountManager.removeAccount(id: account.id)
        } catch {
            print("Error removing account: \(error)")
        }
    }
    
    @MainActor
    private func showError(_ error: AppError) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
