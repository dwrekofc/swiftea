import XCTest
@testable import SwiftEAKit

final class AppleScriptServiceTests: XCTestCase {

    // MARK: - AppleScriptError Tests

    func testAutomationPermissionDeniedErrorDescription() {
        let error = AppleScriptError.automationPermissionDenied(guidance: "Test guidance")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Automation permission denied"))
        XCTAssertTrue(error.errorDescription!.contains("Test guidance"))
    }

    func testMailAppNotRespondingErrorDescription() {
        let error = AppleScriptError.mailAppNotResponding(underlying: "Connection failed")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Mail.app is not running"))
        XCTAssertTrue(error.errorDescription!.contains("Connection failed"))
    }

    func testMessageNotFoundErrorDescription() {
        let error = AppleScriptError.messageNotFound(messageId: "test-123")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Message not found"))
        XCTAssertTrue(error.errorDescription!.contains("test-123"))
    }

    func testMessageResolutionAmbiguousErrorDescription() {
        let error = AppleScriptError.messageResolutionAmbiguous(count: 5, suggestion: "Use --message-id")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("5 messages"))
        XCTAssertTrue(error.errorDescription!.contains("Use --message-id"))
    }

    func testMailboxNotFoundErrorDescription() {
        let error = AppleScriptError.mailboxNotFound(mailbox: "INBOX")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Mailbox not found"))
        XCTAssertTrue(error.errorDescription!.contains("INBOX"))
    }

    func testScriptCompilationFailedErrorDescription() {
        let error = AppleScriptError.scriptCompilationFailed(details: "Syntax error on line 5")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("compilation failed"))
        XCTAssertTrue(error.errorDescription!.contains("Syntax error"))
    }

    func testExecutionFailedErrorDescription() {
        let error = AppleScriptError.executionFailed(code: -1728, message: "Can't get object")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("error -1728"))
        XCTAssertTrue(error.errorDescription!.contains("Can't get object"))
    }

    // MARK: - Recovery Guidance Tests

    func testAutomationPermissionDeniedHasRecoveryGuidance() {
        let error = AppleScriptError.automationPermissionDenied(guidance: "Test")
        XCTAssertNotNil(error.recoveryGuidance)
        XCTAssertTrue(error.recoveryGuidance!.contains("System Settings"))
        XCTAssertTrue(error.recoveryGuidance!.contains("Privacy & Security"))
    }

    func testMailAppNotRespondingHasRecoveryGuidance() {
        let error = AppleScriptError.mailAppNotResponding(underlying: "Test")
        XCTAssertNotNil(error.recoveryGuidance)
        XCTAssertTrue(error.recoveryGuidance!.contains("opening Mail.app"))
    }

    func testMessageNotFoundHasRecoveryGuidance() {
        let error = AppleScriptError.messageNotFound(messageId: "test")
        XCTAssertNotNil(error.recoveryGuidance)
        XCTAssertTrue(error.recoveryGuidance!.contains("sync"))
    }

    func testMessageResolutionAmbiguousHasRecoveryGuidance() {
        let error = AppleScriptError.messageResolutionAmbiguous(count: 2, suggestion: "test")
        XCTAssertNotNil(error.recoveryGuidance)
        XCTAssertTrue(error.recoveryGuidance!.contains("--message-id"))
    }

    func testMailboxNotFoundHasRecoveryGuidance() {
        let error = AppleScriptError.mailboxNotFound(mailbox: "Test")
        XCTAssertNotNil(error.recoveryGuidance)
    }

    func testExecutionFailedHasNoRecoveryGuidance() {
        let error = AppleScriptError.executionFailed(code: -1, message: "test")
        XCTAssertNil(error.recoveryGuidance)
    }

    // MARK: - AppleScriptResult Tests

    func testAppleScriptResultSuccess() {
        let result = AppleScriptResult.success("test output")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "test output")
    }

    func testAppleScriptResultSuccessNoOutput() {
        let result = AppleScriptResult.success()
        XCTAssertTrue(result.success)
        XCTAssertNil(result.output)
    }

    // MARK: - MailActionScripts Tests

    // MARK: Message Resolution Helper Tests

    /// Tests that the message resolution helper generates correct AppleScript fragment.
    /// The helper is private but we can verify its output through the public methods.
    func testMessageResolutionHelperGeneratesCorrectScript() {
        // All action scripts should contain the same mailbox-search resolution pattern
        // Note: Mail.app doesn't support global message searches, so we search within mailboxes
        let testMessageId = "<test-resolution@example.com>"
        let strippedMessageId = "test-resolution@example.com"  // Angle brackets are stripped

        let deleteScript = MailActionScripts.deleteMessage(byMessageId: testMessageId)
        let moveScript = MailActionScripts.moveMessage(byMessageId: testMessageId, toMailbox: "Archive")
        let flagScript = MailActionScripts.setFlag(byMessageId: testMessageId, flagged: true)
        let readScript = MailActionScripts.setReadStatus(byMessageId: testMessageId, read: true)
        let replyScript = MailActionScripts.createReply(byMessageId: testMessageId, replyToAll: false, body: nil, send: false)

        // All scripts should have the new mailbox-search resolution pattern
        let expectedResolutionComponents = [
            "set targetMsgId to \"\(strippedMessageId)\"",
            "set theMessage to missing value",
            "set searchMailboxes to {\"Inbox\", \"Sent Items\", \"Sent\", \"Archive\"}",
            "repeat with acc in accounts",
            "repeat with mboxName in searchMailboxes",
            "every message of targetMbox whose message id is targetMsgId",
            "if (count of foundMsgs) > 0",
            "set theMessage to item 1 of foundMsgs",
            "if theMessage is missing value",
            "error \"Message not found:"
        ]

        let scripts = [
            ("deleteMessage", deleteScript),
            ("moveMessage", moveScript),
            ("setFlag", flagScript),
            ("setReadStatus", readScript),
            ("createReply", replyScript)
        ]

        // Verify all scripts contain the new resolution pattern
        for (name, script) in scripts {
            for component in expectedResolutionComponents {
                XCTAssertTrue(script.contains(component), "\(name) should contain: \(component)")
            }
            // Verify angle brackets are stripped
            XCTAssertFalse(script.contains("<test-resolution@example.com>"), "\(name) should not contain angle brackets in message ID")
        }
    }

    /// Tests that all action methods use theMessage variable after resolution
    func testAllActionMethodsUseTheMessageVariable() {
        let testMessageId = "<var-test@example.com>"

        // deleteMessage should use theMessage
        let deleteScript = MailActionScripts.deleteMessage(byMessageId: testMessageId)
        XCTAssertTrue(deleteScript.contains("delete theMessage"), "deleteMessage should use theMessage variable")

        // moveMessage should use theMessage
        let moveScript = MailActionScripts.moveMessage(byMessageId: testMessageId, toMailbox: "Archive")
        XCTAssertTrue(moveScript.contains("move theMessage"), "moveMessage should use theMessage variable")

        // setFlag should use theMessage
        let flagScript = MailActionScripts.setFlag(byMessageId: testMessageId, flagged: true)
        XCTAssertTrue(flagScript.contains("flagged status of theMessage"), "setFlag should use theMessage variable")

        // setReadStatus should use theMessage
        let readScript = MailActionScripts.setReadStatus(byMessageId: testMessageId, read: true)
        XCTAssertTrue(readScript.contains("read status of theMessage"), "setReadStatus should use theMessage variable")

        // createReply should use theMessage
        let replyScript = MailActionScripts.createReply(byMessageId: testMessageId, replyToAll: false, body: nil, send: false)
        XCTAssertTrue(replyScript.contains("reply to theMessage"), "createReply should use theMessage variable")
    }

    func testDeleteMessageScript() {
        let script = MailActionScripts.deleteMessage(byMessageId: "<test@example.com>")
        // Note: angle brackets are stripped for Mail.app AppleScript lookup
        XCTAssertTrue(script.contains("test@example.com"))
        XCTAssertFalse(script.contains("<test@example.com>"), "Angle brackets should be stripped")
        XCTAssertTrue(script.contains("delete"))
        XCTAssertTrue(script.contains("message id"))
    }

    func testMoveMessageScript() {
        let script = MailActionScripts.moveMessage(byMessageId: "<test@example.com>", toMailbox: "Archive")
        // Note: angle brackets are stripped for Mail.app AppleScript lookup
        XCTAssertTrue(script.contains("test@example.com"))
        XCTAssertFalse(script.contains("<test@example.com>"), "Angle brackets should be stripped")
        XCTAssertTrue(script.contains("move"))
        XCTAssertTrue(script.contains("Archive"))
    }

    func testMoveMessageScriptWithAccount() {
        let script = MailActionScripts.moveMessage(
            byMessageId: "<test@example.com>",
            toMailbox: "Archive",
            inAccount: "Work"
        )
        // Note: angle brackets are stripped for Mail.app AppleScript lookup
        XCTAssertTrue(script.contains("test@example.com"))
        XCTAssertFalse(script.contains("<test@example.com>"), "Angle brackets should be stripped")
        XCTAssertTrue(script.contains("move"))
        XCTAssertTrue(script.contains("Archive"))
        XCTAssertTrue(script.contains("Work"))
    }

    func testSetFlagScript() {
        let flagScript = MailActionScripts.setFlag(byMessageId: "<test@example.com>", flagged: true)
        XCTAssertTrue(flagScript.contains("flagged status"))
        XCTAssertTrue(flagScript.contains("true"))

        let unflagScript = MailActionScripts.setFlag(byMessageId: "<test@example.com>", flagged: false)
        XCTAssertTrue(unflagScript.contains("flagged status"))
        XCTAssertTrue(unflagScript.contains("false"))
    }

    func testSetReadStatusScript() {
        let readScript = MailActionScripts.setReadStatus(byMessageId: "<test@example.com>", read: true)
        XCTAssertTrue(readScript.contains("read status"))
        XCTAssertTrue(readScript.contains("true"))

        let unreadScript = MailActionScripts.setReadStatus(byMessageId: "<test@example.com>", read: false)
        XCTAssertTrue(unreadScript.contains("read status"))
        XCTAssertTrue(unreadScript.contains("false"))
    }

    func testCreateReplyScript() {
        let replyScript = MailActionScripts.createReply(
            byMessageId: "<test@example.com>",
            replyToAll: false,
            body: "Test reply",
            send: false
        )
        XCTAssertTrue(replyScript.contains("reply to"))
        XCTAssertFalse(replyScript.contains("reply to all"))
        XCTAssertTrue(replyScript.contains("Test reply"))
        XCTAssertTrue(replyScript.contains("open"))
    }

    func testCreateReplyAllScript() {
        let replyScript = MailActionScripts.createReply(
            byMessageId: "<test@example.com>",
            replyToAll: true,
            body: nil,
            send: true
        )
        XCTAssertTrue(replyScript.contains("reply to all"))
        XCTAssertTrue(replyScript.contains("send"))
    }

    func testComposeScript() {
        let composeScript = MailActionScripts.compose(
            to: "test@example.com",
            subject: "Test Subject",
            body: "Test body",
            cc: "cc@example.com",
            bcc: "bcc@example.com",
            send: false
        )
        XCTAssertTrue(composeScript.contains("test@example.com"))
        XCTAssertTrue(composeScript.contains("Test Subject"))
        XCTAssertTrue(composeScript.contains("Test body"))
        XCTAssertTrue(composeScript.contains("to recipient"))
        XCTAssertTrue(composeScript.contains("cc recipient"))
        XCTAssertTrue(composeScript.contains("bcc recipient"))
    }

    func testComposeScriptWithSend() {
        let composeScript = MailActionScripts.compose(
            to: "test@example.com",
            subject: "Test",
            body: nil,
            cc: nil,
            bcc: nil,
            send: true
        )
        XCTAssertTrue(composeScript.contains("send theMessage"))
    }

    func testComposeScriptMultipleRecipients() {
        let composeScript = MailActionScripts.compose(
            to: "a@example.com, b@example.com",
            subject: "Test",
            body: nil,
            cc: nil,
            bcc: nil,
            send: false
        )
        XCTAssertTrue(composeScript.contains("a@example.com"))
        XCTAssertTrue(composeScript.contains("b@example.com"))
    }

    // MARK: - String Escaping Tests

    func testScriptEscapesQuotes() {
        let script = MailActionScripts.deleteMessage(byMessageId: "<test\"quoted@example.com>")
        XCTAssertTrue(script.contains("\\\""))
    }

    func testScriptEscapesBackslashes() {
        let script = MailActionScripts.compose(
            to: "test@example.com",
            subject: "Path: C:\\Users\\test",
            body: nil,
            cc: nil,
            bcc: nil,
            send: false
        )
        XCTAssertTrue(script.contains("\\\\"))
    }

    func testScriptEscapesNewlines() {
        let script = MailActionScripts.compose(
            to: "test@example.com",
            subject: "Test",
            body: "Line 1\nLine 2",
            cc: nil,
            bcc: nil,
            send: false
        )
        XCTAssertTrue(script.contains("\\n"))
    }

    // MARK: - AppleScriptService Instance Tests

    func testSharedInstance() {
        let instance1 = AppleScriptService.shared
        let instance2 = AppleScriptService.shared
        XCTAssertTrue(instance1 === instance2)
    }

    func testServiceCanBeInstantiated() {
        let service = AppleScriptService()
        XCTAssertNotNil(service)
    }

    // MARK: - Script Execution Tests (Non-Mail)

    func testExecuteSimpleScript() throws {
        let service = AppleScriptService()
        let result = try service.execute("return 2 + 2")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "4")
    }

    func testExecuteScriptWithStringOutput() throws {
        let service = AppleScriptService()
        let result = try service.execute("return \"hello world\"")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "hello world")
    }

    func testExecuteInvalidScriptThrows() {
        let service = AppleScriptService()
        XCTAssertThrowsError(try service.execute("this is not valid applescript syntax 123 abc")) { error in
            guard let appleScriptError = error as? AppleScriptError else {
                XCTFail("Expected AppleScriptError")
                return
            }
            if case .scriptCompilationFailed = appleScriptError {
                // Expected
            } else if case .executionFailed = appleScriptError {
                // Also acceptable - depends on AppleScript version
            } else {
                XCTFail("Expected scriptCompilationFailed or executionFailed, got \(appleScriptError)")
            }
        }
    }

    // MARK: - Integration Tests: Script Generation Validation

    func testDeleteMessageScriptContainsRequiredComponents() throws {
        // Generate script and verify it has required components (but don't execute against Mail.app)
        let script = MailActionScripts.deleteMessage(byMessageId: "<test123@example.com>")

        // Verify the script has required components (new mailbox-search pattern)
        XCTAssertTrue(script.contains("message id"))
        XCTAssertTrue(script.contains("delete"))
        XCTAssertTrue(script.contains("foundMsgs"), "Should use foundMsgs variable in new mailbox-search pattern")
        XCTAssertTrue(script.contains("searchMailboxes"), "Should search within specific mailboxes")
        XCTAssertTrue(script.contains("error") && script.contains("number -1728"), "Should include error handling for message not found")
    }

    func testMoveMessageScriptContainsRequiredComponents() throws {
        let script = MailActionScripts.moveMessage(byMessageId: "<move-test@example.com>", toMailbox: "INBOX")

        // Verify script structure (new mailbox-search pattern)
        XCTAssertTrue(script.contains("message id"))
        XCTAssertTrue(script.contains("move"))
        XCTAssertTrue(script.contains("mailbox \"INBOX\""))
        XCTAssertTrue(script.contains("foundMsgs"), "Should use foundMsgs variable in new mailbox-search pattern")
    }

    func testSetFlagScriptContainsRequiredComponents() throws {
        let flagScript = MailActionScripts.setFlag(byMessageId: "<flag-test@example.com>", flagged: true)
        let unflagScript = MailActionScripts.setFlag(byMessageId: "<flag-test@example.com>", flagged: false)

        // Verify script structure
        XCTAssertTrue(flagScript.contains("flagged status"))
        XCTAssertTrue(flagScript.contains("to true"))
        XCTAssertTrue(unflagScript.contains("to false"))
    }

    func testSetReadStatusScriptContainsRequiredComponents() throws {
        let readScript = MailActionScripts.setReadStatus(byMessageId: "<read-test@example.com>", read: true)
        let unreadScript = MailActionScripts.setReadStatus(byMessageId: "<read-test@example.com>", read: false)

        // Verify script structure
        XCTAssertTrue(readScript.contains("read status"))
        XCTAssertTrue(readScript.contains("to true"))
        XCTAssertTrue(unreadScript.contains("to false"))
    }

    func testCreateReplyScriptVariations() throws {
        // Test reply without send
        let draftReply = MailActionScripts.createReply(
            byMessageId: "<reply-test@example.com>",
            replyToAll: false,
            body: "Draft body",
            send: false
        )
        XCTAssertTrue(draftReply.contains("open theReply"))
        XCTAssertFalse(draftReply.contains("send theReply"))

        // Test reply all with send
        let sentReplyAll = MailActionScripts.createReply(
            byMessageId: "<reply-test@example.com>",
            replyToAll: true,
            body: "Sent body",
            send: true
        )
        XCTAssertTrue(sentReplyAll.contains("reply to all"))
        XCTAssertTrue(sentReplyAll.contains("send theReply"))

        // Test reply without body
        let replyNoBody = MailActionScripts.createReply(
            byMessageId: "<reply-test@example.com>",
            replyToAll: false,
            body: nil,
            send: false
        )
        XCTAssertFalse(replyNoBody.contains("set content"))
    }

    func testComposeScriptVariations() throws {
        // Test basic compose
        let basicCompose = MailActionScripts.compose(
            to: "test@example.com",
            subject: "Test Subject",
            body: nil,
            cc: nil,
            bcc: nil,
            send: false
        )
        XCTAssertTrue(basicCompose.contains("make new outgoing message"))
        XCTAssertTrue(basicCompose.contains("subject:\"Test Subject\""))
        XCTAssertFalse(basicCompose.contains("send theMessage"))

        // Test compose with all options
        let fullCompose = MailActionScripts.compose(
            to: "to@example.com",
            subject: "Full Test",
            body: "Test body content",
            cc: "cc@example.com",
            bcc: "bcc@example.com",
            send: true
        )
        XCTAssertTrue(fullCompose.contains("to recipient"))
        XCTAssertTrue(fullCompose.contains("cc recipient"))
        XCTAssertTrue(fullCompose.contains("bcc recipient"))
        XCTAssertTrue(fullCompose.contains("send theMessage"))
        XCTAssertTrue(fullCompose.contains("content:\"Test body content\""))
    }

    // MARK: - Integration Tests: Error Mapping

    func testAutomationPermissionErrorMapping() {
        // Simulate the error dictionary structure AppleScript returns for permission denial
        let error = AppleScriptError.automationPermissionDenied(guidance: "Permission required")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Automation permission denied"))
        XCTAssertNotNil(error.recoveryGuidance)
        XCTAssertTrue(error.recoveryGuidance!.contains("System Settings"))
    }

    func testMailAppNotRespondingErrorMapping() {
        let error = AppleScriptError.mailAppNotResponding(underlying: "Application isn't running")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not running"))
        XCTAssertNotNil(error.recoveryGuidance)
    }

    func testMessageNotFoundErrorMapping() {
        let error = AppleScriptError.messageNotFound(messageId: "<not-found@example.com>")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("<not-found@example.com>"))
        XCTAssertNotNil(error.recoveryGuidance)
        XCTAssertTrue(error.recoveryGuidance!.contains("sync"))
    }

    func testAmbiguousMatchErrorMapping() {
        let error = AppleScriptError.messageResolutionAmbiguous(count: 3, suggestion: "Use specific ID")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("3"))
        // The error message says "3 messages" with a suggestion
        XCTAssertTrue(error.errorDescription!.contains("messages"))
    }

    func testMailboxNotFoundErrorMapping() {
        let error = AppleScriptError.mailboxNotFound(mailbox: "NonExistent")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("NonExistent"))
    }

    // MARK: - Integration Tests: Special Character Handling

    func testScriptHandlesUnicodeCharacters() {
        let script = MailActionScripts.compose(
            to: "test@example.com",
            subject: "日本語 и русский 🎉",
            body: "Émoji 👍 and special chars: äöü",
            cc: nil,
            bcc: nil,
            send: false
        )

        // Verify Unicode is present (not corrupted)
        XCTAssertTrue(script.contains("日本語"))
        XCTAssertTrue(script.contains("русский"))
    }

    func testScriptHandlesLongBody() {
        let longBody = String(repeating: "a", count: 10000)
        let script = MailActionScripts.compose(
            to: "test@example.com",
            subject: "Long body test",
            body: longBody,
            cc: nil,
            bcc: nil,
            send: false
        )

        XCTAssertTrue(script.contains(longBody))
    }

    func testScriptHandlesEmptyStrings() {
        let script = MailActionScripts.compose(
            to: "test@example.com",
            subject: "",
            body: "",
            cc: nil,
            bcc: nil,
            send: false
        )

        // Script should still be valid with empty subject/body
        XCTAssertTrue(script.contains("make new outgoing message"))
    }

    // MARK: - Integration Tests: Script Output Verification

    func testDeleteScriptReturnsDeleted() {
        let script = MailActionScripts.deleteMessage(byMessageId: "<test@example.com>")
        XCTAssertTrue(script.contains("return \"deleted\""))
    }

    func testMoveScriptReturnsMoved() {
        let script = MailActionScripts.moveMessage(byMessageId: "<test@example.com>", toMailbox: "Archive")
        XCTAssertTrue(script.contains("return \"moved\""))
    }

    func testFlagScriptReturnsFlagged() {
        let flagScript = MailActionScripts.setFlag(byMessageId: "<test@example.com>", flagged: true)
        let unflagScript = MailActionScripts.setFlag(byMessageId: "<test@example.com>", flagged: false)

        XCTAssertTrue(flagScript.contains("return \"flagged\""))
        XCTAssertTrue(unflagScript.contains("return \"unflagged\""))
    }

    func testReadStatusScriptReturnsStatus() {
        let readScript = MailActionScripts.setReadStatus(byMessageId: "<test@example.com>", read: true)
        let unreadScript = MailActionScripts.setReadStatus(byMessageId: "<test@example.com>", read: false)

        XCTAssertTrue(readScript.contains("return \"read\""))
        XCTAssertTrue(unreadScript.contains("return \"unread\""))
    }

    func testReplyScriptReturnsMode() {
        let openedReply = MailActionScripts.createReply(
            byMessageId: "<test@example.com>",
            replyToAll: false,
            body: nil,
            send: false
        )
        let sentReply = MailActionScripts.createReply(
            byMessageId: "<test@example.com>",
            replyToAll: false,
            body: "body",
            send: true
        )

        XCTAssertTrue(openedReply.contains("return \"opened\""))
        XCTAssertTrue(sentReply.contains("return \"sent\""))
    }

    func testComposeScriptReturnsMode() {
        let openedCompose = MailActionScripts.compose(
            to: "test@example.com",
            subject: "Test",
            body: nil,
            cc: nil,
            bcc: nil,
            send: false
        )
        let sentCompose = MailActionScripts.compose(
            to: "test@example.com",
            subject: "Test",
            body: nil,
            cc: nil,
            bcc: nil,
            send: true
        )

        XCTAssertTrue(openedCompose.contains("return \"opened\""))
        XCTAssertTrue(sentCompose.contains("return \"sent\""))
    }

    // MARK: - Mail Launch Timeout Error Tests

    func testMailLaunchTimeoutErrorDescription() {
        let error = AppleScriptError.mailLaunchTimeout(seconds: 10)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("10"))
        XCTAssertTrue(error.errorDescription!.contains("failed to launch"))
    }

    func testMailLaunchTimeoutHasRecoveryGuidance() {
        let error = AppleScriptError.mailLaunchTimeout(seconds: 5)
        XCTAssertNotNil(error.recoveryGuidance)
        XCTAssertTrue(error.recoveryGuidance!.contains("manually") || error.recoveryGuidance!.contains("permissions"))
    }

    // MARK: - ensureMailRunning Configuration Tests

    func testDefaultMailLaunchTimeoutIsReasonable() {
        // Verify default timeout is 10 seconds as specified in acceptance criteria
        XCTAssertEqual(AppleScriptService.defaultMailLaunchTimeout, 10)
    }

    func testDefaultMailPollIntervalIsReasonable() {
        // Verify default poll interval is 100ms (100,000 microseconds)
        XCTAssertEqual(AppleScriptService.defaultMailPollIntervalMicroseconds, 100_000)
    }

    func testEnsureMailRunningAcceptsCustomTimeout() {
        // This test verifies the method signature accepts a timeout parameter
        // We can't actually test the full behavior without Mail.app, but we can
        // verify the API exists and compiles correctly
        let service = AppleScriptService()
        // The method should accept an optional timeout parameter
        // Note: This will actually try to launch Mail.app, so we just verify it compiles
        _ = type(of: service.ensureMailRunning(timeout:))
    }
}
