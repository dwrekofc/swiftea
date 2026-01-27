// PromptTemplateManager - Manages the AI screening prompt template

import Foundation

/// Manages loading and creating the AI screening prompt template
public struct PromptTemplateManager {

    /// Get the path to the prompt template file within a vault
    public static func promptPath(vaultRoot: String) -> String {
        (vaultRoot as NSString).appendingPathComponent(".swiftea/ai-prompt.md")
    }

    /// Load the existing prompt template or create the default one
    public static func loadOrCreateTemplate(vaultRoot: String) throws -> String {
        let path = promptPath(vaultRoot: vaultRoot)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: path) {
            return try String(contentsOfFile: path, encoding: .utf8)
        }

        // Create default template
        let dir = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try defaultTemplate.write(toFile: path, atomically: true, encoding: .utf8)
        return defaultTemplate
    }

    /// The default prompt template content
    public static let defaultTemplate = """
        You are an email screening assistant. Analyze the following email and provide:
        1. A brief summary (1-2 sentences)
        2. A category classification

        ## Email Details

        **From:** {{senderEmail}}
        **To:** {{recipientEmail}}
        **Subject:** {{subject}}

        ## Email Body

        {{bodyText}}

        ## Instructions

        Classify this email into exactly ONE of these categories: {{categories}}

        Category definitions:
        - **action-required**: Sent directly to the recipient from a known person, requires reading or reply
        - **internal-fyi**: Internal memo or announcement, no action required
        - **meeting-invite**: Calendar event invitation or meeting request
        - **noise**: External sales pitches, marketing newsletters, automated notifications, promotions

        Respond with ONLY a JSON object in this exact format:
        {"summary": "Brief 1-2 sentence summary", "category": "one-of-the-categories-above"}
        """
}
