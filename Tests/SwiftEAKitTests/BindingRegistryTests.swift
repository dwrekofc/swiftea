import Testing
import Foundation
@testable import SwiftEAKit

@Suite("BindingRegistry Tests")
struct BindingRegistryTests {
    let testDir: String
    let registryPath: String
    let registry: BindingRegistry

    init() {
        testDir = NSTemporaryDirectory() + "swiftea-registry-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        registryPath = testDir + "/account-bindings.json"
        registry = BindingRegistry(registryPath: registryPath)
    }

    // MARK: - Basic Binding Tests

    @Test("Bind account creates registry")
    func bindAccountCreatesRegistry() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let account = DiscoveredAccount(id: "acc-1", name: "Test Account", email: "test@example.com", type: .mail)
        let vaultPath = "/test/vault"

        try registry.bindAccount(account, toVault: vaultPath)

        #expect(FileManager.default.fileExists(atPath: registryPath), "Registry file should be created")
    }

    @Test("Bind account stores binding")
    func bindAccountStoresBinding() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let account = DiscoveredAccount(id: "acc-1", name: "Test Account", email: "test@example.com", type: .mail)
        let vaultPath = "/test/vault"

        try registry.bindAccount(account, toVault: vaultPath)

        let (bound, storedPath) = try registry.isAccountBound("acc-1")
        #expect(bound)
        #expect(storedPath == vaultPath)
    }

    @Test("Bind multiple accounts")
    func bindMultipleAccounts() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let account1 = DiscoveredAccount(id: "acc-1", name: "Account 1", email: nil, type: .mail)
        let account2 = DiscoveredAccount(id: "acc-2", name: "Account 2", email: nil, type: .calendar)
        let vaultPath = "/test/vault"

        try registry.bindAccount(account1, toVault: vaultPath)
        try registry.bindAccount(account2, toVault: vaultPath)

        let bindings = try registry.allBindings()
        #expect(bindings.count == 2)
    }

    // MARK: - Conflict Detection Tests

    @Test("Bind account fails if bound to other vault")
    func bindAccountFailsIfBoundToOtherVault() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let account = DiscoveredAccount(id: "acc-conflict", name: "Conflict Account", email: nil, type: .mail)

        // Bind to first vault
        try registry.bindAccount(account, toVault: "/vault/one")

        // Attempt to bind to second vault should fail
        #expect(throws: BindingRegistryError.self) {
            try registry.bindAccount(account, toVault: "/vault/two")
        }
    }

    @Test("Bind account succeeds if rebinding to same vault")
    func bindAccountSucceedsIfRebindingToSameVault() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let account = DiscoveredAccount(id: "acc-same", name: "Same Vault Account", email: nil, type: .mail)
        let vaultPath = "/test/same-vault"

        // Bind twice to same vault should succeed (idempotent)
        try registry.bindAccount(account, toVault: vaultPath)
        try registry.bindAccount(account, toVault: vaultPath)

        let bindings = try registry.allBindings()
        #expect(bindings.count == 1)
    }

    // MARK: - Unbind Tests

    @Test("Unbind account removes binding")
    func unbindAccountRemovesBinding() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let account = DiscoveredAccount(id: "acc-unbind", name: "Unbind Account", email: nil, type: .mail)
        let vaultPath = "/test/vault"

        try registry.bindAccount(account, toVault: vaultPath)
        try registry.unbindAccount("acc-unbind")

        let (bound, _) = try registry.isAccountBound("acc-unbind")
        #expect(!bound)
    }

    @Test("Unbind nonexistent account does not throw")
    func unbindNonexistentAccountDoesNotThrow() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        // Should not throw when unbinding non-existent account
        try registry.unbindAccount("non-existent")
    }

    // MARK: - Query Tests

    @Test("isAccountBound returns false for unbound")
    func isAccountBoundReturnsFalseForUnbound() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let (bound, path) = try registry.isAccountBound("unknown-account")
        #expect(!bound)
        #expect(path == nil)
    }

    @Test("Vault path for account")
    func vaultPathForAccount() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let account = DiscoveredAccount(id: "acc-path", name: "Path Account", email: nil, type: .mail)
        let vaultPath = "/test/vault/path"

        try registry.bindAccount(account, toVault: vaultPath)

        let retrievedPath = try registry.vaultPath(for: "acc-path")
        #expect(retrievedPath == vaultPath)
    }

    @Test("Bindings for vault")
    func bindingsForVault() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let vault1 = "/vault/one"
        let vault2 = "/vault/two"

        try registry.bindAccount(
            DiscoveredAccount(id: "v1-acc1", name: "V1 Account 1", email: nil, type: .mail),
            toVault: vault1
        )
        try registry.bindAccount(
            DiscoveredAccount(id: "v1-acc2", name: "V1 Account 2", email: nil, type: .calendar),
            toVault: vault1
        )
        try registry.bindAccount(
            DiscoveredAccount(id: "v2-acc1", name: "V2 Account 1", email: nil, type: .mail),
            toVault: vault2
        )

        let vault1Bindings = try registry.bindings(forVault: vault1)
        #expect(vault1Bindings.count == 2)

        let vault2Bindings = try registry.bindings(forVault: vault2)
        #expect(vault2Bindings.count == 1)
    }

    // MARK: - Registry Persistence Tests

    @Test("Registry persists across instances")
    func registryPersistsAcrossInstances() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let account = DiscoveredAccount(id: "persist-acc", name: "Persist Account", email: nil, type: .mail)
        let vaultPath = "/test/persist"

        // Bind with first registry instance
        try registry.bindAccount(account, toVault: vaultPath)

        // Create new registry instance with same path
        let newRegistry = BindingRegistry(registryPath: registryPath)
        let (bound, _) = try newRegistry.isAccountBound("persist-acc")
        #expect(bound)
    }

    @Test("Empty registry returns empty bindings")
    func emptyRegistryReturnsEmptyBindings() throws {
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let bindings = try registry.allBindings()
        #expect(bindings.isEmpty)
    }
}
