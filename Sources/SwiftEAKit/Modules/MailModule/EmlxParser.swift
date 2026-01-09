// EmlxParser - Parse Apple Mail .emlx files

import Foundation

/// Errors that can occur during .emlx parsing
public enum EmlxParseError: Error, LocalizedError {
    case fileNotFound(path: String)
    case invalidFormat
    case readFailed(underlying: Error)
    case headerParseFailed

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "EMLX file not found: \(path)"
        case .invalidFormat:
            return "Invalid EMLX file format"
        case .readFailed(let error):
            return "Failed to read EMLX file: \(error.localizedDescription)"
        case .headerParseFailed:
            return "Failed to parse email headers"
        }
    }
}

/// Parsed content from an .emlx file
public struct ParsedEmlx: @unchecked Sendable {
    /// Raw headers dictionary
    public let headers: [String: String]
    /// Subject line
    public let subject: String?
    /// From address (parsed)
    public let from: EmailAddress?
    /// To addresses
    public let to: [EmailAddress]
    /// CC addresses
    public let cc: [EmailAddress]
    /// BCC addresses (rarely in stored mail)
    public let bcc: [EmailAddress]
    /// RFC822 Message-ID
    public let messageId: String?
    /// In-Reply-To header
    public let inReplyTo: String?
    /// References header
    public let references: [String]
    /// Date header
    public let date: Date?
    /// Plain text body (preferred)
    public let bodyText: String?
    /// HTML body
    public let bodyHtml: String?
    /// Attachment metadata
    public let attachments: [AttachmentInfo]
    /// Apple Mail plist metadata (from end of file)
    public let applePlist: [String: Any]?

    public init(
        headers: [String: String],
        subject: String?,
        from: EmailAddress?,
        to: [EmailAddress],
        cc: [EmailAddress],
        bcc: [EmailAddress],
        messageId: String?,
        inReplyTo: String?,
        references: [String],
        date: Date?,
        bodyText: String?,
        bodyHtml: String?,
        attachments: [AttachmentInfo],
        applePlist: [String: Any]?
    ) {
        self.headers = headers
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.messageId = messageId
        self.inReplyTo = inReplyTo
        self.references = references
        self.date = date
        self.bodyText = bodyText
        self.bodyHtml = bodyHtml
        self.attachments = attachments
        self.applePlist = applePlist
    }
}

/// Represents a parsed email address
public struct EmailAddress: Sendable {
    public let name: String?
    public let email: String

    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }

    public var displayString: String {
        if let name = name, !name.isEmpty {
            return "\(name) <\(email)>"
        }
        return email
    }
}

/// Attachment metadata parsed from an email
public struct AttachmentInfo: Sendable {
    public let filename: String
    public let mimeType: String?
    public let size: Int?
    public let contentId: String?
    public let isInline: Bool

    public init(filename: String, mimeType: String?, size: Int?, contentId: String?, isInline: Bool) {
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.contentId = contentId
        self.isInline = isInline
    }
}

