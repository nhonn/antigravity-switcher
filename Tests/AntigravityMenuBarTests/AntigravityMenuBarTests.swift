import XCTest
@testable import AntigravityMenuBar

final class AppConfigurationTests: XCTestCase {
    func testConfigurationValues() {
        let config = AppConfiguration.shared
        XCTAssertEqual(config.appDataDirectoryName, ".antigravity-agent")
        XCTAssertEqual(config.backupsDirectoryName, "backups")
        XCTAssertEqual(config.accountsFileName, "antigravity_accounts.json")
    }
    
    func testBundleIds() {
        let config = AppConfiguration.shared
        XCTAssert(config.antigravityBundleIds.contains("com.ctrler.antigravity"))
    }
}
