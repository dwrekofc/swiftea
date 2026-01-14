import XCTest
@testable import SwiftEAKit

final class MessageResolverTests: XCTestCase {

    // MARK: - MessageResolutionError Tests

    func testNotFoundInDatabaseErrorDescription() {
        let error = MessageResolutionError.notFoundInDatabase(id: "test-123")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("test-123"))
        XCTAssertTrue(error.errorDescription!.contains("not found"))
        XCTAssertNotNil(error.recoverySuggestion)
        XCTAssertTrue(error.recoverySuggestion!.contains("sync"))
    }

    func testNoMessageIdAvailableErrorDescription() {
        let error = MessageResolutionError.noMessageIdAvailable(id: "test-456")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("test-456"))
        XCTAssertTrue(error.errorDescription!.contains("Message-ID"))
        XCTAssertNotNil(error.recoverySuggestion)
    }

    func testNotFoundInMailAppErrorDescription() {
        let error1 = MessageResolutionError.notFoundInMailApp(id: "test-789", messageId: "<test@example.com>")
        XCTAssertNotNil(error1.errorDescription)
        XCTAssertTrue(error1.errorDescription!.contains("test-789"))
        XCTAssertTrue(error1.errorDescription!.contains("<test@example.com>"))

        let error2 = MessageResolutionError.notFoundInMailApp(id: "test-abc", messageId: nil)
        XCTAssertNotNil(error2.errorDescription)
        XCTAssertTrue(error2.errorDescription!.contains("test-abc"))
        XCTAssertFalse(error2.errorDescription!.contains("Message-ID:"))
    }

    func testAmbiguousMatchErrorDescription() {
        let error = MessageResolutionError.ambiguousMatch(id: "test-multi", count: 5)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("test-multi"))
        XCTAssertTrue(error.errorDescription!.contains("5"))
        XCTAssertTrue(error.errorDescription!.contains("ambiguous"))
        XCTAssertNotNil(error.recoverySuggestion)
    }

    func testUnsupportedAccountTypeErrorDescription() {
        let error = MessageResolutionError.unsupportedAccountType(id: "test-ews", reason: "Exchange not supported")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("test-ews"))
        XCTAssertTrue(error.errorDescription!.contains("Exchange not supported"))
        XCTAssertNotNil(error.recoverySuggestion)
    }

    // MARK: - ResolvedMessage Tests

    func testResolvedMessageCreation() {
        let message = MailMessage(
            id: "mail-123",
            messageId: "<test@example.com>",
            subject: "Test Subject"
        )

        let resolved = ResolvedMessage(
            swiftEAId: "mail-123",
            messageId: "<test@example.com>",
            message: message,
            isConfident: true
        )

        XCTAssertEqual(resolved.swiftEAId, "mail-123")
        XCTAssertEqual(resolved.messageId, "<test@example.com>")
        XCTAssertEqual(resolved.message.subject, "Test Subject")
        XCTAssertTrue(resolved.isConfident)
    }

    func testResolvedMessageDefaultConfidence() {
        let message = MailMessage(id: "mail-456", subject: "Test")
        let resolved = ResolvedMessage(
            swiftEAId: "mail-456",
            messageId: "<msg@test.com>",
            message: message
        )
        XCTAssertTrue(resolved.isConfident)
    }

    // MARK: - MessageResolutionResult Tests

    func testResolutionResultSuccess() {
        let message = MailMessage(id: "mail-123", messageId: "<test@example.com>", subject: "Test")
        let resolved = ResolvedMessage(swiftEAId: "mail-123", messageId: "<test@example.com>", message: message)

        let result = MessageResolutionResult(resolved: resolved, action: "delete")

        XCTAssertTrue(result.succeeded)
        XCTAssertNotNil(result.resolved)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.action, "delete")
    }

    func testResolutionResultFailure() {
        let error = MessageResolutionError.notFoundInDatabase(id: "missing")
        let result = MessageResolutionResult(error: error, action: "archive")

        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.resolved)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.action, "archive")
    }

    func testResolutionResultFormatSuccess() {
        let message = MailMessage(id: "mail-123", messageId: "<test@example.com>", subject: "Test Subject")
        let resolved = ResolvedMessage(swiftEAId: "mail-123", messageId: "<test@example.com>", message: message)
        let result = MessageResolutionResult(resolved: resolved, action: "flag")

        let output = result.formatForOutput()

        XCTAssertTrue(output.contains("mail-123"))
        XCTAssertTrue(output.contains("<test@example.com>"))
        XCTAssertTrue(output.contains("Test Subject"))
        XCTAssertTrue(output.contains("flag"))
    }

    func testResolutionResultFormatFailure() {
        let error = MessageResolutionError.notFoundInDatabase(id: "missing-id")
        let result = MessageResolutionResult(error: error, action: "move")

        let output = result.formatForOutput()

        XCTAssertTrue(output.contains("Failed"))
        XCTAssertTrue(output.contains("move"))
        XCTAssertTrue(output.contains("Suggestion"))
    }

    // MARK: - Batch Resolution Tests

    func testBatchResolutionResultTypes() {
        // This tests the type system and dictionary handling
        let results: [String: Result<ResolvedMessage, MessageResolutionError>] = [
            "id1": .failure(.notFoundInDatabase(id: "id1")),
            "id2": .failure(.noMessageIdAvailable(id: "id2"))
        ]

        XCTAssertEqual(results.count, 2)

        if case .failure(let error) = results["id1"] {
            if case .notFoundInDatabase(let id) = error {
                XCTAssertEqual(id, "id1")
            } else {
                XCTFail("Expected notFoundInDatabase error")
            }
        } else {
            XCTFail("Expected failure result for id1")
        }
    }
}
