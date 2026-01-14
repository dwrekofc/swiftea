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

    // MARK: - Calendar Settings Tests

    func testCalendarSettingsDefaults() {
        let settings = CalendarSettings()

        XCTAssertNil(settings.defaultCalendar)
        XCTAssertEqual(settings.dateRangeDays, 365)
        XCTAssertEqual(settings.syncIntervalMinutes, 5)
        XCTAssertTrue(settings.expandRecurring)
        XCTAssertEqual(settings.exportFormat, "markdown")
        XCTAssertNil(settings.exportOutputDir)
    }

    func testCalendarSettingsGetValue() {
        let settings = CalendarSettings(
            defaultCalendar: "Work",
            dateRangeDays: 180,
            syncIntervalMinutes: 10,
            expandRecurring: false,
            exportFormat: "json",
            exportOutputDir: "/exports"
        )

        XCTAssertEqual(settings.getValue(for: "calendar.defaultCalendar"), "Work")
        XCTAssertEqual(settings.getValue(for: "calendar.dateRangeDays"), "180")
        XCTAssertEqual(settings.getValue(for: "calendar.syncIntervalMinutes"), "10")
        XCTAssertEqual(settings.getValue(for: "calendar.expandRecurring"), "false")
        XCTAssertEqual(settings.getValue(for: "calendar.export.format"), "json")
        XCTAssertEqual(settings.getValue(for: "calendar.export.outputDir"), "/exports")
        XCTAssertNil(settings.getValue(for: "calendar.unknown"))
    }

    func testCalendarSettingsSetValueDefaultCalendar() {
        var settings = CalendarSettings()

        let error = settings.setValue("Personal", for: "calendar.defaultCalendar")
        XCTAssertNil(error)
        XCTAssertEqual(settings.defaultCalendar, "Personal")

        // Empty value should clear the setting
        let error2 = settings.setValue("", for: "calendar.defaultCalendar")
        XCTAssertNil(error2)
        XCTAssertNil(settings.defaultCalendar)
    }

    func testCalendarSettingsSetValueDateRangeDays() {
        var settings = CalendarSettings()

        // Valid value
        let error = settings.setValue("180", for: "calendar.dateRangeDays")
        XCTAssertNil(error)
        XCTAssertEqual(settings.dateRangeDays, 180)

        // Too small
        let error2 = settings.setValue("0", for: "calendar.dateRangeDays")
        XCTAssertNotNil(error2)

        // Too large
        let error3 = settings.setValue("5000", for: "calendar.dateRangeDays")
        XCTAssertNotNil(error3)

        // Invalid
        let error4 = settings.setValue("abc", for: "calendar.dateRangeDays")
        XCTAssertNotNil(error4)
    }

    func testCalendarSettingsSetValueSyncInterval() {
        var settings = CalendarSettings()

        // Valid value
        let error = settings.setValue("15", for: "calendar.syncIntervalMinutes")
        XCTAssertNil(error)
        XCTAssertEqual(settings.syncIntervalMinutes, 15)

        // Too small
        let error2 = settings.setValue("0", for: "calendar.syncIntervalMinutes")
        XCTAssertNotNil(error2)

        // Invalid
        let error3 = settings.setValue("abc", for: "calendar.syncIntervalMinutes")
        XCTAssertNotNil(error3)
    }

    func testCalendarSettingsSetValueExpandRecurring() {
        var settings = CalendarSettings()

        // Set to false
        let error = settings.setValue("false", for: "calendar.expandRecurring")
        XCTAssertNil(error)
        XCTAssertFalse(settings.expandRecurring)

        // Set back to true
        let error2 = settings.setValue("true", for: "calendar.expandRecurring")
        XCTAssertNil(error2)
        XCTAssertTrue(settings.expandRecurring)

        // Alternative values
        var settings2 = CalendarSettings()
        _ = settings2.setValue("yes", for: "calendar.expandRecurring")
        XCTAssertTrue(settings2.expandRecurring)

        var settings3 = CalendarSettings()
        _ = settings3.setValue("no", for: "calendar.expandRecurring")
        XCTAssertFalse(settings3.expandRecurring)

        // Invalid
        var settings4 = CalendarSettings()
        let error4 = settings4.setValue("maybe", for: "calendar.expandRecurring")
        XCTAssertNotNil(error4)
    }

    func testCalendarSettingsSetValueExportFormat() {
        var settings = CalendarSettings()

        // Valid formats
        let error = settings.setValue("json", for: "calendar.export.format")
        XCTAssertNil(error)
        XCTAssertEqual(settings.exportFormat, "json")

        let error2 = settings.setValue("ics", for: "calendar.export.format")
        XCTAssertNil(error2)
        XCTAssertEqual(settings.exportFormat, "ics")

        let error3 = settings.setValue("md", for: "calendar.export.format")
        XCTAssertNil(error3)
        XCTAssertEqual(settings.exportFormat, "markdown") // md -> markdown normalization

        // Invalid
        let error4 = settings.setValue("xml", for: "calendar.export.format")
        XCTAssertNotNil(error4)
    }

    func testCalendarSettingsSetValueUnknownKey() {
        var settings = CalendarSettings()
        let error = settings.setValue("value", for: "calendar.unknown")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("Unknown key"))
    }

    func testCalendarSettingsConfigKeys() {
        let keys = CalendarSettings.keys

        XCTAssertTrue(keys.keys.contains("calendar.defaultCalendar"))
        XCTAssertTrue(keys.keys.contains("calendar.dateRangeDays"))
        XCTAssertTrue(keys.keys.contains("calendar.syncIntervalMinutes"))
        XCTAssertTrue(keys.keys.contains("calendar.expandRecurring"))
        XCTAssertTrue(keys.keys.contains("calendar.export.format"))
        XCTAssertTrue(keys.keys.contains("calendar.export.outputDir"))
    }

    func testVaultConfigIncludesCalendarSettings() throws {
        let vaultPath = testDir + "/calendar-config-test"
        try FileManager.default.createDirectory(atPath: vaultPath, withIntermediateDirectories: true)
        _ = try manager.initializeVault(at: vaultPath)

        // Read initial config
        var config = try manager.readConfig(from: vaultPath)

        // Modify calendar settings
        config.calendar.dateRangeDays = 90
        config.calendar.syncIntervalMinutes = 10
        config.calendar.exportFormat = "json"
        try manager.writeConfig(config, to: vaultPath)

        // Read again and verify
        let updatedConfig = try manager.readConfig(from: vaultPath)
        XCTAssertEqual(updatedConfig.calendar.dateRangeDays, 90)
        XCTAssertEqual(updatedConfig.calendar.syncIntervalMinutes, 10)
        XCTAssertEqual(updatedConfig.calendar.exportFormat, "json")
    }
}
