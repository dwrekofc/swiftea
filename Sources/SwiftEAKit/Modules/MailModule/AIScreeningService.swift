// AIScreeningService - AI-powered email pre-screening via OpenRouter API

import Foundation

/// Email category assigned by AI screening
public enum EmailCategory: String, CaseIterable, Sendable {
    case actionRequired = "action-required"
    case internalFyi = "internal-fyi"
    case meetingInvite = "meeting-invite"
    case noise = "noise"
}

/// Result of AI screening for a single email
public struct ScreeningResult: Sendable {
    public let messageId: String
    public let summary: String
    public let category: EmailCategory
}

/// Errors that can occur during AI screening
public enum AIScreeningError: Error, LocalizedError {
    case apiKeyMissing
    case promptTemplateNotFound(path: String)
    case apiRequestFailed(statusCode: Int, body: String)
    case creditsExhausted(remaining: Double?)
    case responseParsingFailed(detail: String)
    case networkError(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "OPENROUTER_API_KEY environment variable is not set. Set it to enable AI screening."
        case .promptTemplateNotFound(let path):
            return "Prompt template not found at: \(path)"
        case .apiRequestFailed(let statusCode, let body):
            return "OpenRouter API request failed (HTTP \(statusCode)): \(body)"
        case .creditsExhausted(let remaining):
            if let remaining = remaining {
                return "OpenRouter credits exhausted (remaining: \(remaining)). Add credits at https://openrouter.ai/settings/credits"
            }
            return "OpenRouter credits exhausted. Add credits at https://openrouter.ai/settings/credits"
        case .responseParsingFailed(let detail):
            return "Failed to parse AI screening response: \(detail)"
        case .networkError(let underlying):
            return "Network error during AI screening: \(underlying.localizedDescription)"
        }
    }

    /// Whether this error indicates the API cannot process further requests (credits gone, payment required)
    public var isUnrecoverable: Bool {
        switch self {
        case .creditsExhausted:
            return true
        case .apiRequestFailed(let statusCode, _):
            return statusCode == 402 || statusCode == 429
        default:
            return false
        }
    }
}

/// Credit status from the OpenRouter API key endpoint
public struct OpenRouterCreditStatus {
    public let limit: Double?
    public let remaining: Double?
    public let isFreeTier: Bool
}

/// AI email screening service using OpenRouter API
public final class AIScreeningService {
    private let apiKey: String
    private let model: String
    private let promptTemplate: String
    private let apiBaseURL: String

    public init(
        apiKey: String,
        model: String = "openai/gpt-oss-120b",
        promptTemplate: String,
        apiBaseURL: String = "https://openrouter.ai/api/v1/chat/completions"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.promptTemplate = promptTemplate
        self.apiBaseURL = apiBaseURL
    }

    /// Check if an API key is available in the environment
    public static var hasAPIKey: Bool {
        environmentAPIKey != nil
    }

    /// Read the API key from the OPENROUTER_API_KEY environment variable
    public static var environmentAPIKey: String? {
        let value = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        guard let key = value, !key.isEmpty else { return nil }
        return key
    }

    /// Check credit status from the OpenRouter /api/v1/key endpoint
    public func checkCredits() -> OpenRouterCreditStatus? {
        guard let url = URL(string: "https://openrouter.ai/api/v1/key") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var httpResponse: HTTPURLResponse?

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            responseData = data
            httpResponse = response as? HTTPURLResponse
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        guard let statusCode = httpResponse?.statusCode, statusCode >= 200, statusCode < 300,
              let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keyData = json["data"] as? [String: Any] else {
            return nil
        }

        let limit = keyData["limit"] as? Double
        let remaining = keyData["limit_remaining"] as? Double
        let isFreeTier = keyData["is_free_tier"] as? Bool ?? true
        return OpenRouterCreditStatus(limit: limit, remaining: remaining, isFreeTier: isFreeTier)
    }

    /// Screen a single email message
    public func screen(message: MailMessage, recipientEmail: String?) -> Result<ScreeningResult, AIScreeningError> {
        let bodyText: String
        if let text = message.bodyText, !text.isEmpty {
            bodyText = String(text.prefix(4000))
        } else if let html = message.bodyHtml, !html.isEmpty {
            bodyText = String(stripHtmlForAI(html).prefix(4000))
        } else {
            bodyText = "(empty body)"
        }

        let prompt = renderPrompt(
            senderEmail: anonymizeEmail(message.senderEmail ?? "unknown"),
            recipientEmail: anonymizeEmail(recipientEmail ?? "unknown"),
            subject: message.subject,
            bodyText: bodyText
        )

        let apiResult = callOpenRouter(prompt: prompt)
        switch apiResult {
        case .success(let responseText):
            return parseScreeningResponse(responseText, messageId: message.id)
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Prompt Rendering

    /// Render the prompt template with variable substitution
    public func renderPrompt(
        senderEmail: String,
        recipientEmail: String,
        subject: String,
        bodyText: String
    ) -> String {
        let categories = EmailCategory.allCases.map { $0.rawValue }.joined(separator: ", ")
        return promptTemplate
            .replacingOccurrences(of: "{{senderEmail}}", with: senderEmail)
            .replacingOccurrences(of: "{{recipientEmail}}", with: recipientEmail)
            .replacingOccurrences(of: "{{subject}}", with: subject)
            .replacingOccurrences(of: "{{bodyText}}", with: bodyText)
            .replacingOccurrences(of: "{{categories}}", with: categories)
    }

    /// Anonymize an email address for privacy: "john.doe@company.com" -> "j***@company.com"
    public func anonymizeEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return email }
        let local = parts[0]
        let domain = parts[1]
        guard let firstChar = local.first else { return email }
        return "\(firstChar)***@\(domain)"
    }

