// MailViewFilter - Vault-scoped view filter for the global mail database

import Foundation

/// Defines which accounts and mailboxes a vault should display from the global database.
/// Stored in each vault's .swiftea/config.json as part of VaultConfig v2.
public struct MailViewFilter: Codable, Sendable {
    /// Account IDs to include (e.g., ["iCloud", "Gmail"])
    public var accounts: [String]

    /// Mailbox names to include (e.g., ["INBOX", "Sent"])
    public var mailboxes: [String]

    /// If true, show all mailboxes for the selected accounts (ignores mailboxes array)
    public var includeAllMailboxes: Bool

    public init(
        accounts: [String] = [],
        mailboxes: [String] = [],
        includeAllMailboxes: Bool = true
    ) {
        self.accounts = accounts
        self.mailboxes = mailboxes
        self.includeAllMailboxes = includeAllMailboxes
    }

    /// True when no filtering is applied (show everything)
    public var isUnfiltered: Bool {
        accounts.isEmpty && (includeAllMailboxes || mailboxes.isEmpty)
    }

    /// Generate a SQL WHERE clause fragment for filtering messages.
    /// Returns nil if no filtering is needed (isUnfiltered).
    ///
    /// - Parameter tableAlias: The table alias used in the query (e.g., "m" for messages)
    /// - Returns: A SQL WHERE clause fragment like "m.account_id IN ('iCloud','Gmail')"
    public func sqlWhereClause(tableAlias: String = "m") -> String? {
        guard !isUnfiltered else { return nil }

        var clauses: [String] = []

        if !accounts.isEmpty {
            let escaped = accounts.map { escapeSQL($0) }
            let inList = escaped.map { "'\($0)'" }.joined(separator: ",")
            clauses.append("\(tableAlias).account_id IN (\(inList))")
        }

        if !includeAllMailboxes && !mailboxes.isEmpty {
            let escaped = mailboxes.map { escapeSQL($0) }
            let inList = escaped.map { "'\($0)'" }.joined(separator: ",")
            clauses.append("\(tableAlias).mailbox_name IN (\(inList))")
        }

        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: " AND ")
    }

    /// Generate a SQL WHERE clause for filtering threads.
    /// This uses a subquery on thread_messages + messages to check if the thread
    /// contains messages matching the filter.
    ///
    /// - Parameter threadAlias: The table alias used for the threads table (e.g., "t")
    /// - Returns: A SQL WHERE clause fragment using EXISTS subquery
    public func sqlThreadWhereClause(threadAlias: String = "t") -> String? {
        guard !isUnfiltered else { return nil }

        // Build the inner message filter
        guard let messageFilter = sqlWhereClause(tableAlias: "fm") else { return nil }

        return """
            EXISTS (
                SELECT 1 FROM thread_messages ftm
                JOIN messages fm ON ftm.message_id = fm.id
                WHERE ftm.thread_id = \(threadAlias).id
                AND \(messageFilter)
            )
            """
    }

    private func escapeSQL(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
