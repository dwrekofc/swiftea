import XCTest
@testable import SwiftEAKit

// MARK: - Mock AppleScript Service

/// Mock AppleScriptService that records calls and can be configured to succeed or fail
final class MockAppleScriptService: AppleScriptServiceProtocol, @unchecked Sendable {
    var executeMailScriptCalls: [String] = []
    var shouldFail = false
    var failureError: Error = NSError(domain: "Mock", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock failure"])

    func execute(_ script: String) throws -> AppleScriptResult {
        if shouldFail {
            throw failureError
        }
        return .success("success")
    }

    func executeMailScript(_ mailScript: String) throws -> AppleScriptResult {
        executeMailScriptCalls.append(mailScript)
        if shouldFail {
            throw failureError
        }
        return .success("success")
    }

    func checkMailPermission() -> Bool {
        return true
    }

    func ensureMailRunning(timeout: Int) throws {
        // No-op for tests
    }
}

// MARK: - MailSyncBackward Tests

final class MailSyncBackwardTests: XCTestCase {
    var testDir: String!
    var mailDatabase: MailDatabase!
    var mockAppleScript: MockAppleScriptService!
    var backwardSync: MailSyncBackward!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "swiftea-backward-sync-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)

        let dbPath = (testDir as NSString).appendingPathComponent("mail.db")
        mailDatabase = MailDatabase(databasePath: dbPath)
        try! mailDatabase.initialize()

        mockAppleScript = MockAppleScriptService()
        backwardSync = MailSyncBackward(mailDatabase: mailDatabase, appleScriptService: mockAppleScript)
    }

    override func tearDown() {
        mailDatabase.close()
        try? FileManager.default.removeItem(atPath: testDir)
        mailDatabase = nil
        mockAppleScript = nil
        backwardSync = nil
        super.tearDown()
    }

    // MARK: - BackwardSyncResult Tests

    func testBackwardSyncResultInitialization() {
        let result = BackwardSyncResult(archived: 5, deleted: 3, failed: 2, errors: ["Error 1", "Error 2"])

        XCTAssertEqual(result.archived, 5)
        XCTAssertEqual(result.deleted, 3)
        XCTAssertEqual(result.failed, 2)
        XCTAssertEqual(result.errors.count, 2)
    }

    func testBackwardSyncResultDefaults() {
        let result = BackwardSyncResult()

        XCTAssertEqual(result.archived, 0)
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    // MARK: - BackwardSyncError Tests

    func testBackwardSyncErrorMessageNotFound() {
        let error = BackwardSyncError.messageNotFound(id: "test-123")

        XCTAssertTrue(error.errorDescription?.contains("test-123") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("not found") ?? false)
    }

    func testBackwardSyncErrorNoMessageId() {
        let error = BackwardSyncError.noMessageId(id: "test-456")

        XCTAssertTrue(error.errorDescription?.contains("test-456") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("RFC822") ?? false)
    }

    func testBackwardSyncErrorAppleScriptFailed() {
        let underlying = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Script error"])
        let error = BackwardSyncError.appleScriptFailed(id: "test-789", underlying: underlying)

        XCTAssertTrue(error.errorDescription?.contains("test-789") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("AppleScript failed") ?? false)
    }

    func testBackwardSyncErrorRollbackFailed() {
        let underlying = NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "DB error"])
        let error = BackwardSyncError.rollbackFailed(id: "test-abc", underlying: underlying)

