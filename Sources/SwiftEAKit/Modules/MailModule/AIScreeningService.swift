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
        case .responseParsingFailed(let detail):
            return "Failed to parse AI screening response: \(detail)"
        case .networkError(let underlying):
            return "Network error during AI screening: \(underlying.localizedDescription)"
        }
    }
}

/// AI email screening service using OpenRouter API
public final class AIScreeningService {
    private let apiKey: String
    private let model: String
    private let promptTemplate: String
    private let apiBaseURL: String

    public init(
        apiKey: String,
        model: String = "google/gemini-2.0-flash-001",
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
        guard let data = responseText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.responseParsingFailed(detail: "Invalid JSON: \(String(responseText.prefix(200)))"))
        }

        guard let summary = json["summary"] as? String, !summary.isEmpty else {
            return .failure(.responseParsingFailed(detail: "Missing or empty 'summary' field"))
        }

        guard let categoryStr = json["category"] as? String,
              let category = EmailCategory(rawValue: categoryStr) else {
            let raw = json["category"] as? String ?? "(missing)"
            return .failure(.responseParsingFailed(detail: "Invalid category '\(raw)'. Expected one of: \(EmailCategory.allCases.map { $0.rawValue }.joined(separator: ", "))"))
        }

        return .success(ScreeningResult(
            messageId: messageId,
            summary: summary,
            category: category
        ))
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
