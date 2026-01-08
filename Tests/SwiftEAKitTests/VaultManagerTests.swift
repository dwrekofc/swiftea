import XCTest
@testable import SwiftEAKit

final class VaultManagerTests: XCTestCase {
    var testDir: String!
    var manager: VaultManager!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        manager = VaultManager()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    // MARK: - Vault Init Tests

    func testInitializeVaultCreatesStructure() throws {
        let vaultPath = testDir + "/test-vault"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)

        let config = try manager.initializeVault(at: vaultPath)

        // Verify .swiftea directory exists
        XCTAssertTrue(manager.isVault(at: vaultPath), "Vault should be detected after init")

        // Verify config.json exists
        let configPath = manager.configPath(for: vaultPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath), "config.json should exist")

        // Verify swiftea.db exists
        let dbPath = manager.databasePath(for: vaultPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath), "swiftea.db should exist")

        // Verify Swiftea/ folder structure
        let dataFolder = manager.dataFolder(for: vaultPath)
        for folder in VaultManager.canonicalFolders {
            let folderPath = (dataFolder as NSString).appendingPathComponent(folder)
            var isDir: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir) && isDir.boolValue,
                "Swiftea/\(folder) should exist as directory"
            )
        }

        // Verify config content
        XCTAssertEqual(config.version, "1.0")
        XCTAssertTrue(config.accounts.isEmpty)
    }

    func testInitializeVaultFailsIfAlreadyExists() throws {
        let vaultPath = testDir + "/existing-vault"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)

        // First init should succeed
        _ = try manager.initializeVault(at: vaultPath)

        // Second init should fail
        XCTAssertThrowsError(try manager.initializeVault(at: vaultPath)) { error in
            guard case VaultError.alreadyExists = error else {
                XCTFail("Expected VaultError.alreadyExists, got \(error)")
                return
            }
        }
    }

    func testInitializeVaultWithForceReinitializes() throws {
        let vaultPath = testDir + "/force-vault"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)

        // First init
        _ = try manager.initializeVault(at: vaultPath)

        // Force reinit should succeed
        let config = try manager.initializeVault(at: vaultPath, force: true)
        XCTAssertEqual(config.version, "1.0")
    }

    // MARK: - Vault Detection Tests

    func testIsVaultReturnsFalseForNonVault() {
        let nonVaultPath = testDir + "/not-a-vault"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)

        XCTAssertFalse(manager.isVault(at: nonVaultPath))
    }

    func testIsVaultReturnsTrueForVault() throws {
        let vaultPath = testDir + "/is-vault"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        _ = try manager.initializeVault(at: vaultPath)

        XCTAssertTrue(manager.isVault(at: vaultPath))
    }

    // MARK: - Config Tests

    func testReadWriteConfig() throws {
        let vaultPath = testDir + "/config-test"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        _ = try manager.initializeVault(at: vaultPath)

        // Read initial config
        var config = try manager.readConfig(from: vaultPath)
        XCTAssertTrue(config.accounts.isEmpty)

        // Modify and write config
        config.accounts.append(BoundAccount(id: "test-id", type: .mail, name: "Test Account"))
        try manager.writeConfig(config, to: vaultPath)

        // Read again and verify
        let updatedConfig = try manager.readConfig(from: vaultPath)
        XCTAssertEqual(updatedConfig.accounts.count, 1)
        XCTAssertEqual(updatedConfig.accounts[0].id, "test-id")
        XCTAssertEqual(updatedConfig.accounts[0].type, .mail)
        XCTAssertEqual(updatedConfig.accounts[0].name, "Test Account")
    }

    // MARK: - Path Helper Tests

    func testVaultDirectoryPath() {
        let path = "/some/vault"
        XCTAssertEqual(manager.vaultDirectory(for: path), "/some/vault/.swiftea")
    }

    func testConfigPath() {
        let path = "/some/vault"
        XCTAssertEqual(manager.configPath(for: path), "/some/vault/.swiftea/config.json")
    }

    func testDatabasePath() {
        let path = "/some/vault"
        XCTAssertEqual(manager.databasePath(for: path), "/some/vault/.swiftea/swiftea.db")
    }

    func testDataFolderPath() {
        let path = "/some/vault"
        XCTAssertEqual(manager.dataFolder(for: path), "/some/vault/Swiftea")
    }

    // MARK: - Find Vault Root Tests

    func testFindVaultRootFromVaultRoot() throws {
        let vaultPath = testDir + "/find-root"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        _ = try manager.initializeVault(at: vaultPath)

        let found = manager.findVaultRoot(from: vaultPath)
        XCTAssertEqual(found, (vaultPath as NSString).standardizingPath)
    }

    func testFindVaultRootFromSubdirectory() throws {
        let vaultPath = testDir + "/find-sub"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        _ = try manager.initializeVault(at: vaultPath)

        // Create subdirectory
        let subPath = vaultPath + "/Swiftea/Mail/subdir"
        try FileManager.default.createDirectory(atPath: subPath, withIntermediateDirectories: true)

        let found = manager.findVaultRoot(from: subPath)
        XCTAssertEqual(found, (vaultPath as NSString).standardizingPath)
    }

    func testFindVaultRootReturnsNilForNonVault() {
        let nonVaultPath = testDir + "/no-vault"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)

        let found = manager.findVaultRoot(from: nonVaultPath)
        XCTAssertNil(found)
    }
}