        XCTAssertTrue(error.errorDescription?.contains("test-abc") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("rollback") ?? false)
    }

    // MARK: - archiveMessage Tests

    func testArchiveMessageNotFound() throws {
        XCTAssertThrowsError(try backwardSync.archiveMessage(id: "nonexistent")) { error in
            guard case BackwardSyncError.messageNotFound(let id) = error else {
                XCTFail("Expected messageNotFound error, got \(error)")
                return
            }
            XCTAssertEqual(id, "nonexistent")
        }
    }

    func testArchiveMessageNoMessageId() throws {
        // Insert a message without RFC822 messageId
        let message = MailMessage(
            id: "no-msgid",
            messageId: nil,
            subject: "No Message-ID"
        )
        try mailDatabase.upsertMessage(message)

        XCTAssertThrowsError(try backwardSync.archiveMessage(id: "no-msgid")) { error in
            guard case BackwardSyncError.noMessageId(let id) = error else {
                XCTFail("Expected noMessageId error, got \(error)")
                return
            }
            XCTAssertEqual(id, "no-msgid")
        }
    }

    func testArchiveMessageOptimisticUpdateSetsStatusBeforeAppleScript() throws {
        // Insert a message
        let message = MailMessage(
            id: "archive-test-1",
            messageId: "<test@example.com>",
            subject: "Test",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        // Track state during AppleScript execution
        var statusDuringAppleScript: MailboxStatus?
        var pendingActionDuringAppleScript: SyncAction?

        // Configure mock to capture state during execution
        final class CapturingMockAppleScript: AppleScriptServiceProtocol, @unchecked Sendable {
            var onExecute: (() -> Void)?

            func execute(_ script: String) throws -> AppleScriptResult {
                return .success("success")
            }

            func executeMailScript(_ mailScript: String) throws -> AppleScriptResult {
                onExecute?()
                return .success("archived")
            }

            func checkMailPermission() -> Bool { true }
            func ensureMailRunning(timeout: Int) throws {}
        }

        let capturingMock = CapturingMockAppleScript()
        capturingMock.onExecute = {
            // Check DB state during AppleScript execution
            if let msg = try? self.mailDatabase.getMessage(id: "archive-test-1") {
                statusDuringAppleScript = msg.mailboxStatus
                pendingActionDuringAppleScript = msg.pendingSyncAction
            }
        }

        let syncWithCapturing = MailSyncBackward(mailDatabase: mailDatabase, appleScriptService: capturingMock)

        // Archive the message
        try syncWithCapturing.archiveMessage(id: "archive-test-1")

        // Verify optimistic update was applied BEFORE AppleScript
        XCTAssertEqual(statusDuringAppleScript, .archived, "Status should be 'archived' during AppleScript execution")
        XCTAssertEqual(pendingActionDuringAppleScript, .archive, "Pending action should be 'archive' during AppleScript execution")

        // Verify final state after successful execution
        let finalMessage = try mailDatabase.getMessage(id: "archive-test-1")
        XCTAssertEqual(finalMessage?.mailboxStatus, .archived)
        XCTAssertNil(finalMessage?.pendingSyncAction, "Pending action should be cleared after success")
    }

    func testArchiveMessageSuccessUpdatesStatus() throws {
        let message = MailMessage(
            id: "archive-success",
            messageId: "<archive-success@example.com>",
            subject: "Archive Success",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        try backwardSync.archiveMessage(id: "archive-success")

        let retrieved = try mailDatabase.getMessage(id: "archive-success")
        XCTAssertEqual(retrieved?.mailboxStatus, .archived)
        XCTAssertNil(retrieved?.pendingSyncAction)
    }

    func testArchiveMessageCallsAppleScript() throws {
        let message = MailMessage(
            id: "archive-script-test",
            messageId: "<archive-script@example.com>",
            subject: "Archive Script Test",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        try backwardSync.archiveMessage(id: "archive-script-test")

        XCTAssertEqual(mockAppleScript.executeMailScriptCalls.count, 1)
        XCTAssertTrue(mockAppleScript.executeMailScriptCalls.first?.contains("<archive-script@example.com>") ?? false)
        XCTAssertTrue(mockAppleScript.executeMailScriptCalls.first?.contains("Archive") ?? false)
    }

    func testArchiveMessageFailureRollsBack() throws {
        let message = MailMessage(
            id: "archive-fail",
            messageId: "<archive-fail@example.com>",
            subject: "Archive Fail",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        // Configure mock to fail
        mockAppleScript.shouldFail = true

        XCTAssertThrowsError(try backwardSync.archiveMessage(id: "archive-fail")) { error in
            guard case BackwardSyncError.appleScriptFailed = error else {
                XCTFail("Expected appleScriptFailed error")
                return
            }
        }

        // Verify rollback occurred
        let retrieved = try mailDatabase.getMessage(id: "archive-fail")
        XCTAssertEqual(retrieved?.mailboxStatus, .inbox, "Status should be rolled back to original")
        XCTAssertNil(retrieved?.pendingSyncAction, "Pending action should be cleared")
    }

    func testArchiveMessageFailurePreservesOriginalStatus() throws {
        // Start with archived status
        let message = MailMessage(
            id: "archive-archived",
            messageId: "<archive-archived@example.com>",
            subject: "Already Archived",
            mailboxStatus: .archived
        )
        try mailDatabase.upsertMessage(message)

        mockAppleScript.shouldFail = true

        XCTAssertThrowsError(try backwardSync.archiveMessage(id: "archive-archived"))

        // Should rollback to original archived status
        let retrieved = try mailDatabase.getMessage(id: "archive-archived")
        XCTAssertEqual(retrieved?.mailboxStatus, .archived)
    }

    // MARK: - deleteMessage Tests

    func testDeleteMessageNotFound() throws {
        XCTAssertThrowsError(try backwardSync.deleteMessage(id: "nonexistent")) { error in
            guard case BackwardSyncError.messageNotFound(let id) = error else {
                XCTFail("Expected messageNotFound error")
                return
            }
            XCTAssertEqual(id, "nonexistent")
        }
    }

    func testDeleteMessageNoMessageId() throws {
        let message = MailMessage(
            id: "no-delete-msgid",
            messageId: nil,
            subject: "No Message-ID"
        )
        try mailDatabase.upsertMessage(message)

        XCTAssertThrowsError(try backwardSync.deleteMessage(id: "no-delete-msgid")) { error in
            guard case BackwardSyncError.noMessageId(let id) = error else {
                XCTFail("Expected noMessageId error")
                return
            }
            XCTAssertEqual(id, "no-delete-msgid")
        }
    }

    func testDeleteMessageOptimisticUpdateSetsStatusBeforeAppleScript() throws {
        let message = MailMessage(
            id: "delete-test-1",
            messageId: "<delete@example.com>",
            subject: "Test",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        var statusDuringAppleScript: MailboxStatus?
        var pendingActionDuringAppleScript: SyncAction?

        final class CapturingMockAppleScript: AppleScriptServiceProtocol, @unchecked Sendable {
            var onExecute: (() -> Void)?

            func execute(_ script: String) throws -> AppleScriptResult {
                return .success("success")
            }

            func executeMailScript(_ mailScript: String) throws -> AppleScriptResult {
                onExecute?()
                return .success("deleted")
            }

            func checkMailPermission() -> Bool { true }
            func ensureMailRunning(timeout: Int) throws {}
        }

        let capturingMock = CapturingMockAppleScript()
        capturingMock.onExecute = {
            if let msg = try? self.mailDatabase.getMessage(id: "delete-test-1") {
                statusDuringAppleScript = msg.mailboxStatus
                pendingActionDuringAppleScript = msg.pendingSyncAction
            }
        }

        let syncWithCapturing = MailSyncBackward(mailDatabase: mailDatabase, appleScriptService: capturingMock)

        try syncWithCapturing.deleteMessage(id: "delete-test-1")

        XCTAssertEqual(statusDuringAppleScript, .deleted, "Status should be 'deleted' during AppleScript execution")
        XCTAssertEqual(pendingActionDuringAppleScript, .delete, "Pending action should be 'delete' during AppleScript execution")

        let finalMessage = try mailDatabase.getMessage(id: "delete-test-1")
        XCTAssertEqual(finalMessage?.mailboxStatus, .deleted)
        XCTAssertNil(finalMessage?.pendingSyncAction)
    }

    func testDeleteMessageSuccessUpdatesStatus() throws {
        let message = MailMessage(
            id: "delete-success",
            messageId: "<delete-success@example.com>",
            subject: "Delete Success",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        try backwardSync.deleteMessage(id: "delete-success")

        let retrieved = try mailDatabase.getMessage(id: "delete-success")
        XCTAssertEqual(retrieved?.mailboxStatus, .deleted)
        XCTAssertNil(retrieved?.pendingSyncAction)
    }

    func testDeleteMessageCallsAppleScript() throws {
        let message = MailMessage(
            id: "delete-script-test",
            messageId: "<delete-script@example.com>",
            subject: "Delete Script Test",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        try backwardSync.deleteMessage(id: "delete-script-test")

        XCTAssertEqual(mockAppleScript.executeMailScriptCalls.count, 1)
        XCTAssertTrue(mockAppleScript.executeMailScriptCalls.first?.contains("<delete-script@example.com>") ?? false)
        XCTAssertTrue(mockAppleScript.executeMailScriptCalls.first?.contains("delete") ?? false)
    }

    func testDeleteMessageFailureRollsBack() throws {
        let message = MailMessage(
            id: "delete-fail",
            messageId: "<delete-fail@example.com>",
            subject: "Delete Fail",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        mockAppleScript.shouldFail = true

        XCTAssertThrowsError(try backwardSync.deleteMessage(id: "delete-fail")) { error in
            guard case BackwardSyncError.appleScriptFailed = error else {
                XCTFail("Expected appleScriptFailed error")
                return
            }
        }

        let retrieved = try mailDatabase.getMessage(id: "delete-fail")
        XCTAssertEqual(retrieved?.mailboxStatus, .inbox, "Status should be rolled back to original")
        XCTAssertNil(retrieved?.pendingSyncAction)
    }

    func testDeleteMessageFromArchivedRollsBackToArchived() throws {
        let message = MailMessage(
            id: "delete-from-archived",
            messageId: "<delete-from-archived@example.com>",
            subject: "Delete From Archived",
            mailboxStatus: .archived
        )
        try mailDatabase.upsertMessage(message)

        mockAppleScript.shouldFail = true

        XCTAssertThrowsError(try backwardSync.deleteMessage(id: "delete-from-archived"))

        let retrieved = try mailDatabase.getMessage(id: "delete-from-archived")
        XCTAssertEqual(retrieved?.mailboxStatus, .archived, "Should rollback to archived status")
    }

    // MARK: - processPendingActions Tests

    func testProcessPendingActionsEmptyReturnsZeroCounts() throws {
        let result = try backwardSync.processPendingActions()

        XCTAssertEqual(result.archived, 0)
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testProcessPendingActionsProcessesArchiveActions() throws {
        // Insert messages with pending archive actions
        let messages = [
            MailMessage(id: "pending-archive-1", messageId: "<pa1@example.com>", subject: "PA 1", mailboxStatus: .archived, pendingSyncAction: .archive),
            MailMessage(id: "pending-archive-2", messageId: "<pa2@example.com>", subject: "PA 2", mailboxStatus: .archived, pendingSyncAction: .archive)
        ]
        for msg in messages {
            try mailDatabase.upsertMessage(msg)
        }

        let result = try backwardSync.processPendingActions()

        XCTAssertEqual(result.archived, 2)
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.failed, 0)

        // Verify pending actions were cleared
        for msg in messages {
            let retrieved = try mailDatabase.getMessage(id: msg.id)
            XCTAssertNil(retrieved?.pendingSyncAction)
        }
    }

    func testProcessPendingActionsProcessesDeleteActions() throws {
        let messages = [
            MailMessage(id: "pending-delete-1", messageId: "<pd1@example.com>", subject: "PD 1", mailboxStatus: .deleted, pendingSyncAction: .delete),
            MailMessage(id: "pending-delete-2", messageId: "<pd2@example.com>", subject: "PD 2", mailboxStatus: .deleted, pendingSyncAction: .delete),
            MailMessage(id: "pending-delete-3", messageId: "<pd3@example.com>", subject: "PD 3", mailboxStatus: .deleted, pendingSyncAction: .delete)
        ]
        for msg in messages {
            try mailDatabase.upsertMessage(msg)
        }

        let result = try backwardSync.processPendingActions()

        XCTAssertEqual(result.archived, 0)
        XCTAssertEqual(result.deleted, 3)
        XCTAssertEqual(result.failed, 0)
    }

    func testProcessPendingActionsHandlesMixedActions() throws {
        let messages = [
            MailMessage(id: "mixed-1", messageId: "<m1@example.com>", subject: "Mixed 1", mailboxStatus: .archived, pendingSyncAction: .archive),
            MailMessage(id: "mixed-2", messageId: "<m2@example.com>", subject: "Mixed 2", mailboxStatus: .deleted, pendingSyncAction: .delete),
            MailMessage(id: "mixed-3", messageId: "<m3@example.com>", subject: "Mixed 3", mailboxStatus: .archived, pendingSyncAction: .archive)
        ]
        for msg in messages {
            try mailDatabase.upsertMessage(msg)
        }

        let result = try backwardSync.processPendingActions()

        XCTAssertEqual(result.archived, 2)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertEqual(result.failed, 0)
    }

    func testProcessPendingActionsSkipsMessagesWithoutMessageId() throws {
        let messages = [
            MailMessage(id: "no-msgid-1", messageId: nil, subject: "No ID 1", mailboxStatus: .archived, pendingSyncAction: .archive),
            MailMessage(id: "has-msgid", messageId: "<has@example.com>", subject: "Has ID", mailboxStatus: .archived, pendingSyncAction: .archive)
        ]
        for msg in messages {
            try mailDatabase.upsertMessage(msg)
        }

        let result = try backwardSync.processPendingActions()

        XCTAssertEqual(result.archived, 1)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors.first?.contains("no-msgid-1") ?? false)

        // Message with ID should have pending action cleared
        let hasId = try mailDatabase.getMessage(id: "has-msgid")
        XCTAssertNil(hasId?.pendingSyncAction)

        // Message without ID should still have pending action (for retry or manual fix)
        let noId = try mailDatabase.getMessage(id: "no-msgid-1")
        XCTAssertEqual(noId?.pendingSyncAction, .archive)
    }

    func testProcessPendingActionsCountsFailedAppleScript() throws {
        let message = MailMessage(
            id: "fail-processing",
            messageId: "<fail@example.com>",
            subject: "Fail",
            mailboxStatus: .archived,
            pendingSyncAction: .archive
        )
        try mailDatabase.upsertMessage(message)

        mockAppleScript.shouldFail = true

        let result = try backwardSync.processPendingActions()

        XCTAssertEqual(result.archived, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.errors.count, 1)

        // Pending action should NOT be cleared on failure (for retry)
        let retrieved = try mailDatabase.getMessage(id: "fail-processing")
        XCTAssertEqual(retrieved?.pendingSyncAction, .archive)
    }

    func testProcessPendingActionsDoesNotClearFailedActions() throws {
        let messages = [
            MailMessage(id: "success-1", messageId: "<s1@example.com>", subject: "Success", mailboxStatus: .archived, pendingSyncAction: .archive),
            MailMessage(id: "fail-1", messageId: "<f1@example.com>", subject: "Fail", mailboxStatus: .deleted, pendingSyncAction: .delete)
        ]
        for msg in messages {
            try mailDatabase.upsertMessage(msg)
        }

        // Configure mock to fail only on delete scripts
        final class SelectiveFailMock: AppleScriptServiceProtocol, @unchecked Sendable {
            func execute(_ script: String) throws -> AppleScriptResult {
                return .success("success")
            }

            func executeMailScript(_ mailScript: String) throws -> AppleScriptResult {
                if mailScript.contains("delete") {
                    throw NSError(domain: "Mock", code: -1, userInfo: [:])
                }
                return .success("success")
            }

            func checkMailPermission() -> Bool { true }
            func ensureMailRunning(timeout: Int) throws {}
        }

        let selectiveMock = SelectiveFailMock()
        let selectiveSync = MailSyncBackward(mailDatabase: mailDatabase, appleScriptService: selectiveMock)

        let result = try selectiveSync.processPendingActions()

        XCTAssertEqual(result.archived, 1)
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.failed, 1)

        // Success should be cleared
        let success = try mailDatabase.getMessage(id: "success-1")
        XCTAssertNil(success?.pendingSyncAction)

        // Failed should retain pending action for retry
        let failed = try mailDatabase.getMessage(id: "fail-1")
        XCTAssertEqual(failed?.pendingSyncAction, .delete)
    }

    func testProcessPendingActionsSkipsMessagesWithNoPendingAction() throws {
        // Insert messages with and without pending actions
        let messages = [
            MailMessage(id: "with-action", messageId: "<wa@example.com>", subject: "With Action", mailboxStatus: .archived, pendingSyncAction: .archive),
            MailMessage(id: "no-action", messageId: "<na@example.com>", subject: "No Action", mailboxStatus: .inbox, pendingSyncAction: nil)
        ]
        for msg in messages {
            try mailDatabase.upsertMessage(msg)
        }

        let result = try backwardSync.processPendingActions()

        // Should only process the one with pending action
        XCTAssertEqual(result.archived, 1)
        XCTAssertEqual(mockAppleScript.executeMailScriptCalls.count, 1)
    }

    // MARK: - MailSyncBackwardScripts Tests

    func testArchiveMessageScriptContainsMessageId() {
        let script = MailSyncBackwardScripts.archiveMessage(byMessageId: "<test@example.com>")

        XCTAssertTrue(script.contains("<test@example.com>"))
        XCTAssertTrue(script.contains("Archive"))
        XCTAssertTrue(script.contains("move"))
    }

    func testDeleteMessageScriptContainsMessageId() {
        let script = MailSyncBackwardScripts.deleteMessage(byMessageId: "<delete@example.com>")

        XCTAssertTrue(script.contains("<delete@example.com>"))
        XCTAssertTrue(script.contains("delete"))
    }

    func testScriptsEscapeSpecialCharacters() {
        // Test with quotes
        let scriptWithQuotes = MailSyncBackwardScripts.archiveMessage(byMessageId: "test\"quote@example.com")
        XCTAssertTrue(scriptWithQuotes.contains("\\\""))

        // Test with backslash
        let scriptWithBackslash = MailSyncBackwardScripts.archiveMessage(byMessageId: "test\\back@example.com")
        XCTAssertTrue(scriptWithBackslash.contains("\\\\"))
    }

    func testScriptsIncludeErrorHandling() {
        let script = MailSyncBackwardScripts.archiveMessage(byMessageId: "<test@example.com>")

        // Should include error handling for message not found
        XCTAssertTrue(script.contains("-1728"))
        XCTAssertTrue(script.contains("error"))
    }

    // MARK: - Integration Tests

    func testFullArchiveWorkflow() throws {
        // Insert a message in inbox
        let message = MailMessage(
            id: "full-archive-test",
            messageId: "<full-archive@example.com>",
            subject: "Full Archive Test",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        // Verify initial state
        var retrieved = try mailDatabase.getMessage(id: "full-archive-test")
        XCTAssertEqual(retrieved?.mailboxStatus, .inbox)
        XCTAssertNil(retrieved?.pendingSyncAction)

        // Archive the message
        try backwardSync.archiveMessage(id: "full-archive-test")

        // Verify final state
        retrieved = try mailDatabase.getMessage(id: "full-archive-test")
        XCTAssertEqual(retrieved?.mailboxStatus, .archived)
        XCTAssertNil(retrieved?.pendingSyncAction)

        // Verify AppleScript was called correctly
        XCTAssertEqual(mockAppleScript.executeMailScriptCalls.count, 1)
    }

    func testFullDeleteWorkflow() throws {
        let message = MailMessage(
            id: "full-delete-test",
            messageId: "<full-delete@example.com>",
            subject: "Full Delete Test",
            mailboxStatus: .inbox
        )
        try mailDatabase.upsertMessage(message)

        try backwardSync.deleteMessage(id: "full-delete-test")

        let retrieved = try mailDatabase.getMessage(id: "full-delete-test")
        XCTAssertEqual(retrieved?.mailboxStatus, .deleted)
        XCTAssertNil(retrieved?.pendingSyncAction)
        XCTAssertEqual(mockAppleScript.executeMailScriptCalls.count, 1)
    }

    func testPendingActionsFromFailedSyncArereprocessed() throws {
        // Simulate a previous failed sync by inserting a message with pending action
        let message = MailMessage(
            id: "retry-test",
            messageId: "<retry@example.com>",
            subject: "Retry Test",
            mailboxStatus: .archived,
            pendingSyncAction: .archive
        )
        try mailDatabase.upsertMessage(message)

        // Process pending actions (simulating daemon sync)
        let result = try backwardSync.processPendingActions()

        XCTAssertEqual(result.archived, 1)
        XCTAssertEqual(result.failed, 0)

        // Verify pending action is now cleared
        let retrieved = try mailDatabase.getMessage(id: "retry-test")
        XCTAssertNil(retrieved?.pendingSyncAction)
    }
}
