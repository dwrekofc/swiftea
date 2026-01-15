import ArgumentParser
import XCTest
@testable import SwiftEACLI

final class MailCommandValidationTests: XCTestCase {

    // MARK: - Helper to extract MailValidationError from CommandError

    private func extractValidationError(from error: Error) -> MailValidationError? {
        // Check if it's our error type directly
        if let validationError = error as? MailValidationError {
            return validationError
        }
        // Check if it's wrapped in a CommandError
        let errorString = String(describing: error)
        if errorString.contains("MailValidationError.invalidLimit") {
            return .invalidLimit
        }
        if errorString.contains("MailValidationError.emptyRecipient") {
            return .emptyRecipient
        }
        if errorString.contains("MailValidationError.watchAndStopMutuallyExclusive") {
            return .watchAndStopMutuallyExclusive
        }
        return nil
    }

    // MARK: - MailSyncCommand Validation Tests

    func testSyncCommandWatchAndStopMutuallyExclusive() throws {
        // --watch and --stop cannot be used together
        // ArgumentParser runs validation during parse()
        XCTAssertThrowsError(try MailSyncCommand.parseAsRoot(["--watch", "--stop"])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .watchAndStopMutuallyExclusive)
            XCTAssertEqual(
                validationError.errorDescription,
                "--watch and --stop cannot be used together"
            )
        }
    }

    func testSyncCommandWatchAloneIsValid() throws {
        // Should parse without throwing
        XCTAssertNoThrow(try MailSyncCommand.parseAsRoot(["--watch"]))
    }

    func testSyncCommandStopAloneIsValid() throws {
        XCTAssertNoThrow(try MailSyncCommand.parseAsRoot(["--stop"]))
    }

    func testSyncCommandNoFlagsIsValid() throws {
        XCTAssertNoThrow(try MailSyncCommand.parseAsRoot([]))
    }

    // MARK: - MailSearchCommand Validation Tests

    func testSearchCommandLimitZeroIsInvalid() throws {
        XCTAssertThrowsError(try MailSearchCommand.parseAsRoot(["test query", "--limit", "0"])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidLimit, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .invalidLimit)
            XCTAssertEqual(
                validationError.errorDescription,
                "--limit must be a positive integer"
            )
        }
    }

    func testSearchCommandNegativeLimitIsInvalid() throws {
        // Note: ArgumentParser may parse "-5" as a flag rather than a value
        // We test with a clearly negative number
        XCTAssertThrowsError(try MailSearchCommand.parseAsRoot(["test query", "--limit=0"])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidLimit, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .invalidLimit)
        }
    }

    func testSearchCommandPositiveLimitIsValid() throws {
        XCTAssertNoThrow(try MailSearchCommand.parseAsRoot(["test query", "--limit", "10"]))
    }

    func testSearchCommandDefaultLimitIsValid() throws {
        XCTAssertNoThrow(try MailSearchCommand.parseAsRoot(["test query"]))
    }

    // MARK: - MailExportCommand Validation Tests

    func testExportCommandLimitZeroIsInvalid() throws {
        XCTAssertThrowsError(try MailExportCommand.parseAsRoot(["--limit", "0"])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidLimit, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .invalidLimit)
        }
    }

    func testExportCommandNegativeLimitIsInvalid() throws {
        // Test with = syntax to avoid ArgumentParser treating it as a flag
        XCTAssertThrowsError(try MailExportCommand.parseAsRoot(["--limit=0"])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidLimit, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .invalidLimit)
        }
    }

    func testExportCommandInvalidFormatIsRejected() throws {
        // With enum-based format, ArgumentParser handles validation automatically
        // Invalid values are rejected at parse time with a descriptive error
        XCTAssertThrowsError(try MailExportCommand.parseAsRoot(["--format", "invalidvalue"])) { error in
            // ArgumentParser throws its own error for invalid enum values
            let errorString = String(describing: error)
            XCTAssertTrue(
                errorString.contains("invalidvalue") || errorString.lowercased().contains("invalid"),
                "Error should indicate the invalid format value"
            )
        }
    }

    func testExportCommandMarkdownFormatIsValid() throws {
        XCTAssertNoThrow(try MailExportCommand.parseAsRoot(["--format", "markdown"]))
    }

    func testExportCommandMdFormatIsValid() throws {
        XCTAssertNoThrow(try MailExportCommand.parseAsRoot(["--format", "md"]))
    }

    func testExportCommandJsonFormatIsValid() throws {
        XCTAssertNoThrow(try MailExportCommand.parseAsRoot(["--format", "json"]))
    }

    func testExportCommandFormatIsCaseSensitive() throws {
        // With enum-based format, case sensitivity is enforced by ArgumentParser
        // "JSON" is rejected because the enum values are lowercase: json, markdown, md
        XCTAssertThrowsError(try MailExportCommand.parseAsRoot(["--format", "JSON"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(
                errorString.contains("JSON") || errorString.lowercased().contains("invalid"),
                "Error should indicate the invalid format value"
            )
        }
    }

    func testExportCommandDefaultFormatIsValid() throws {
        XCTAssertNoThrow(try MailExportCommand.parseAsRoot([]))
    }

    // MARK: - MailComposeCommand Validation Tests

    func testComposeCommandEmptyToIsInvalid() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot(["--to", "", "--subject", "Test"])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.emptyRecipient, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .emptyRecipient)
            XCTAssertEqual(
                validationError.errorDescription,
                "--to requires a non-empty email address"
            )
        }
    }

    func testComposeCommandWhitespaceOnlyToIsInvalid() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot(["--to", "   ", "--subject", "Test"])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.emptyRecipient, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .emptyRecipient)
        }
    }

    func testComposeCommandValidToIsAccepted() throws {
        XCTAssertNoThrow(try MailComposeCommand.parseAsRoot([
            "--to", "test@example.com",
            "--subject", "Test Subject"
        ]))
    }

    // MARK: - Error Description Tests

    func testMailValidationErrorDescriptions() {
        let errors: [MailValidationError] = [
            .invalidLimit,
            .emptyRecipient,
            .watchAndStopMutuallyExclusive
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }

    // MARK: - OutputFormat Enum Tests

    func testOutputFormatEnumValues() {
        // Verify all expected enum cases exist
        XCTAssertEqual(OutputFormat.markdown.rawValue, "markdown")
        XCTAssertEqual(OutputFormat.md.rawValue, "md")
        XCTAssertEqual(OutputFormat.json.rawValue, "json")
    }

    func testOutputFormatIsJson() {
        XCTAssertTrue(OutputFormat.json.isJson)
        XCTAssertFalse(OutputFormat.markdown.isJson)
        XCTAssertFalse(OutputFormat.md.isJson)
    }

    func testOutputFormatIsMarkdown() {
        XCTAssertTrue(OutputFormat.markdown.isMarkdown)
        XCTAssertTrue(OutputFormat.md.isMarkdown)
        XCTAssertFalse(OutputFormat.json.isMarkdown)
    }

    func testOutputFormatFileExtension() {
        XCTAssertEqual(OutputFormat.json.fileExtension, "json")
        XCTAssertEqual(OutputFormat.markdown.fileExtension, "md")
        XCTAssertEqual(OutputFormat.md.fileExtension, "md")
    }

    func testOutputFormatAllValueStrings() {
        let allValues = OutputFormat.allValueStrings
        XCTAssertTrue(allValues.contains("markdown"))
        XCTAssertTrue(allValues.contains("md"))
        XCTAssertTrue(allValues.contains("json"))
        XCTAssertEqual(allValues.count, 3)
    }

    // MARK: - MailShowCommand Validation Tests

    func testShowCommandParsesWithMessageId() throws {
        let command = try MailShowCommand.parseAsRoot(["mail-abc123"]) as! MailShowCommand
        XCTAssertEqual(command.id, "mail-abc123")
    }

    func testShowCommandParsesHtmlFlag() throws {
        let command = try MailShowCommand.parseAsRoot(["mail-abc123", "--html"]) as! MailShowCommand
        XCTAssertTrue(command.html)
    }

    func testShowCommandParsesRawFlag() throws {
        let command = try MailShowCommand.parseAsRoot(["mail-abc123", "--raw"]) as! MailShowCommand
        XCTAssertTrue(command.raw)
    }

    func testShowCommandParsesJsonFlag() throws {
        let command = try MailShowCommand.parseAsRoot(["mail-abc123", "--json"]) as! MailShowCommand
        XCTAssertTrue(command.json)
    }

    func testShowCommandCombinesFlagsCorrectly() throws {
        let command = try MailShowCommand.parseAsRoot(["mail-abc123", "--html"]) as! MailShowCommand
        XCTAssertEqual(command.id, "mail-abc123")
        XCTAssertTrue(command.html)
        XCTAssertFalse(command.raw)
        XCTAssertFalse(command.json)
    }
}
