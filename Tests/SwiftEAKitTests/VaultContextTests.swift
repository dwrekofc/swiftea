import XCTest
@testable import SwiftEAKit

final class VaultContextTests: XCTestCase {
    var testDir: String!
    var vaultPath: String!
    var manager: VaultManager!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-context-test-\(UUID().uuidString)"
        vaultPath = testDir + "/test-vault"
        try? FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        manager = VaultManager()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    // MARK: - Vault Context Require Tests

    func testRequireSucceedsInVault() throws {
        // Initialize vault
        _ = try manager.initializeVault(at: vaultPath)

        // Require should succeed
        let context = try VaultContext.require(at: vaultPath)
        XCTAssertEqual(context.rootPath, (vaultPath as NSString).standardizingPath)
        XCTAssertEqual(context.config.version, "1.0")
    }

    func testRequireFailsOutsideVault() {
        let nonVaultPath = testDir + "/not-a-vault"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)

        XCTAssertThrowsError(try VaultContext.require(at: nonVaultPath)) { error in
            XCTAssertTrue(error is NoVaultContextError, "Expected NoVaultContextError")
        }
    }

    func testRequireErrorMessageIsActionable() {
        let nonVaultPath = testDir + "/actionable-test"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)

        do {
            _ = try VaultContext.require(at: nonVaultPath)
            XCTFail("Should have thrown")
        } catch let error as NoVaultContextError {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("No vault context found"), "Error should explain the problem")
            XCTAssertTrue(message.contains("swea init"), "Error should suggest solution")
            XCTAssertTrue(message.contains(nonVaultPath), "Error should include the path")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Vault Context Exists Tests

    func testExistsReturnsTrueForVault() throws {
        _ = try manager.initializeVault(at: vaultPath)
        XCTAssertTrue(VaultContext.exists(at: vaultPath))
    }

    func testExistsReturnsFalseForNonVault() {
        let nonVaultPath = testDir + "/not-vault"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)
        XCTAssertFalse(VaultContext.exists(at: nonVaultPath))
    }

    // MARK: - Context Properties Tests

    func testContextProvidesDatabasePath() throws {
        _ = try manager.initializeVault(at: vaultPath)
        let context = try VaultContext.require(at: vaultPath)

        let expectedDbPath = ((vaultPath as NSString).standardizingPath as NSString)
            .appendingPathComponent(".swiftea/swiftea.db")
        XCTAssertEqual(context.databasePath, expectedDbPath)
    }

    func testContextProvidesDataFolderPath() throws {
        _ = try manager.initializeVault(at: vaultPath)
        let context = try VaultContext.require(at: vaultPath)

        let expectedDataPath = ((vaultPath as NSString).standardizingPath as NSString)
            .appendingPathComponent("Swiftea")
        XCTAssertEqual(context.dataFolderPath, expectedDataPath)
    }

    // MARK: - Subdirectory Behavior Tests

    func testRequireFailsFromSubdirectory() throws {
        // Initialize vault
        _ = try manager.initializeVault(at: vaultPath)

        // Create subdirectory within vault
        let subDir = vaultPath + "/Swiftea/Mail"

        // Require from subdirectory should fail (no .swiftea in CWD)
        XCTAssertThrowsError(try VaultContext.require(at: subDir)) { error in
            XCTAssertTrue(error is NoVaultContextError)
        }
    }

    // MARK: - Config Access Tests

    func testContextProvidesConfig() throws {
        _ = try manager.initializeVault(at: vaultPath)

        // Modify config
        var config = try manager.readConfig(from: vaultPath)
        config.accounts.append(BoundAccount(id: "ctx-acc", type: .mail, name: "Context Account"))
        try manager.writeConfig(config, to: vaultPath)

        // Get context and verify config
        let context = try VaultContext.require(at: vaultPath)
        XCTAssertEqual(context.config.accounts.count, 1)
        XCTAssertEqual(context.config.accounts[0].name, "Context Account")
    }
}
