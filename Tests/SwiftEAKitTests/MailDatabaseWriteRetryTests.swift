import XCTest
import Libsql
@testable import SwiftEAKit

final class MailDatabaseWriteRetryTests: XCTestCase {
    var testDir: String!
    var database: MailDatabase!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-maildb-write-retry-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)

        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        database = MailDatabase(databasePath: dbPath)
    }

    override func tearDown() {
        database.close()
        try? FileManager.default.removeItem(atPath: testDir)
        database = nil
        super.tearDown()
    }

    func testUpdateMailboxStatusRetriesWhenDatabaseIsLocked() throws {
        try database.initialize()

        let message = MailMessage(
            id: "lock-retry-test-id",
            appleRowId: 1,
            subject: "Lock Retry"
        )
        try database.upsertMessage(message)

        // Hold a write lock with a separate libsql connection.
        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        let lockDb = try Database(dbPath)
        let lockConn = try lockDb.connect()
        _ = try lockConn.execute("BEGIN IMMEDIATE")

        let expectation = expectation(description: "updateMailboxStatus completes after lock release")
        let errorLock = NSLock()
        var backgroundError: Error?

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.database.updateMailboxStatus(id: message.id, status: .archived)
            } catch {
                errorLock.lock()
                backgroundError = error
                errorLock.unlock()
            }
            expectation.fulfill()
        }

        // Release the lock shortly after starting the update.
        usleep(300_000)
        _ = try lockConn.execute("COMMIT")

        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(waiterResult, .completed, "Timed out waiting for updateMailboxStatus to complete")

        errorLock.lock()
        let error = backgroundError
        errorLock.unlock()
        XCTAssertNil(error, "Expected updateMailboxStatus to retry and succeed, got: \(String(describing: error))")

        let updated = try database.getMessage(id: message.id)
        XCTAssertEqual(updated?.mailboxStatus, .archived)
    }
}
