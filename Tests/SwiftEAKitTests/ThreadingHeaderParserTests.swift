import XCTest
@testable import SwiftEAKit

final class ThreadingHeaderParserTests: XCTestCase {
    var parser: ThreadingHeaderParser!

    override func setUp() {
        super.setUp()
        parser = ThreadingHeaderParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Message-ID Normalization

    func testNormalizeMessageIdWithAngleBrackets() {
        let result = parser.normalizeMessageId("<test@example.com>")
        XCTAssertEqual(result, "<test@example.com>")
    }

    func testNormalizeMessageIdWithoutAngleBrackets() {
        let result = parser.normalizeMessageId("test@example.com")
        XCTAssertEqual(result, "<test@example.com>")
    }

    func testNormalizeMessageIdWithWhitespace() {
        let result = parser.normalizeMessageId("  <test@example.com>  ")
        XCTAssertEqual(result, "<test@example.com>")
    }

    func testNormalizeMessageIdWithNewlines() {
        let result = parser.normalizeMessageId("\n<test@example.com>\n")
        XCTAssertEqual(result, "<test@example.com>")
    }

    func testNormalizeMessageIdNil() {
        let result = parser.normalizeMessageId(nil)
        XCTAssertNil(result)
    }

    func testNormalizeMessageIdEmpty() {
        let result = parser.normalizeMessageId("")
        XCTAssertNil(result)
    }

    func testNormalizeMessageIdWithMultipleIds() {
        // Some malformed headers have multiple message IDs
        let result = parser.normalizeMessageId("<first@example.com> <second@example.com>")
        XCTAssertEqual(result, "<first@example.com>")
    }

    func testNormalizeMessageIdWithInvalidFormat() {
        // No @ symbol, not a valid message ID
        let result = parser.normalizeMessageId("invalid")
        XCTAssertNil(result)
    }

    // MARK: - In-Reply-To Normalization

    func testNormalizeInReplyToWithAngleBrackets() {
        let result = parser.normalizeInReplyTo("<parent@example.com>")
        XCTAssertEqual(result, "<parent@example.com>")
    }

    func testNormalizeInReplyToWithWhitespace() {
        let result = parser.normalizeInReplyTo("  <parent@example.com>  ")
        XCTAssertEqual(result, "<parent@example.com>")
    }

    func testNormalizeInReplyToWithMultipleIds() {
        // In-Reply-To should have one ID, but some clients add multiple
        // Should take the first valid one
        let result = parser.normalizeInReplyTo("<first@example.com> <second@example.com>")
        XCTAssertEqual(result, "<first@example.com>")
    }

    func testNormalizeInReplyToNil() {
        let result = parser.normalizeInReplyTo(nil)
        XCTAssertNil(result)
    }

    func testNormalizeInReplyToEmpty() {
        let result = parser.normalizeInReplyTo("")
        XCTAssertNil(result)
    }

    // MARK: - References Parsing

    func testParseReferencesWithSingleId() {
        let result = parser.parseReferences("<ref1@example.com>")
        XCTAssertEqual(result, ["<ref1@example.com>"])
    }

    func testParseReferencesWithMultipleIds() {
        let result = parser.parseReferences("<ref1@example.com> <ref2@example.com> <ref3@example.com>")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], "<ref1@example.com>")
        XCTAssertEqual(result[1], "<ref2@example.com>")
        XCTAssertEqual(result[2], "<ref3@example.com>")
    }

    func testParseReferencesWithNewlines() {
        let refs = """
        <ref1@example.com>
        <ref2@example.com>
        <ref3@example.com>
        """
        let result = parser.parseReferences(refs)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains("<ref1@example.com>"))
        XCTAssertTrue(result.contains("<ref2@example.com>"))
        XCTAssertTrue(result.contains("<ref3@example.com>"))
    }

    func testParseReferencesWithMixedWhitespace() {
        let result = parser.parseReferences("  <ref1@example.com>  \n  <ref2@example.com>  ")
        XCTAssertEqual(result.count, 2)
    }

    func testParseReferencesNil() {
        let result = parser.parseReferences(nil)
        XCTAssertEqual(result, [])
    }

    func testParseReferencesEmpty() {
        let result = parser.parseReferences("")
        XCTAssertEqual(result, [])
    }

    func testParseReferencesPreservesOrder() {
        // References should preserve chronological order (oldest to newest)
        let result = parser.parseReferences("<oldest@ex.com> <middle@ex.com> <newest@ex.com>")
        XCTAssertEqual(result[0], "<oldest@ex.com>")
        XCTAssertEqual(result[1], "<middle@ex.com>")
        XCTAssertEqual(result[2], "<newest@ex.com>")
    }

    // MARK: - Combined Threading Headers

    func testParseThreadingHeadersComplete() {
        let headers = parser.parseThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: "<ref1@example.com> <ref2@example.com>"
        )

        XCTAssertEqual(headers.messageId, "<msg@example.com>")
        XCTAssertEqual(headers.inReplyTo, "<parent@example.com>")
        XCTAssertEqual(headers.references.count, 2)
    }

    func testParseThreadingHeadersPartial() {
        // Only message ID, no reply-to or references
        let headers = parser.parseThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: nil
        )

        XCTAssertEqual(headers.messageId, "<msg@example.com>")
        XCTAssertNil(headers.inReplyTo)
        XCTAssertEqual(headers.references, [])
    }

    func testParseThreadingHeadersAllNil() {
        let headers = parser.parseThreadingHeaders(
            messageId: nil,
            inReplyTo: nil,
            references: nil
        )

        XCTAssertNil(headers.messageId)
        XCTAssertNil(headers.inReplyTo)
        XCTAssertEqual(headers.references, [])
    }

    // MARK: - ThreadingHeaders Properties

    func testIsReplyWithInReplyTo() {
        let headers = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: []
        )
        XCTAssertTrue(headers.isReply)
    }

    func testIsReplyWithReferences() {
        let headers = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: ["<ref@example.com>"]
        )
        XCTAssertTrue(headers.isReply)
    }

    func testIsReplyWithBoth() {
        let headers = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<ref@example.com>"]
        )
        XCTAssertTrue(headers.isReply)
    }

    func testIsReplyFalseWhenNoParent() {
        let headers = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: []
        )
        XCTAssertFalse(headers.isReply)
    }

    func testHasThreadingHeaders() {
        let withMessageId = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: nil,
            references: []
        )
        XCTAssertTrue(withMessageId.hasThreadingHeaders)

        let withReply = ThreadingHeaderParser.ThreadingHeaders(
            messageId: nil,
            inReplyTo: "<parent@example.com>",
            references: []
        )
        XCTAssertTrue(withReply.hasThreadingHeaders)

        let withNothing = ThreadingHeaderParser.ThreadingHeaders(
            messageId: nil,
            inReplyTo: nil,
            references: []
        )
        XCTAssertFalse(withNothing.hasThreadingHeaders)
    }

    // MARK: - JSON Serialization

    func testEncodeReferencesToJson() {
        let refs = ["<ref1@example.com>", "<ref2@example.com>"]
        let json = parser.encodeReferencesToJson(refs)

        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("<ref1@example.com>"))
        XCTAssertTrue(json!.contains("<ref2@example.com>"))
    }

    func testEncodeEmptyReferencesToJson() {
        let json = parser.encodeReferencesToJson([])
        XCTAssertNil(json)
    }

    func testDecodeReferencesFromJson() {
        let json = "[\"<ref1@example.com>\",\"<ref2@example.com>\"]"
        let refs = parser.decodeReferencesFromJson(json)

        XCTAssertEqual(refs.count, 2)
        XCTAssertEqual(refs[0], "<ref1@example.com>")
        XCTAssertEqual(refs[1], "<ref2@example.com>")
    }

    func testDecodeReferencesFromNilJson() {
        let refs = parser.decodeReferencesFromJson(nil)
        XCTAssertEqual(refs, [])
    }

    func testDecodeReferencesFromEmptyJson() {
        let refs = parser.decodeReferencesFromJson("")
        XCTAssertEqual(refs, [])
    }

    func testDecodeReferencesFromInvalidJson() {
        let refs = parser.decodeReferencesFromJson("invalid json")
        XCTAssertEqual(refs, [])
    }

    func testJsonRoundTrip() {
        let original = ["<ref1@example.com>", "<ref2@example.com>", "<ref3@example.com>"]
        let json = parser.encodeReferencesToJson(original)
        let decoded = parser.decodeReferencesFromJson(json)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Malformed Header Handling

    func testHandlesMalformedMessageIdGracefully() {
        // Missing closing bracket - not a valid message ID format
        let result1 = parser.normalizeMessageId("<test@example.com")
        XCTAssertNil(result1)

        // No brackets but has @ - fallback adds brackets
        let result3 = parser.normalizeMessageId("test@example.com")
        XCTAssertEqual(result3, "<test@example.com>")

        // Already has proper brackets
        let result4 = parser.normalizeMessageId("<test@example.com>")
        XCTAssertEqual(result4, "<test@example.com>")
    }

    func testHandlesSpecialCharactersInMessageId() {
        // Message IDs can contain various special characters
        let result = parser.normalizeMessageId("<test+special.chars_123@example.com>")
        XCTAssertEqual(result, "<test+special.chars_123@example.com>")
    }

    func testHandlesLongThreadReferences() {
        // Long email threads can have many references
        var refs: [String] = []
        for i in 1...50 {
            refs.append("<ref\(i)@example.com>")
        }
        let refsString = refs.joined(separator: " ")

        let result = parser.parseReferences(refsString)
        XCTAssertEqual(result.count, 50)
    }

    // MARK: - ThreadingHeaders Equatable

    func testThreadingHeadersEquatable() {
        let headers1 = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<ref@example.com>"]
        )

        let headers2 = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<msg@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<ref@example.com>"]
        )

        let headers3 = ThreadingHeaderParser.ThreadingHeaders(
            messageId: "<different@example.com>",
            inReplyTo: "<parent@example.com>",
            references: ["<ref@example.com>"]
        )

        XCTAssertEqual(headers1, headers2)
        XCTAssertNotEqual(headers1, headers3)
    }
}
