import XCTest
@testable import SwiftEAKit

final class StableIdGeneratorTests: XCTestCase {
    var generator: StableIdGenerator!

    override func setUp() {
        super.setUp()
        generator = StableIdGenerator()
    }

    override func tearDown() {
        generator = nil
        super.tearDown()
    }

    // MARK: - ID Generation with Message-ID

    func testGenerateIdWithMessageId() {
        let id = generator.generateId(
            messageId: "<test123@example.com>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )

        XCTAssertEqual(id.count, 32, "ID should be 32 characters")
        XCTAssertTrue(generator.isValidId(id), "Generated ID should be valid")
    }

    func testGenerateIdWithMessageIdIsStable() {
        let id1 = generator.generateId(
            messageId: "<stable@example.com>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )
        let id2 = generator.generateId(
            messageId: "<stable@example.com>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )

        XCTAssertEqual(id1, id2, "Same Message-ID should produce same ID")
    }

    func testGenerateIdNormalizesMessageId() {
        // With and without angle brackets should produce same ID
        let id1 = generator.generateId(
            messageId: "<test@example.com>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )
        let id2 = generator.generateId(
            messageId: "test@example.com",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )

        XCTAssertEqual(id1, id2, "Message-ID with/without brackets should match")
    }

    func testGenerateIdIsCaseInsensitiveForMessageId() {
        let id1 = generator.generateId(
            messageId: "<TEST@EXAMPLE.COM>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )
        let id2 = generator.generateId(
            messageId: "<test@example.com>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )

        XCTAssertEqual(id1, id2, "Message-ID comparison should be case-insensitive")
    }

    // MARK: - ID Generation with Header Fallback

    func testGenerateIdWithHeaderFallback() {
        let date = Date(timeIntervalSince1970: 1736177400) // Fixed timestamp
        let id = generator.generateId(
            messageId: nil,
            subject: "Test Subject",
            sender: "test@example.com",
            date: date,
            appleRowId: nil
        )

        XCTAssertEqual(id.count, 32, "ID should be 32 characters")
        XCTAssertTrue(generator.isValidId(id), "Generated ID should be valid")
    }

    func testGenerateIdWithHeaderFallbackIsStable() {
        let date = Date(timeIntervalSince1970: 1736177400)
        let id1 = generator.generateId(
            messageId: nil,
            subject: "Same Subject",
            sender: "same@example.com",
            date: date,
            appleRowId: 12345
        )
        let id2 = generator.generateId(
            messageId: nil,
            subject: "Same Subject",
            sender: "same@example.com",
            date: date,
            appleRowId: 12345
        )

        XCTAssertEqual(id1, id2, "Same headers should produce same ID")
    }

    func testGenerateIdWithDifferentSubjectsProducesDifferentIds() {
        let date = Date(timeIntervalSince1970: 1736177400)
        let id1 = generator.generateId(
            messageId: nil,
            subject: "Subject One",
            sender: "test@example.com",
            date: date,
            appleRowId: nil
        )
        let id2 = generator.generateId(
            messageId: nil,
            subject: "Subject Two",
            sender: "test@example.com",
            date: date,
            appleRowId: nil
        )

        XCTAssertNotEqual(id1, id2, "Different subjects should produce different IDs")
    }

    func testGenerateIdSenderIsCaseInsensitive() {
        let date = Date(timeIntervalSince1970: 1736177400)
        let id1 = generator.generateId(
            messageId: nil,
            subject: "Test",
            sender: "USER@EXAMPLE.COM",
            date: date,
            appleRowId: nil
        )
        let id2 = generator.generateId(
            messageId: nil,
            subject: "Test",
            sender: "user@example.com",
            date: date,
            appleRowId: nil
        )

        XCTAssertEqual(id1, id2, "Sender comparison should be case-insensitive")
    }

    // MARK: - ID Generation with Row ID Fallback

    func testGenerateIdWithRowIdOnly() {
        let id = generator.generateId(
            messageId: nil,
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: 99999
        )

        XCTAssertEqual(id.count, 32, "ID should be 32 characters")
        XCTAssertTrue(generator.isValidId(id), "Generated ID should be valid")
    }

    func testGenerateIdWithRowIdOnlyIsStable() {
        let id1 = generator.generateId(
            messageId: nil,
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: 12345
        )
        let id2 = generator.generateId(
            messageId: nil,
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: 12345
        )

        XCTAssertEqual(id1, id2, "Same rowid should produce same ID")
    }

    func testGenerateIdDifferentRowIdsProduceDifferentIds() {
        let id1 = generator.generateId(
            messageId: nil,
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: 11111
        )
        let id2 = generator.generateId(
            messageId: nil,
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: 22222
        )

        XCTAssertNotEqual(id1, id2, "Different rowids should produce different IDs")
    }

    // MARK: - ID Validation

    func testIsValidIdWithValidId() {
        let validId = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
        XCTAssertTrue(generator.isValidId(validId), "32 hex chars should be valid")
    }

    func testIsValidIdWithTooShort() {
        let shortId = "abc123"
        XCTAssertFalse(generator.isValidId(shortId), "Short ID should be invalid")
    }

    func testIsValidIdWithTooLong() {
        let longId = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"
        XCTAssertFalse(generator.isValidId(longId), "Long ID should be invalid")
    }

    func testIsValidIdWithUppercase() {
        let upperId = "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4"
        XCTAssertFalse(generator.isValidId(upperId), "Uppercase should be invalid")
    }

    func testIsValidIdWithNonHex() {
        let nonHexId = "g1h2i3j4k5l6g1h2i3j4k5l6g1h2i3j4"
        XCTAssertFalse(generator.isValidId(nonHexId), "Non-hex chars should be invalid")
    }

    func testIsValidIdWithEmptyString() {
        XCTAssertFalse(generator.isValidId(""), "Empty string should be invalid")
    }

    // MARK: - Edge Cases

    func testGenerateIdPrefersMessageIdOverHeaders() {
        let date = Date(timeIntervalSince1970: 1736177400)
        let idWithMsgId = generator.generateId(
            messageId: "<unique@example.com>",
            subject: "Subject",
            sender: "sender@example.com",
            date: date,
            appleRowId: 12345
        )
        let idMsgIdOnly = generator.generateId(
            messageId: "<unique@example.com>",
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )

        XCTAssertEqual(idWithMsgId, idMsgIdOnly, "Message-ID should take precedence")
    }

    func testGenerateIdWithEmptyMessageIdFallsBack() {
        let date = Date(timeIntervalSince1970: 1736177400)
        let idWithEmpty = generator.generateId(
            messageId: "",
            subject: "Subject",
            sender: "sender@example.com",
            date: date,
            appleRowId: nil
        )
        let idWithoutMsgId = generator.generateId(
            messageId: nil,
            subject: "Subject",
            sender: "sender@example.com",
            date: date,
            appleRowId: nil
        )

        XCTAssertEqual(idWithEmpty, idWithoutMsgId, "Empty Message-ID should fallback to headers")
    }

    func testGenerateIdWithWhitespaceOnlyMessageIdFallsBack() {
        let date = Date(timeIntervalSince1970: 1736177400)
        let id = generator.generateId(
            messageId: "   ",
            subject: "Subject",
            sender: "sender@example.com",
            date: date,
            appleRowId: nil
        )

        XCTAssertEqual(id.count, 32, "Should generate valid ID from headers")
        XCTAssertTrue(generator.isValidId(id), "Generated ID should be valid")
    }

    func testGenerateIdWithSpecialCharactersInSubject() {
        let id = generator.generateId(
            messageId: nil,
            subject: "Test with 日本語 and émojis 🎉",
            sender: "test@example.com",
            date: Date(),
            appleRowId: nil
        )

        XCTAssertEqual(id.count, 32, "Should handle special characters")
        XCTAssertTrue(generator.isValidId(id), "Generated ID should be valid")
    }

    func testGenerateIdWithNoDataFallsBackToUUID() {
        let id = generator.generateId(
            messageId: nil,
            subject: nil,
            sender: nil,
            date: nil,
            appleRowId: nil
        )

        // UUID fallback produces 32-char hex string (UUID without dashes)
        XCTAssertEqual(id.count, 32, "UUID fallback should be 32 chars")
    }

    func testGenerateIdWithMinimalComponents() {
        // Only one header component - should use rowid fallback path
        let idSubjectOnly = generator.generateId(
            messageId: nil,
            subject: "Only Subject",
            sender: nil,
            date: nil,
            appleRowId: 12345
        )

        XCTAssertEqual(idSubjectOnly.count, 32, "Should handle minimal components")
        XCTAssertTrue(generator.isValidId(idSubjectOnly), "Generated ID should be valid")
    }
}