/// Parses Apple Mail .emlx files
public final class EmlxParser: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Parse an .emlx file at the given path
    public func parse(path: String) throws -> ParsedEmlx {
        guard fileManager.fileExists(atPath: path) else {
            throw EmlxParseError.fileNotFound(path: path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw EmlxParseError.readFailed(underlying: error)
        }

        return try parse(data: data)
    }

    /// Parse .emlx data
    public func parse(data: Data) throws -> ParsedEmlx {
        // .emlx format:
        // Line 1: byte count (ASCII digits followed by newline)
        // Lines 2+: RFC822 message (headers + body)
        // End: Apple plist XML metadata

        guard let content = String(data: data, encoding: .utf8) else {
            // Try Latin1 as fallback
            guard let latin1Content = String(data: data, encoding: .isoLatin1) else {
                throw EmlxParseError.invalidFormat
            }
            return try parseContent(latin1Content, data: data)
        }

        return try parseContent(content, data: data)
    }

    private func parseContent(_ content: String, data: Data) throws -> ParsedEmlx {
        let lines = content.components(separatedBy: "\n")

        guard !lines.isEmpty else {
            throw EmlxParseError.invalidFormat
        }

        // First line should be byte count
        guard let byteCount = Int(lines[0].trimmingCharacters(in: .whitespaces)) else {
            throw EmlxParseError.invalidFormat
        }

        // Find the start of the RFC822 message (after byte count line)
        let byteCountLineLength = lines[0].utf8.count + 1 // +1 for newline
        let messageStart = byteCountLineLength
        let messageEnd = min(messageStart + byteCount, data.count)

        guard messageEnd > messageStart else {
            throw EmlxParseError.invalidFormat
        }

        // Extract message portion
        let messageData = data[messageStart..<messageEnd]
        guard let messageContent = String(data: messageData, encoding: .utf8)
            ?? String(data: messageData, encoding: .isoLatin1) else {
            throw EmlxParseError.invalidFormat
        }

        // Parse headers and body
        let (headers, body) = parseRfc822(messageContent)

        // Extract specific headers
        let subject = decodeHeader(headers["subject"])
        let from = parseAddressHeader(headers["from"])?.first
        let to = parseAddressHeader(headers["to"]) ?? []
        let cc = parseAddressHeader(headers["cc"]) ?? []
        let bcc = parseAddressHeader(headers["bcc"]) ?? []
        let messageId = headers["message-id"]
        let inReplyTo = headers["in-reply-to"]
        let references = parseReferences(headers["references"])
        let date = parseDateHeader(headers["date"])

        // Parse body - extract text and HTML parts
        let (bodyText, bodyHtml, attachments) = parseBody(body, contentType: headers["content-type"])

        // Try to extract Apple plist from end of file
        var applePlist: [String: Any]? = nil
        if messageEnd < data.count {
            let plistData = data[messageEnd...]
            if let plist = try? PropertyListSerialization.propertyList(
                from: Data(plistData),
                options: [],
                format: nil
            ) as? [String: Any] {
                applePlist = plist
            }
        }

        return ParsedEmlx(
            headers: headers,
            subject: subject,
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: references,
            date: date,
            bodyText: bodyText,
            bodyHtml: bodyHtml,
            attachments: attachments,
            applePlist: applePlist
        )
    }

    /// Parse RFC822 message into headers dictionary and body
    private func parseRfc822(_ message: String) -> ([String: String], String) {
        var headers: [String: String] = [:]
        var currentHeader: String? = nil
        var currentValue: String = ""
        var bodyStartIndex: String.Index? = nil

        let lines = message.components(separatedBy: "\r\n").isEmpty
            ? message.components(separatedBy: "\n")
            : message.components(separatedBy: "\r\n")

        var index = 0
        for line in lines {
            // Empty line marks end of headers
            if line.isEmpty {
                if let header = currentHeader {
                    headers[header.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
                }
                // Body starts after this empty line
                let headerSection = lines[0...index].joined(separator: "\n")
                let startOffset = headerSection.count + 1 // +1 for the empty line
                if startOffset < message.count {
                    bodyStartIndex = message.index(message.startIndex, offsetBy: min(startOffset, message.count - 1))
                }
                break
            }

            // Continuation line (starts with whitespace)
            if line.first?.isWhitespace == true {
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colonIndex = line.firstIndex(of: ":") {
                // Save previous header
                if let header = currentHeader {
                    headers[header.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
                }
                // Start new header
                currentHeader = String(line[..<colonIndex])
                let valueStart = line.index(after: colonIndex)
                currentValue = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            }
            index += 1
        }

        // Extract body
        let body: String
        if let startIndex = bodyStartIndex {
            body = String(message[startIndex...])
        } else {
            body = ""
        }

        return (headers, body)
    }

    /// Decode RFC2047 encoded header values
    private func decodeHeader(_ value: String?) -> String? {
        guard let value = value else { return nil }

        // Basic RFC2047 decoding for =?charset?encoding?text?=
        var result = value
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range)

            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let charsetRange = Range(match.range(at: 1), in: result),
                      let encodingRange = Range(match.range(at: 2), in: result),
                      let textRange = Range(match.range(at: 3), in: result) else {
                    continue
                }

                let charset = String(result[charsetRange])
                let encoding = String(result[encodingRange]).uppercased()
                let encodedText = String(result[textRange])

                var decoded: String?

                if encoding == "B" {
                    // Base64
                    if let data = Data(base64Encoded: encodedText) {
                        decoded = decodeWithCharset(data, charset: charset)
                    }
                } else if encoding == "Q" {
                    // Quoted-printable
                    decoded = decodeQuotedPrintable(encodedText, charset: charset)
                }

                if let decoded = decoded {
                    result.replaceSubrange(fullRange, with: decoded)
                }
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private func decodeWithCharset(_ data: Data, charset: String) -> String? {
        let encoding: String.Encoding
        switch charset.lowercased() {
        case "utf-8", "utf8":
            encoding = .utf8
        case "iso-8859-1", "latin1":
            encoding = .isoLatin1
        case "iso-8859-15":
            encoding = .isoLatin1  // Close enough
        case "windows-1252", "cp1252":
            encoding = .windowsCP1252
        default:
            encoding = .utf8
        }
        return String(data: data, encoding: encoding)
    }

    private func decodeQuotedPrintable(_ text: String, charset: String) -> String? {
        var result = text.replacingOccurrences(of: "_", with: " ")
        var data = Data()

        var index = result.startIndex
        while index < result.endIndex {
            if result[index] == "=" {
                let nextIndex = result.index(after: index)
                if nextIndex < result.endIndex {
                    let endIndex = result.index(nextIndex, offsetBy: 2, limitedBy: result.endIndex) ?? result.endIndex
                    let hex = String(result[nextIndex..<endIndex])
                    if let byte = UInt8(hex, radix: 16) {
                        data.append(byte)
                        index = endIndex
                        continue
                    }
                }
            }
            if let byte = String(result[index]).data(using: .utf8)?.first {
                data.append(byte)
            }
            index = result.index(after: index)
        }

        return decodeWithCharset(data, charset: charset)
    }

    /// Parse address header (From, To, CC, etc.)
    private func parseAddressHeader(_ value: String?) -> [EmailAddress]? {
        guard let value = value, !value.isEmpty else { return nil }

        var addresses: [EmailAddress] = []

        // Split on commas (but not inside quotes)
        let parts = splitAddresses(value)

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let address = parseAddress(trimmed) {
                addresses.append(address)
            }
        }

        return addresses.isEmpty ? nil : addresses
    }

    private func splitAddresses(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var depth = 0

        for char in value {
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if char == "<" {
                depth += 1
                current.append(char)
            } else if char == ">" {
                depth = max(0, depth - 1)
                current.append(char)
            } else if char == "," && !inQuotes && depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }

    private func parseAddress(_ value: String) -> EmailAddress? {
        // Format: "Name" <email@example.com> or Name <email@example.com> or email@example.com
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Try to extract <email> part
        if let startAngle = trimmed.lastIndex(of: "<"),
           let endAngle = trimmed.lastIndex(of: ">"),
           startAngle < endAngle {
            let email = String(trimmed[trimmed.index(after: startAngle)..<endAngle])
                .trimmingCharacters(in: .whitespaces)
            var name = String(trimmed[..<startAngle])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            // Decode name if needed
            if let decoded = decodeHeader(name) {
                name = decoded
            }

            return EmailAddress(name: name.isEmpty ? nil : name, email: email)
        }

        // Plain email address
        if trimmed.contains("@") {
            return EmailAddress(name: nil, email: trimmed)
        }

        return nil
    }

    /// Parse References header into array of message IDs
    private func parseReferences(_ value: String?) -> [String] {
        guard let value = value else { return [] }

        // References are space or newline separated message IDs
        let pattern = #"<[^>]+>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)

        return matches.compactMap { match in
            guard let range = Range(match.range, in: value) else { return nil }
            return String(value[range])
        }
    }

    /// Parse date header
    private func parseDateHeader(_ value: String?) -> Date? {
        guard let value = value else { return nil }

        // Try common date formats
        let formatters: [DateFormatter] = [
            createFormatter("EEE, dd MMM yyyy HH:mm:ss Z"),
            createFormatter("EEE, dd MMM yyyy HH:mm:ss z"),
            createFormatter("dd MMM yyyy HH:mm:ss Z"),
            createFormatter("yyyy-MM-dd'T'HH:mm:ssZ"),
            createFormatter("EEE MMM dd HH:mm:ss yyyy")
        ]

        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        // Try ISO8601
        let iso = ISO8601DateFormatter()
        return iso.date(from: value)
    }

    private func createFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    /// Parse email body - extract text, HTML, and attachments
    private func parseBody(_ body: String, contentType: String?) -> (String?, String?, [AttachmentInfo]) {
        var plainText: String? = nil
        var htmlText: String? = nil
        var attachments: [AttachmentInfo] = []

        // Check if multipart
        if let contentType = contentType,
           contentType.lowercased().contains("multipart/") {
            // Extract boundary
            if let boundary = extractBoundary(from: contentType) {
                let parts = body.components(separatedBy: "--\(boundary)")

                for part in parts {
                    if part.hasPrefix("--") || part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continue
                    }

                    let (partHeaders, partBody) = parseRfc822(part)
                    let partContentType = partHeaders["content-type"]?.lowercased() ?? ""

                    if partContentType.contains("text/plain") {
                        plainText = decodeBodyPart(partBody, headers: partHeaders)
                    } else if partContentType.contains("text/html") {
                        htmlText = decodeBodyPart(partBody, headers: partHeaders)
                    } else if partContentType.contains("multipart/") {
                        // Recursively handle nested multipart
                        let (nestedText, nestedHtml, nestedAttachments) = parseBody(partBody, contentType: partContentType)
                        if plainText == nil { plainText = nestedText }
                        if htmlText == nil { htmlText = nestedHtml }
                        attachments.append(contentsOf: nestedAttachments)
                    } else if let attachment = parseAttachment(partHeaders, body: partBody) {
                        attachments.append(attachment)
                    }
                }
            }
        } else if let contentType = contentType {
            // Single part message
            let ct = contentType.lowercased()
            if ct.contains("text/plain") {
                plainText = body.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if ct.contains("text/html") {
                htmlText = body.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            // No content type, assume plain text
            plainText = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (plainText, htmlText, attachments)
    }

    private func extractBoundary(from contentType: String) -> String? {
        // Look for boundary="..." or boundary=...
        let pattern = #"boundary\s*=\s*"?([^";\s]+)"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(contentType.startIndex..., in: contentType)
        if let match = regex.firstMatch(in: contentType, range: range),
           let boundaryRange = Range(match.range(at: 1), in: contentType) {
            return String(contentType[boundaryRange])
        }

        return nil
    }

    private func decodeBodyPart(_ body: String, headers: [String: String]) -> String {
        var result = body

        // Handle transfer encoding
        let encoding = headers["content-transfer-encoding"]?.lowercased() ?? ""

        if encoding == "quoted-printable" {
            result = decodeQuotedPrintableBody(result)
        } else if encoding == "base64" {
            if let data = Data(base64Encoded: result.replacingOccurrences(of: "\n", with: "")
                                                    .replacingOccurrences(of: "\r", with: "")),
               let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                result = decoded
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeQuotedPrintableBody(_ text: String) -> String {
        var result = ""
        var lines = text.components(separatedBy: "\n")

        for i in 0..<lines.count {
            var line = lines[i]

            // Handle soft line breaks
            while line.hasSuffix("=") && i < lines.count - 1 {
                line = String(line.dropLast())
                // This is simplified - proper implementation would need index tracking
                break
            }

            // Decode =XX sequences
            var index = line.startIndex
            while index < line.endIndex {
                if line[index] == "=" {
                    let nextIndex = line.index(after: index)
                    if nextIndex < line.endIndex {
                        if let endIndex = line.index(nextIndex, offsetBy: 2, limitedBy: line.endIndex) {
                            let hex = String(line[nextIndex..<endIndex])
                            if let byte = UInt8(hex, radix: 16) {
                                result.append(Character(UnicodeScalar(byte)))
                                index = endIndex
                                continue
                            }
                        }
                    }
                }
                result.append(line[index])
                index = line.index(after: index)
            }
            result.append("\n")
        }

        return result
    }

    private func parseAttachment(_ headers: [String: String], body: String) -> AttachmentInfo? {
        // Get filename from Content-Disposition or Content-Type
        var filename: String? = nil
        var mimeType: String? = nil
        var contentId: String? = nil
        var isInline = false

        if let disposition = headers["content-disposition"] {
            isInline = disposition.lowercased().contains("inline")
            filename = extractFilename(from: disposition)
        }

        if let ct = headers["content-type"] {
            mimeType = ct.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
            if filename == nil {
                filename = extractFilename(from: ct)
            }
        }

        if let cid = headers["content-id"] {
            contentId = cid.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }

        guard let name = filename else { return nil }

        // Estimate size from body (base64 encoded typically)
        let size = body.replacingOccurrences(of: "\n", with: "")
                       .replacingOccurrences(of: "\r", with: "")
                       .count * 3 / 4  // Base64 decode ratio

        return AttachmentInfo(
            filename: name,
            mimeType: mimeType,
            size: size > 0 ? size : nil,
            contentId: contentId,
            isInline: isInline
        )
    }

    private func extractFilename(from header: String) -> String? {
        // Look for filename="..." or name="..."
        let patterns = [
            #"filename\*?=\s*"?([^";\n]+)"?"#,
            #"name\s*=\s*"?([^";\n]+)"?"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
               let range = Range(match.range(at: 1), in: header) {
                var filename = String(header[range])

                // Handle RFC2231 encoding (filename*=utf-8''encoded)
                if filename.contains("''") {
                    let parts = filename.components(separatedBy: "''")
                    if parts.count == 2 {
                        filename = parts[1].removingPercentEncoding ?? parts[1]
                    }
                }

                return filename.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        return nil
    }
}