    // MARK: - OpenRouter API

    /// Call the OpenRouter API with the rendered prompt
    private func callOpenRouter(prompt: String) -> Result<String, AIScreeningError> {
        guard let url = URL(string: apiBaseURL) else {
            return .failure(.apiRequestFailed(statusCode: 0, body: "Invalid API URL"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return .failure(.apiRequestFailed(statusCode: 0, body: "Failed to serialize request body"))
        }
        request.httpBody = bodyData

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var httpResponse: HTTPURLResponse?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            responseError = error
            httpResponse = response as? HTTPURLResponse
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = responseError {
            return .failure(.networkError(underlying: error))
        }

        guard let statusCode = httpResponse?.statusCode else {
            return .failure(.apiRequestFailed(statusCode: 0, body: "No HTTP response"))
        }

        guard let data = responseData else {
            return .failure(.apiRequestFailed(statusCode: statusCode, body: "Empty response body"))
        }

        guard statusCode >= 200 && statusCode < 300 else {
            let body = String(data: data, encoding: .utf8) ?? "(unreadable)"
            return .failure(.apiRequestFailed(statusCode: statusCode, body: String(body.prefix(500))))
        }

        // Parse the OpenRouter response to extract the assistant's message content
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "(unreadable)"
            return .failure(.responseParsingFailed(detail: "Could not extract content from response: \(String(raw.prefix(300)))"))
        }

        return .success(content)
    }

    // MARK: - Response Parsing

    /// Parse the LLM's JSON response into a ScreeningResult
    public func parseScreeningResponse(_ responseText: String, messageId: String) -> Result<ScreeningResult, AIScreeningError> {
        let cleaned = extractJSON(from: responseText)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.responseParsingFailed(detail: "Invalid JSON: \(String(responseText.prefix(200)))"))
        }

        // Accept summary or fall back to empty — caller can use subject as fallback
        let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let category: EmailCategory
        if let categoryStr = json["category"] as? String {
            if let exact = EmailCategory(rawValue: categoryStr) {
                category = exact
            } else {
                // Try normalizing: lowercase, trim, replace spaces with hyphens
                let normalized = categoryStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased().replacingOccurrences(of: " ", with: "-")
                if let fuzzy = EmailCategory(rawValue: normalized) {
                    category = fuzzy
                } else {
                    return .failure(.responseParsingFailed(detail: "Invalid category '\(categoryStr)'. Expected one of: \(EmailCategory.allCases.map { $0.rawValue }.joined(separator: ", "))"))
                }
            }
        } else {
            return .failure(.responseParsingFailed(detail: "Missing 'category' field"))
        }

        return .success(ScreeningResult(
            messageId: messageId,
            summary: summary.isEmpty ? "(no summary)" : summary,
            category: category
        ))
    }

    /// Try to extract a valid JSON object from a potentially malformed LLM response.
    /// Handles common issues: extra leading chars, markdown code fences, duplicate braces.
    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences: ```json ... ```
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let inner = lines.dropFirst().prefix(while: { !$0.hasPrefix("```") }).joined(separator: "\n")
            if !inner.isEmpty {
                let fenced = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = tryParseJSON(fenced) { return parsed }
            }
        }

        // Try the raw text first
        if let parsed = tryParseJSON(trimmed) { return parsed }

        // Try each '{' position as potential JSON start (handles prefix garbage)
        var searchRange = trimmed.startIndex..<trimmed.endIndex
        while let braceIdx = trimmed.range(of: "{", range: searchRange)?.lowerBound {
            let candidate = String(trimmed[braceIdx...])
            if let parsed = tryParseJSON(candidate) { return parsed }
            let next = trimmed.index(after: braceIdx)
            guard next < trimmed.endIndex else { break }
            searchRange = next..<trimmed.endIndex
        }

        return trimmed
    }

    /// Attempt to parse a string as a JSON object. Returns the string if valid, nil otherwise.
    private func tryParseJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] != nil else {
            return nil
        }
        return text
    }

    // MARK: - HTML Stripping

    /// Simple HTML-to-text fallback for emails with only body_html
    public func stripHtmlForAI(_ html: String) -> String {
        var text = html
        // Remove style and script blocks
        let blockPatterns = ["<style[^>]*>[\\s\\S]*?</style>", "<script[^>]*>[\\s\\S]*?</script>"]
        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }
        // Replace <br>, <p>, <div> tags with newlines
        let nlPatterns = ["<br[^>]*>", "</p>", "</div>", "</tr>", "</li>"]
        for pattern in nlPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
            }
        }
        // Strip remaining HTML tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse excessive whitespace
        text = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return text
    }
}
