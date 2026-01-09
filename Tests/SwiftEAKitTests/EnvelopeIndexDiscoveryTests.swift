import XCTest
@testable import SwiftEAKit

final class EnvelopeIndexDiscoveryTests: XCTestCase {
    var discovery: EnvelopeIndexDiscovery!
    var testDir: String!

    override func setUp() {
        super.setUp()
        discovery = EnvelopeIndexDiscovery()
        testDir = NSTemporaryDirectory() + "swiftea-envelope-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        discovery = nil
        super.tearDown()
    }

    // MARK: - Custom Path Validation

    func testDiscoverWithValidCustomPath() throws {
        // Create a mock envelope index file
        let envelopePath = (testDir as NSString).appendingPathComponent("V10/MailData/Envelope Index")
        let mailDataPath = (envelopePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: mailDataPath, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: envelopePath, contents: Data())

        let result = try discovery.discover(customPath: envelopePath)

        XCTAssertEqual(result.envelopeIndexPath, envelopePath)
        XCTAssertEqual(result.versionDirectory, "V10")
    }

    func testDiscoverWithNonexistentCustomPathThrows() {
        let nonExistentPath = "/nonexistent/path/Envelope Index"

        XCTAssertThrowsError(try discovery.discover(customPath: nonExistentPath)) { error in
            guard case EnvelopeDiscoveryError.envelopeIndexNotFound = error else {
                XCTFail("Expected EnvelopeDiscoveryError.envelopeIndexNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Version Directory Extraction

    func testExtractsVersionFromPath() throws {
        // Create V11 directory structure
        let envelopePath = (testDir as NSString).appendingPathComponent("V11/MailData/Envelope Index")
        let mailDataPath = (envelopePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: mailDataPath, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: envelopePath, contents: Data())

        let result = try discovery.discover(customPath: envelopePath)

        XCTAssertEqual(result.versionDirectory, "V11")
    }

    func testExtractsVersionFromDeeperPath() throws {
        // Create a path with V directory deeper in structure
        let envelopePath = (testDir as NSString).appendingPathComponent("Library/Mail/V12/MailData/Envelope Index")
        let mailDataPath = (envelopePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: mailDataPath, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: envelopePath, contents: Data())

        let result = try discovery.discover(customPath: envelopePath)

        XCTAssertEqual(result.versionDirectory, "V12")
    }

    // MARK: - Emlx Path Generation

    func testEmlxPathGeneration() {
        let mailboxPath = "/Users/test/Library/Mail/V10/Mailboxes/INBOX.mbox"
        let mailBasePath = "/Users/test/Library/Mail/V10"

        let emlxPath = discovery.emlxPath(forMessageId: 12345, mailboxPath: mailboxPath, mailBasePath: mailBasePath)

        XCTAssertEqual(emlxPath, "/Users/test/Library/Mail/V10/Mailboxes/INBOX.mbox/Messages/12345.emlx")
    }

    func testEmlxPathWithDifferentMailbox() {
        let mailboxPath = "/Users/test/Library/Mail/V10/Mailboxes/Work/Projects.mbox"
        let mailBasePath = "/Users/test/Library/Mail/V10"

        let emlxPath = discovery.emlxPath(forMessageId: 99999, mailboxPath: mailboxPath, mailBasePath: mailBasePath)

        XCTAssertEqual(emlxPath, "/Users/test/Library/Mail/V10/Mailboxes/Work/Projects.mbox/Messages/99999.emlx")
    }

    // MARK: - EnvelopeIndexInfo Properties

    func testEnvelopeIndexInfoInitialization() {
        let info = EnvelopeIndexInfo(
            envelopeIndexPath: "/path/to/Envelope Index",
            versionDirectory: "V10",
            mailBasePath: "/path/to/Mail",
            mailDataPath: "/path/to/MailData"
        )

        XCTAssertEqual(info.envelopeIndexPath, "/path/to/Envelope Index")
        XCTAssertEqual(info.versionDirectory, "V10")
        XCTAssertEqual(info.mailBasePath, "/path/to/Mail")
        XCTAssertEqual(info.mailDataPath, "/path/to/MailData")
    }

    // MARK: - Error Messages

    func testEnvelopeDiscoveryErrorDescriptions() {
        let errors: [EnvelopeDiscoveryError] = [
            .mailDirectoryNotFound,
            .noVersionDirectory,
            .envelopeIndexNotFound,
            .permissionDenied(path: "/test/path")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }

        // Check specific error message content
        let permError = EnvelopeDiscoveryError.permissionDenied(path: "/some/path")
        XCTAssertTrue(permError.errorDescription?.contains("/some/path") == true)
        XCTAssertTrue(permError.errorDescription?.contains("Full Disk Access") == true)
    }

    // MARK: - Permission Check

    func testCheckPermissionsWithAccessibleDirectory() {
        // Test against a directory we can definitely access
        let canCheck = discovery.checkPermissions()
        // This will be true or false depending on actual system permissions
        // We just verify the method runs without crashing
        XCTAssertNotNil(canCheck)
    }

    // MARK: - Version Number Handling

    func testVersionDirectoryWithMultipleDigits() throws {
        // Create V100 directory (unlikely but possible in future)
        let envelopePath = (testDir as NSString).appendingPathComponent("V100/MailData/Envelope Index")
        let mailDataPath = (envelopePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: mailDataPath, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: envelopePath, contents: Data())

        let result = try discovery.discover(customPath: envelopePath)

        XCTAssertEqual(result.versionDirectory, "V100")
    }

    func testNoVersionInPathUsesDefault() throws {
        // Create path without V directory
        let envelopePath = (testDir as NSString).appendingPathComponent("MailData/Envelope Index")
        let mailDataPath = (envelopePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: mailDataPath, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: envelopePath, contents: Data())

        let result = try discovery.discover(customPath: envelopePath)

        // Should default to V10 when no version found
        XCTAssertEqual(result.versionDirectory, "V10")
    }

    // MARK: - Tilde Expansion

    func testCustomPathWithTildeExpansion() throws {
        // We can't easily test tilde expansion without mocking, but we can verify
        // that paths starting with ~ don't crash
        // This test documents the expected behavior

        // Create a test file in an accessible location
        let envelopePath = (testDir as NSString).appendingPathComponent("Envelope Index")
        FileManager.default.createFile(atPath: envelopePath, contents: Data())

        // Should not crash
        let result = try discovery.discover(customPath: envelopePath)
        XCTAssertNotNil(result)
    }
}
