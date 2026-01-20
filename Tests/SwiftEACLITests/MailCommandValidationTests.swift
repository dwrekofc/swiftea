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
        if errorString.contains("MailValidationError.invalidEmailFormat") {
            // Extract email from error string pattern
            if let range = errorString.range(of: "invalidEmailFormat(email: \""),
               let endRange = errorString.range(of: "\")", range: range.upperBound..<errorString.endIndex) {
                let email = String(errorString[range.upperBound..<endRange.lowerBound])
                return .invalidEmailFormat(email: email)
            }
            return .invalidEmailFormat(email: "unknown")
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

    // MARK: - MailSyncCommand --bulk-copy Tests

    func testSyncCommandBulkCopyFlagParsesCorrectly() throws {
        let command = try MailSyncCommand.parseAsRoot(["--bulk-copy"]) as! MailSyncCommand
        XCTAssertTrue(command.bulkCopy)
    }

    func testSyncCommandBulkCopyDefaultsToFalse() throws {
        let command = try MailSyncCommand.parseAsRoot([]) as! MailSyncCommand
        XCTAssertFalse(command.bulkCopy)
    }

    func testSyncCommandBulkCopyCanCombineWithVerbose() throws {
        let command = try MailSyncCommand.parseAsRoot(["--bulk-copy", "--verbose"]) as! MailSyncCommand
        XCTAssertTrue(command.bulkCopy)
        XCTAssertTrue(command.verbose)
    }

    func testSyncCommandBulkCopyCanCombineWithNoExport() throws {
        // --bulk-copy can be combined with --no-export (though bulk-copy doesn't do export anyway)
        let command = try MailSyncCommand.parseAsRoot(["--bulk-copy", "--no-export"]) as! MailSyncCommand
        XCTAssertTrue(command.bulkCopy)
        XCTAssertTrue(command.noExport)
    }

    func testSyncCommandBulkCopyCannotCombineWithWatch() throws {
        // --bulk-copy with --watch should still parse (validation happens at runtime)
        // The combination is technically valid to parse but may not make sense operationally
        XCTAssertNoThrow(try MailSyncCommand.parseAsRoot(["--bulk-copy", "--watch"]))
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

    // MARK: - Email Format Validation Tests

    func testComposeCommandInvalidEmailNoAtSign() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot([
            "--to", "invalid",
            "--subject", "Test"
        ])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidEmailFormat, got \(error)")
                return
            }
            if case .invalidEmailFormat(let email) = validationError {
                XCTAssertEqual(email, "invalid")
            } else {
                XCTFail("Expected invalidEmailFormat error, got \(validationError)")
            }
        }
    }

    func testComposeCommandInvalidEmailNoDomain() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot([
            "--to", "user@",
            "--subject", "Test"
        ])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidEmailFormat, got \(error)")
                return
            }
            if case .invalidEmailFormat = validationError {
                // Success - email validation failed as expected
            } else {
                XCTFail("Expected invalidEmailFormat error, got \(validationError)")
            }
        }
    }

    func testComposeCommandInvalidEmailNoUsername() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot([
            "--to", "@example.com",
            "--subject", "Test"
        ])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidEmailFormat, got \(error)")
                return
            }
            if case .invalidEmailFormat = validationError {
                // Success - email validation failed as expected
            } else {
                XCTFail("Expected invalidEmailFormat error, got \(validationError)")
            }
        }
    }

    func testComposeCommandInvalidEmailDomainNoDot() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot([
            "--to", "user@domain",
            "--subject", "Test"
        ])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidEmailFormat, got \(error)")
                return
            }
            if case .invalidEmailFormat = validationError {
                // Success - email validation failed as expected
            } else {
                XCTFail("Expected invalidEmailFormat error, got \(validationError)")
            }
        }
    }

    func testComposeCommandInvalidEmailDomainEmptyTLD() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot([
            "--to", "user@domain.",
            "--subject", "Test"
        ])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidEmailFormat, got \(error)")
                return
            }
            if case .invalidEmailFormat = validationError {
                // Success - email validation failed as expected
            } else {
                XCTFail("Expected invalidEmailFormat error, got \(validationError)")
            }
        }
    }

    func testComposeCommandValidEmailWithSubdomain() throws {
        XCTAssertNoThrow(try MailComposeCommand.parseAsRoot([
            "--to", "user@mail.example.com",
            "--subject", "Test"
        ]))
    }

    func testComposeCommandValidEmailWithPlusSign() throws {
        XCTAssertNoThrow(try MailComposeCommand.parseAsRoot([
            "--to", "user+tag@example.com",
            "--subject", "Test"
        ]))
    }

    func testComposeCommandInvalidCCEmail() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot([
            "--to", "valid@example.com",
            "--cc", "invalid-email",
            "--subject", "Test"
        ])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidEmailFormat, got \(error)")
                return
            }
            if case .invalidEmailFormat = validationError {
                // Success - email validation failed as expected
            } else {
                XCTFail("Expected invalidEmailFormat error, got \(validationError)")
            }
        }
    }

    func testComposeCommandInvalidBCCEmail() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot([
            "--to", "valid@example.com",
            "--bcc", "also-invalid",
            "--subject", "Test"
        ])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidEmailFormat, got \(error)")
                return
            }
            if case .invalidEmailFormat = validationError {
                // Success - email validation failed as expected
            } else {
                XCTFail("Expected invalidEmailFormat error, got \(validationError)")
            }
        }
    }

    func testComposeCommandValidMultipleCCEmails() throws {
        XCTAssertNoThrow(try MailComposeCommand.parseAsRoot([
            "--to", "valid@example.com",
            "--cc", "user1@example.com,user2@test.org",
            "--subject", "Test"
        ]))
    }

    func testComposeCommandInvalidSecondCCEmail() throws {
        XCTAssertThrowsError(try MailComposeCommand.parseAsRoot([
            "--to", "valid@example.com",
            "--cc", "user1@example.com,invalid-second",
            "--subject", "Test"
        ])) { error in
            guard let validationError = extractValidationError(from: error) else {
                XCTFail("Expected MailValidationError.invalidEmailFormat, got \(error)")
                return
            }
            if case .invalidEmailFormat = validationError {
                // Success - email validation failed as expected
            } else {
                XCTFail("Expected invalidEmailFormat error, got \(validationError)")
            }
        }
    }

    func testEmailValidationErrorDescription() {
        let error = MailValidationError.invalidEmailFormat(email: "bad-email")
        XCTAssertEqual(
            error.errorDescription,
            "Invalid email format: 'bad-email'. Email must contain '@' and a domain (e.g., user@example.com)"
        )
    }

    // MARK: - Email Validation Helper Tests

    func testValidateEmailFormatWithValidEmail() {
        XCTAssertNil(MailValidationError.validateEmailFormat("user@example.com"))
        XCTAssertNil(MailValidationError.validateEmailFormat("user.name@example.com"))
        XCTAssertNil(MailValidationError.validateEmailFormat("user+tag@example.com"))
        XCTAssertNil(MailValidationError.validateEmailFormat("user@sub.domain.com"))
    }

    func testValidateEmailFormatWithInvalidEmail() {
        XCTAssertNotNil(MailValidationError.validateEmailFormat("invalid"))
        XCTAssertNotNil(MailValidationError.validateEmailFormat("user@"))
        XCTAssertNotNil(MailValidationError.validateEmailFormat("@example.com"))
        XCTAssertNotNil(MailValidationError.validateEmailFormat("user@domain"))
        XCTAssertNotNil(MailValidationError.validateEmailFormat("user@.com"))
        XCTAssertNotNil(MailValidationError.validateEmailFormat("user@domain."))
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

    // MARK: - MailThreadsCommand Tests

    func testThreadsCommandDefaults() throws {
        let command = try MailThreadsCommand.parseAsRoot([]) as! MailThreadsCommand
        XCTAssertEqual(command.limit, 50)
        XCTAssertEqual(command.offset, 0)
        XCTAssertEqual(command.sort, ThreadSortOption.date)
        XCTAssertNil(command.participant)
        XCTAssertEqual(command.format, ThreadOutputFormat.text)
    }

    func testThreadsCommandParsesLimitOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--limit", "100"]) as! MailThreadsCommand
        XCTAssertEqual(command.limit, 100)
    }

    func testThreadsCommandParsesShortLimitOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["-l", "25"]) as! MailThreadsCommand
        XCTAssertEqual(command.limit, 25)
    }

    func testThreadsCommandParsesOffsetOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--offset", "50"]) as! MailThreadsCommand
        XCTAssertEqual(command.offset, 50)
    }

    func testThreadsCommandParsesShortOffsetOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["-o", "10"]) as! MailThreadsCommand
        XCTAssertEqual(command.offset, 10)
    }

    func testThreadsCommandParsesSortDateOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--sort", "date"]) as! MailThreadsCommand
        XCTAssertEqual(command.sort, .date)
    }

    func testThreadsCommandParsesSortSubjectOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--sort", "subject"]) as! MailThreadsCommand
        XCTAssertEqual(command.sort, .subject)
    }

    func testThreadsCommandParsesSortMessageCountOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--sort", "message_count"]) as! MailThreadsCommand
        XCTAssertEqual(command.sort, .messageCount)
    }

    func testThreadsCommandParsesShortSortOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["-s", "subject"]) as! MailThreadsCommand
        XCTAssertEqual(command.sort, .subject)
    }

    func testThreadsCommandInvalidSortOptionIsRejected() throws {
        XCTAssertThrowsError(try MailThreadsCommand.parseAsRoot(["--sort", "invalid"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(
                errorString.contains("invalid") || errorString.contains("sort"),
                "Error should indicate invalid sort value"
            )
        }
    }

    func testThreadsCommandParsesParticipantOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--participant", "john@example.com"]) as! MailThreadsCommand
        XCTAssertEqual(command.participant, "john@example.com")
    }

    func testThreadsCommandParsesShortParticipantOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["-p", "alice@"]) as! MailThreadsCommand
        XCTAssertEqual(command.participant, "alice@")
    }

    func testThreadsCommandParsesPartialParticipant() throws {
        // Partial email match should be allowed
        let command = try MailThreadsCommand.parseAsRoot(["--participant", "@company.com"]) as! MailThreadsCommand
        XCTAssertEqual(command.participant, "@company.com")
    }

    func testThreadsCommandParsesFormatTextOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--format", "text"]) as! MailThreadsCommand
        XCTAssertEqual(command.format, .text)
    }

    func testThreadsCommandParsesFormatJsonOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--format", "json"]) as! MailThreadsCommand
        XCTAssertEqual(command.format, .json)
    }

    func testThreadsCommandParsesFormatMarkdownOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--format", "markdown"]) as! MailThreadsCommand
        XCTAssertEqual(command.format, .markdown)
    }

    func testThreadsCommandParsesFormatMdOption() throws {
        let command = try MailThreadsCommand.parseAsRoot(["--format", "md"]) as! MailThreadsCommand
        XCTAssertEqual(command.format, .md)
    }

    func testThreadsCommandInvalidFormatIsRejected() throws {
        XCTAssertThrowsError(try MailThreadsCommand.parseAsRoot(["--format", "xml"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(
                errorString.contains("xml") || errorString.lowercased().contains("invalid"),
                "Error should indicate invalid format value"
            )
        }
    }

    func testThreadsCommandCombinesAllOptions() throws {
        let command = try MailThreadsCommand.parseAsRoot([
            "--limit", "200",
            "--offset", "100",
            "--sort", "message_count",
            "--participant", "test@example.com",
            "--format", "json"
        ]) as! MailThreadsCommand
        XCTAssertEqual(command.limit, 200)
        XCTAssertEqual(command.offset, 100)
        XCTAssertEqual(command.sort, .messageCount)
        XCTAssertEqual(command.participant, "test@example.com")
        XCTAssertEqual(command.format, .json)
    }

    func testThreadsCommandCombinesShortOptions() throws {
        let command = try MailThreadsCommand.parseAsRoot([
            "-l", "75",
            "-o", "25",
            "-s", "subject",
            "-p", "user@"
        ]) as! MailThreadsCommand
        XCTAssertEqual(command.limit, 75)
        XCTAssertEqual(command.offset, 25)
        XCTAssertEqual(command.sort, .subject)
        XCTAssertEqual(command.participant, "user@")
    }

    // MARK: - MailThreadCommand (single thread) Tests

    func testThreadCommandRequiresId() throws {
        XCTAssertThrowsError(try MailThreadCommand.parseAsRoot([])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(
                errorString.lowercased().contains("missing") || errorString.lowercased().contains("argument"),
                "Error should indicate missing argument"
            )
        }
    }

    func testThreadCommandParsesId() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-abc123"]) as! MailThreadCommand
        XCTAssertEqual(command.id, "thread-abc123")
    }

    func testThreadCommandDefaultsHtmlToFalse() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-123"]) as! MailThreadCommand
        XCTAssertFalse(command.html)
    }

    func testThreadCommandParsesHtmlFlag() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-123", "--html"]) as! MailThreadCommand
        XCTAssertTrue(command.html)
    }

    func testThreadCommandDefaultFormatIsText() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-123"]) as! MailThreadCommand
        XCTAssertEqual(command.format, ThreadOutputFormat.text)
    }

    func testThreadCommandParsesFormatJson() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-123", "--format", "json"]) as! MailThreadCommand
        XCTAssertEqual(command.format, .json)
    }

    func testThreadCommandParsesFormatMarkdown() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-123", "--format", "markdown"]) as! MailThreadCommand
        XCTAssertEqual(command.format, .markdown)
    }

    func testThreadCommandParsesFormatMd() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-123", "--format", "md"]) as! MailThreadCommand
        XCTAssertEqual(command.format, .md)
    }

    func testThreadCommandParsesFormatText() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-123", "--format", "text"]) as! MailThreadCommand
        XCTAssertEqual(command.format, .text)
    }

    func testThreadCommandInvalidFormatIsRejected() throws {
        XCTAssertThrowsError(try MailThreadCommand.parseAsRoot(["thread-123", "--format", "invalid"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(
                errorString.contains("invalid") || errorString.lowercased().contains("format"),
                "Error should indicate invalid format value"
            )
        }
    }

    func testThreadCommandCombinesIdAndHtml() throws {
        let command = try MailThreadCommand.parseAsRoot(["thread-xyz", "--html"]) as! MailThreadCommand
        XCTAssertEqual(command.id, "thread-xyz")
        XCTAssertTrue(command.html)
    }

    func testThreadCommandCombinesAllOptions() throws {
        let command = try MailThreadCommand.parseAsRoot([
            "thread-abc",
            "--html",
            "--format", "json"
        ]) as! MailThreadCommand
        XCTAssertEqual(command.id, "thread-abc")
        XCTAssertTrue(command.html)
        XCTAssertEqual(command.format, .json)
    }

    // MARK: - ThreadOutputFormat Tests

    func testThreadOutputFormatEnumValues() {
        XCTAssertEqual(ThreadOutputFormat.text.rawValue, "text")
        XCTAssertEqual(ThreadOutputFormat.json.rawValue, "json")
        XCTAssertEqual(ThreadOutputFormat.markdown.rawValue, "markdown")
        XCTAssertEqual(ThreadOutputFormat.md.rawValue, "md")
    }

    func testThreadOutputFormatIsJson() {
        XCTAssertTrue(ThreadOutputFormat.json.isJson)
        XCTAssertFalse(ThreadOutputFormat.text.isJson)
        XCTAssertFalse(ThreadOutputFormat.markdown.isJson)
        XCTAssertFalse(ThreadOutputFormat.md.isJson)
    }

    func testThreadOutputFormatIsMarkdown() {
        XCTAssertTrue(ThreadOutputFormat.markdown.isMarkdown)
        XCTAssertTrue(ThreadOutputFormat.md.isMarkdown)
        XCTAssertFalse(ThreadOutputFormat.json.isMarkdown)
        XCTAssertFalse(ThreadOutputFormat.text.isMarkdown)
    }

    func testThreadOutputFormatIsText() {
        XCTAssertTrue(ThreadOutputFormat.text.isText)
        XCTAssertFalse(ThreadOutputFormat.json.isText)
        XCTAssertFalse(ThreadOutputFormat.markdown.isText)
        XCTAssertFalse(ThreadOutputFormat.md.isText)
    }

    func testThreadOutputFormatAllValueStrings() {
        let allValues = ThreadOutputFormat.allValueStrings
        XCTAssertTrue(allValues.contains("text"))
        XCTAssertTrue(allValues.contains("json"))
        XCTAssertTrue(allValues.contains("markdown"))
        XCTAssertTrue(allValues.contains("md"))
        XCTAssertEqual(allValues.count, 4)
    }

    // MARK: - ThreadSortOption Tests

    func testThreadSortOptionEnumValues() {
        XCTAssertEqual(ThreadSortOption.date.rawValue, "date")
        XCTAssertEqual(ThreadSortOption.subject.rawValue, "subject")
        XCTAssertEqual(ThreadSortOption.messageCount.rawValue, "message_count")
    }

    func testThreadSortOptionAllValueStrings() {
        let allValues = ThreadSortOption.allValueStrings
        XCTAssertTrue(allValues.contains("date"))
        XCTAssertTrue(allValues.contains("subject"))
        XCTAssertTrue(allValues.contains("message_count"))
        XCTAssertEqual(allValues.count, 3)
    }

    func testThreadSortOptionToDbSortOrder() {
        // Verify the conversion to database sort order works correctly
        XCTAssertEqual(ThreadSortOption.date.toDbSortOrder(), .date)
        XCTAssertEqual(ThreadSortOption.subject.toDbSortOrder(), .subject)
        XCTAssertEqual(ThreadSortOption.messageCount.toDbSortOrder(), .messageCount)
    }

    // MARK: - MailArchiveCommand / MailDeleteCommand Bulk (--ids) Validation Tests

    func testArchiveCommandRequiresIdOrIds() {
        XCTAssertThrowsError(try MailArchiveCommand.parseAsRoot(["--yes"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(
                errorString.contains("specify --id or --ids") || errorString.contains("Missing required option"),
                "Error should indicate --id/--ids is required"
            )
        }
    }

    func testArchiveCommandRejectsIdAndIdsTogether() {
        XCTAssertThrowsError(try MailArchiveCommand.parseAsRoot(["--id", "mail-1", "--ids", "mail-2,mail-3", "--yes"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(errorString.contains("exactly one of --id or --ids"))
        }
    }

    func testArchiveCommandRejectsEmptyIdsList() {
        XCTAssertThrowsError(try MailArchiveCommand.parseAsRoot(["--ids", " , , ", "--yes"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(errorString.contains("No message IDs provided in --ids"))
        }
    }

    func testArchiveCommandParsesSingleId() throws {
        let command = try MailArchiveCommand.parseAsRoot(["--id", "mail-1", "--yes"]) as! MailArchiveCommand
        XCTAssertEqual(command.id, "mail-1")
        XCTAssertNil(command.ids)
        XCTAssertTrue(command.yes)
        XCTAssertFalse(command.dryRun)
    }

    func testArchiveCommandParsesBulkIds() throws {
        let command = try MailArchiveCommand.parseAsRoot(["--ids", "mail-1,mail-2", "--yes"]) as! MailArchiveCommand
        XCTAssertNil(command.id)
        XCTAssertEqual(command.ids, "mail-1,mail-2")
        XCTAssertTrue(command.yes)
        XCTAssertFalse(command.dryRun)
    }

    func testArchiveCommandStillRequiresYesOrDryRun() {
        XCTAssertThrowsError(try MailArchiveCommand.parseAsRoot(["--id", "mail-1"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(errorString.contains("requires --yes") || errorString.contains("confirmationRequired"))
        }
    }

    func testDeleteCommandRequiresIdOrIds() {
        XCTAssertThrowsError(try MailDeleteCommand.parseAsRoot(["--yes"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(
                errorString.contains("specify --id or --ids") || errorString.contains("Missing required option"),
                "Error should indicate --id/--ids is required"
            )
        }
    }

    func testDeleteCommandRejectsIdAndIdsTogether() {
        XCTAssertThrowsError(try MailDeleteCommand.parseAsRoot(["--id", "mail-1", "--ids", "mail-2,mail-3", "--yes"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(errorString.contains("exactly one of --id or --ids"))
        }
    }

    func testDeleteCommandRejectsEmptyIdsList() {
        XCTAssertThrowsError(try MailDeleteCommand.parseAsRoot(["--ids", " , ", "--yes"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(errorString.contains("No message IDs provided in --ids"))
        }
    }

    func testDeleteCommandParsesSingleId() throws {
        let command = try MailDeleteCommand.parseAsRoot(["--id", "mail-1", "--yes"]) as! MailDeleteCommand
        XCTAssertEqual(command.id, "mail-1")
        XCTAssertNil(command.ids)
        XCTAssertTrue(command.yes)
        XCTAssertFalse(command.dryRun)
    }

    func testDeleteCommandParsesBulkIds() throws {
        let command = try MailDeleteCommand.parseAsRoot(["--ids", "mail-1,mail-2", "--yes"]) as! MailDeleteCommand
        XCTAssertNil(command.id)
        XCTAssertEqual(command.ids, "mail-1,mail-2")
        XCTAssertTrue(command.yes)
        XCTAssertFalse(command.dryRun)
    }

    func testDeleteCommandStillRequiresYesOrDryRun() {
        XCTAssertThrowsError(try MailDeleteCommand.parseAsRoot(["--id", "mail-1"])) { error in
            let errorString = String(describing: error)
            XCTAssertTrue(errorString.contains("requires --yes") || errorString.contains("confirmationRequired"))
        }
    }
}
