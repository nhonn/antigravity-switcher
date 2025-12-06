import SwiftUI

@main
struct AntigravityMenuBarApp: App {
    @StateObject private var accountManager = AccountManager.shared
    
    var body: some Scene {
        MenuBarExtra("Antigravity", systemImage: "person.2.circle") {
            // Header
            Text("Antigravity Manager")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            // Account List
            if accountManager.accounts.isEmpty {
                Text("No backups found")
                    .foregroundColor(.gray)
            } else {
                ForEach(accountManager.accounts) { account in
                    Button {
                        switchAccount(account)
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
    }
    
    private func switchAccount(_ account: Account) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = accountManager.switchAccount(id: account.id)
            DispatchQueue.main.async {
                if !success {
                    print("Failed to switch")
                }
            }
        }
    }
    
    private func backupCurrent() {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = accountManager.addCurrentAccount()
            DispatchQueue.main.async {
                if !success {
                    print("Failed to backup")
                }
            }
        }
    }
}
