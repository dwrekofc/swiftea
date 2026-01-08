import Testing
import Foundation
@testable import SwiftEAKit

@Suite("VaultContext Tests")
struct VaultContextTests {
    let testDir: String
    let vaultPath: String
    let manager: VaultManager

    init() {
        testDir = NSTemporaryDirectory() + "swiftea-context-test-\(UUID().uuidString)"
        vaultPath = testDir + "/test-vault"
        try? FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        manager = VaultManager()
    }

    // MARK: - Vault Context Require Tests

    @Test("Require succeeds in vault")
    func requireSucceedsInVault() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        // Initialize vault
        _ = try manager.initializeVault(at: vaultPath)

        // Require should succeed
        let context = try VaultContext.require(at: vaultPath)
        #expect(context.rootPath == (vaultPath as NSString).standardizingPath)
        #expect(context.config.version == "1.0")
    }

    @Test("Require fails outside vault")
    func requireFailsOutsideVault() {
        let nonVaultPath = testDir + "/not-a-vault"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        #expect(throws: NoVaultContextError.self) {
            _ = try VaultContext.require(at: nonVaultPath)
        }
    }

    @Test("Require error message is actionable")
    func requireErrorMessageIsActionable() {
        let nonVaultPath = testDir + "/actionable-test"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        do {
            _ = try VaultContext.require(at: nonVaultPath)
            Issue.record("Should have thrown")
        } catch let error as NoVaultContextError {
            let message = error.localizedDescription
            #expect(message.contains("No vault context found"), "Error should explain the problem")
            #expect(message.contains("swiftea vault init"), "Error should suggest solution")
            #expect(message.contains(nonVaultPath), "Error should include the path")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    // MARK: - Vault Context Exists Tests

    @Test("Exists returns true for vault")
    func existsReturnsTrueForVault() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        _ = try manager.initializeVault(at: vaultPath)
        #expect(VaultContext.exists(at: vaultPath))
    }

    @Test("Exists returns false for non-vault")
    func existsReturnsFalseForNonVault() {
        let nonVaultPath = testDir + "/not-vault"
        try? FileManager.default.createDirectory(atPath: nonVaultPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        #expect(!VaultContext.exists(at: nonVaultPath))
    }

    // MARK: - Context Properties Tests

    @Test("Context provides database path")
    func contextProvidesDatabasePath() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        _ = try manager.initializeVault(at: vaultPath)
        let context = try VaultContext.require(at: vaultPath)

        let expectedDbPath = ((vaultPath as NSString).standardizingPath as NSString)
            .appendingPathComponent(".swiftea/swiftea.db")
        #expect(context.databasePath == expectedDbPath)
    }

    @Test("Context provides data folder path")
    func contextProvidesDataFolderPath() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        _ = try manager.initializeVault(at: vaultPath)
        let context = try VaultContext.require(at: vaultPath)

        let expectedDataPath = ((vaultPath as NSString).standardizingPath as NSString)
            .appendingPathComponent("Swiftea")
        #expect(context.dataFolderPath == expectedDataPath)
    }

    // MARK: - Subdirectory Behavior Tests

    @Test("Require fails from subdirectory")
    func requireFailsFromSubdirectory() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        // Initialize vault
        _ = try manager.initializeVault(at: vaultPath)

        // Create subdirectory within vault
        let subDir = vaultPath + "/Swiftea/Mail"

        // Require from subdirectory should fail (no .swiftea in CWD)
        #expect(throws: NoVaultContextError.self) {
            _ = try VaultContext.require(at: subDir)
        }
    }

    // MARK: - Config Access Tests

    @Test("Context provides config")
    func contextProvidesConfig() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        _ = try manager.initializeVault(at: vaultPath)

        // Modify config
        var config = try manager.readConfig(from: vaultPath)
        config.accounts.append(BoundAccount(id: "ctx-acc", type: .mail, name: "Context Account"))
        try manager.writeConfig(config, to: vaultPath)

        // Get context and verify config
        let context = try VaultContext.require(at: vaultPath)
        #expect(context.config.accounts.count == 1)
        #expect(context.config.accounts[0].name == "Context Account")
    }
}
