import Testing
import Foundation
@testable import SwiftEAKit

@Suite("VaultManager Tests")
struct VaultManagerTests {
    let testDir: String
    let manager: VaultManager

    init() {
        testDir = NSTemporaryDirectory() + "swiftea-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        manager = VaultManager()
    }

    // MARK: - Vault Init Tests

    @Test("Initialize vault creates complete structure")
    func initializeVaultCreatesStructure() throws {
        let vaultPath = testDir + "/test-vault"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let config = try manager.initializeVault(at: vaultPath)

        // Verify .swiftea directory exists
        #expect(manager.isVault(at: vaultPath), "Vault should be detected after init")

        // Verify config.json exists
        let configPath = manager.configPath(for: vaultPath)
        #expect(FileManager.default.fileExists(atPath: configPath), "config.json should exist")

        // Verify swiftea.db exists
        let dbPath = manager.databasePath(for: vaultPath)
        #expect(FileManager.default.fileExists(atPath: dbPath), "swiftea.db should exist")

        // Verify Swiftea/ folder structure
        let dataFolder = manager.dataFolder(for: vaultPath)
        for folder in VaultManager.canonicalFolders {
            let folderPath = (dataFolder as NSString).appendingPathComponent(folder)
            var isDir: ObjCBool = false
            #expect(
                FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir) && isDir.boolValue,
                "Swiftea/\(folder) should exist as directory"
            )
        }

        // Verify config content
        #expect(config.version == "1.0")
        #expect(config.accounts.isEmpty)
    }

    @Test("Initialize vault fails if already exists")
    func initializeVaultFailsIfAlreadyExists() throws {
        let vaultPath = testDir + "/existing-vault"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        // First init should succeed
        _ = try manager.initializeVault(at: vaultPath)

        // Second init should fail
        #expect(throws: VaultError.self) {
            try manager.initializeVault(at: vaultPath)
        }
    }

    @Test("Initialize vault with force reinitializes")
    func initializeVaultWithForceReinitializes() throws {
        let vaultPath = testDir + "/force-vault"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        // First init
        _ = try manager.initializeVault(at: vaultPath)

        // Force reinit should succeed
        let config = try manager.initializeVault(at: vaultPath, force: true)
        #expect(config.version == "1.0")
    }

    // MARK: - Vault Detection Tests

    @Test("isVault returns false for non-vault")
    func isVaultReturnsFalseForNonVault() {
        let nonVaultPath = testDir + "/not-a-vault"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        #expect(!manager.isVault(at: nonVaultPath))
    }

    @Test("isVault returns true for vault")
    func isVaultReturnsTrueForVault() throws {
        let vaultPath = testDir + "/is-vault"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        _ = try manager.initializeVault(at: vaultPath)
        #expect(manager.isVault(at: vaultPath))
    }

    // MARK: - Config Tests

    @Test("Read and write config")
    func readWriteConfig() throws {
        let vaultPath = testDir + "/config-test"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        _ = try manager.initializeVault(at: vaultPath)

        // Read initial config
        var config = try manager.readConfig(from: vaultPath)
        #expect(config.accounts.isEmpty)

        // Modify and write config
        config.accounts.append(BoundAccount(id: "test-id", type: .mail, name: "Test Account"))
        try manager.writeConfig(config, to: vaultPath)

        // Read again and verify
        let updatedConfig = try manager.readConfig(from: vaultPath)
        #expect(updatedConfig.accounts.count == 1)
        #expect(updatedConfig.accounts[0].id == "test-id")
        #expect(updatedConfig.accounts[0].type == .mail)
        #expect(updatedConfig.accounts[0].name == "Test Account")
    }

    // MARK: - Path Helper Tests

    @Test("Vault directory path")
    func vaultDirectoryPath() {
        let path = "/some/vault"
        #expect(manager.vaultDirectory(for: path) == "/some/vault/.swiftea")
    }

    @Test("Config path")
    func configPath() {
        let path = "/some/vault"
        #expect(manager.configPath(for: path) == "/some/vault/.swiftea/config.json")
    }

    @Test("Database path")
    func databasePath() {
        let path = "/some/vault"
        #expect(manager.databasePath(for: path) == "/some/vault/.swiftea/swiftea.db")
    }

    @Test("Data folder path")
    func dataFolderPath() {
        let path = "/some/vault"
        #expect(manager.dataFolder(for: path) == "/some/vault/Swiftea")
    }

    // MARK: - Find Vault Root Tests

    @Test("Find vault root from vault root")
    func findVaultRootFromVaultRoot() throws {
        let vaultPath = testDir + "/find-root"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        _ = try manager.initializeVault(at: vaultPath)

        let found = manager.findVaultRoot(from: vaultPath)
        #expect(found == (vaultPath as NSString).standardizingPath)
    }

    @Test("Find vault root from subdirectory")
    func findVaultRootFromSubdirectory() throws {
        let vaultPath = testDir + "/find-sub"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        _ = try manager.initializeVault(at: vaultPath)

        // Create subdirectory
        let subPath = vaultPath + "/Swiftea/Mail/subdir"
        try FileManager.default.createDirectory(atPath: subPath, withIntermediateDirectories: true)

        let found = manager.findVaultRoot(from: subPath)
        #expect(found == (vaultPath as NSString).standardizingPath)
    }

    @Test("Find vault root returns nil for non-vault")
    func findVaultRootReturnsNilForNonVault() {
        let nonVaultPath = testDir + "/no-vault"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let found = manager.findVaultRoot(from: nonVaultPath)
        #expect(found == nil)
    }
}
