import XCTest
@testable import AntigravityMenuBar

final class AccountManagerTests: XCTestCase {
    
    // Helper to clean up test files
    private func cleanup() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let testDir = home.appendingPathComponent(".antigravity-agent") // Using actual dir as per code logic
        
        // Caution: This deletes real data if running on a real machine used for dev.
        // However, since we can't easily inject a different root path into AccountManager without refactoring,
        // we'll assume this is running in a controlled env or we should refactor AccountManager to be testable.
        // Given the constraints and the provided code, I'll mock what I can or write a safe test.
        
        // Actually, let's refrain from deleting the whole folder.
        // We can just manipulate the accounts list directly and check file existence for a specific fake backup.
    }
    
    func testRemoveAccount() async throws {
        // Arrange
        let manager = AccountManager.shared
        let fileManager = FileManager.default
        
        print("Test starting")
        
        // Create a dummy account manually into the manager
        let dummyId = UUID().uuidString
        let backupDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".antigravity-agent")
            .appendingPathComponent("backups")
        
        try? fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        let backupPath = backupDir.appendingPathComponent("\(dummyId).json")
        let dummyData = ["key": "value"]
        let data = try JSONEncoder().encode(dummyData)
        try data.write(to: backupPath)
        
        let dummyAccount = Account(
            id: dummyId,
            name: "Test Account",
            email: "test@example.com",
            backup_file: backupPath.path,
            created_at: Date().ISO8601Format(),
            last_used: nil
        )
        
        print("Created dummy data")
        
        await MainActor.run {
            manager.accounts.append(dummyAccount)
            manager.saveAccounts()
            print("Added account to manager")
        }
        
        // Assert creation
        XCTAssertTrue(fileManager.fileExists(atPath: backupPath.path))
        let exists = await MainActor.run {
             manager.accounts.contains(where: { $0.id == dummyId })
        }
        XCTAssertTrue(exists)
        
        // Act
        print("Removing account")
        await MainActor.run {
            try? manager.removeAccount(id: dummyId)
        }
        
        // Assert deletion
        let existsAfter = await MainActor.run {
             manager.accounts.contains(where: { $0.id == dummyId })
        }
        XCTAssertFalse(existsAfter)
        XCTAssertFalse(fileManager.fileExists(atPath: backupPath.path))
        print("Test finished")
    }
}
