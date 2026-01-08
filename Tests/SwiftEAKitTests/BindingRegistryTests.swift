import XCTest
@testable import SwiftEAKit

final class BindingRegistryTests: XCTestCase {
    var testDir: String!
    var registryPath: String!
    var registry: BindingRegistry!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-registry-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        registryPath = testDir + "/account-bindings.json"
        registry = BindingRegistry(registryPath: registryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    // MARK: - Basic Binding Tests

    func testBindAccountCreatesRegistry() throws {
        let account = DiscoveredAccount(id: "acc-1", name: "Test Account", email: "test@example.com", type: .mail)
        let vaultPath = "/test/vault"

        try registry.bindAccount(account, toVault: vaultPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: registryPath), "Registry file should be created")
    }

    func testBindAccountStoresBinding() throws {
        let account = DiscoveredAccount(id: "acc-1", name: "Test Account", email: "test@example.com", type: .mail)
        let vaultPath = "/test/vault"

        try registry.bindAccount(account, toVault: vaultPath)

        let (bound, storedPath) = try registry.isAccountBound("acc-1")
        XCTAssertTrue(bound)
        XCTAssertEqual(storedPath, vaultPath)
    }

    func testBindMultipleAccounts() throws {
        let account1 = DiscoveredAccount(id: "acc-1", name: "Account 1", email: nil, type: .mail)
        let account2 = DiscoveredAccount(id: "acc-2", name: "Account 2", email: nil, type: .calendar)
        let vaultPath = "/test/vault"

        try registry.bindAccount(account1, toVault: vaultPath)
        try registry.bindAccount(account2, toVault: vaultPath)

        let bindings = try registry.allBindings()
        XCTAssertEqual(bindings.count, 2)
    }

    // MARK: - Conflict Detection Tests

    func testBindAccountFailsIfBoundToOtherVault() throws {
        let account = DiscoveredAccount(id: "acc-conflict", name: "Conflict Account", email: nil, type: .mail)

        // Bind to first vault
        try registry.bindAccount(account, toVault: "/vault/one")

        // Attempt to bind to second vault should fail
        XCTAssertThrowsError(try registry.bindAccount(account, toVault: "/vault/two")) { error in
            guard case BindingRegistryError.accountAlreadyBound(let accountId, let existingVault) = error else {
                XCTFail("Expected BindingRegistryError.accountAlreadyBound, got \(error)")
                return
            }
            XCTAssertEqual(accountId, "acc-conflict")
            XCTAssertEqual(existingVault, "/vault/one")
        }
    }

    func testBindAccountSucceedsIfRebindingToSameVault() throws {
        let account = DiscoveredAccount(id: "acc-same", name: "Same Vault Account", email: nil, type: .mail)
        let vaultPath = "/test/same-vault"

        // Bind twice to same vault should succeed (idempotent)
        try registry.bindAccount(account, toVault: vaultPath)
        try registry.bindAccount(account, toVault: vaultPath)

        let bindings = try registry.allBindings()
        XCTAssertEqual(bindings.count, 1)
    }

    // MARK: - Unbind Tests

    func testUnbindAccountRemovesBinding() throws {
        let account = DiscoveredAccount(id: "acc-unbind", name: "Unbind Account", email: nil, type: .mail)
        let vaultPath = "/test/vault"

        try registry.bindAccount(account, toVault: vaultPath)
        try registry.unbindAccount("acc-unbind")

        let (bound, _) = try registry.isAccountBound("acc-unbind")
        XCTAssertFalse(bound)
    }

    func testUnbindNonexistentAccountDoesNotThrow() throws {
        // Should not throw when unbinding non-existent account
        XCTAssertNoThrow(try registry.unbindAccount("non-existent"))
    }

    // MARK: - Query Tests

    func testIsAccountBoundReturnsFalseForUnbound() throws {
        let (bound, path) = try registry.isAccountBound("unknown-account")
        XCTAssertFalse(bound)
        XCTAssertNil(path)
    }

    func testVaultPathForAccount() throws {
        let account = DiscoveredAccount(id: "acc-path", name: "Path Account", email: nil, type: .mail)
        let vaultPath = "/test/vault/path"

        try registry.bindAccount(account, toVault: vaultPath)

        let retrievedPath = try registry.vaultPath(for: "acc-path")
        XCTAssertEqual(retrievedPath, vaultPath)
    }

    func testBindingsForVault() throws {
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
        XCTAssertEqual(vault1Bindings.count, 2)

        let vault2Bindings = try registry.bindings(forVault: vault2)
        XCTAssertEqual(vault2Bindings.count, 1)
    }

    // MARK: - Registry Persistence Tests

    func testRegistryPersistsAcrossInstances() throws {
        let account = DiscoveredAccount(id: "persist-acc", name: "Persist Account", email: nil, type: .mail)
        let vaultPath = "/test/persist"

        // Bind with first registry instance
        try registry.bindAccount(account, toVault: vaultPath)

        // Create new registry instance with same path
        let newRegistry = BindingRegistry(registryPath: registryPath)
        let (bound, _) = try newRegistry.isAccountBound("persist-acc")
        XCTAssertTrue(bound)
    }

    func testEmptyRegistryReturnsEmptyBindings() throws {
        let bindings = try registry.allBindings()
        XCTAssertTrue(bindings.isEmpty)
    }
}
