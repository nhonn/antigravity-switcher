import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var autoBackupBeforeSwitch = AppConfiguration.shared.autoBackupBeforeSwitch
    @State private var launchAtLogin = AppConfiguration.shared.launchAtLogin
    @State private var showNotifications = AppConfiguration.shared.showNotifications
    
    var body: some View {
        Form {
            // MARK: - General Section
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        AppConfiguration.shared.launchAtLogin = newValue
                        updateLaunchAtLogin(enabled: newValue)
                    }
                
                Toggle("Show Notifications", isOn: $showNotifications)
                    .onChange(of: showNotifications) { newValue in
                        AppConfiguration.shared.showNotifications = newValue
                    }
            } header: {
                Label("General", systemImage: "gear")
            }
            
            // MARK: - Backup Section
            Section {
                Toggle("Auto-backup before switching", isOn: $autoBackupBeforeSwitch)
                    .onChange(of: autoBackupBeforeSwitch) { newValue in
                        AppConfiguration.shared.autoBackupBeforeSwitch = newValue
                    }
                
                Text("When enabled, your current account will be automatically backed up before switching to another account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Label("Backup", systemImage: "arrow.clockwise.circle")
            }
            
            // MARK: - About Section
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
        .padding()
    }
    
    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("✅ Registered for launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                print("✅ Unregistered from launch at login")
            }
        } catch {
            print("❌ Failed to update launch at login: \(error)")
        }
    }
}

#Preview {
    SettingsView()
}
