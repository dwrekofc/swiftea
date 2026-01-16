// MailSyncBackward - Push archive/delete actions to Apple Mail
//
// This module handles backward sync: pushing local state changes to Apple Mail.
// Uses an optimistic update pattern: update local DB first, then execute AppleScript.
// On failure, the local state is rolled back.

import Foundation

/// Result of a backward sync operation
public struct BackwardSyncResult: Sendable {
    /// Number of messages successfully archived
    public let archived: Int
    /// Number of messages successfully deleted
    public let deleted: Int
    /// Number of messages that failed to sync
    public let failed: Int
    /// Error messages for failed operations
    public let errors: [String]

    public init(archived: Int = 0, deleted: Int = 0, failed: Int = 0, errors: [String] = []) {
        self.archived = archived
        self.deleted = deleted
        self.failed = failed
        self.errors = errors
    }
}

/// Errors that can occur during backward sync operations
public enum BackwardSyncError: Error, LocalizedError {
    case messageNotFound(id: String)
    case noMessageId(id: String)
    case appleScriptFailed(id: String, underlying: Error)
    case rollbackFailed(id: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .messageNotFound(let id):
            return "Message not found in database: \(id)"
        case .noMessageId(let id):
            return "Message has no RFC822 Message-ID for AppleScript lookup: \(id)"
        case .appleScriptFailed(let id, let underlying):
            return "AppleScript failed for message \(id): \(underlying.localizedDescription)"
        case .rollbackFailed(let id, let underlying):
            return "Failed to rollback status for message \(id): \(underlying.localizedDescription)"
        }
    }
}

/// Handles backward sync: pushing archive/delete actions from SwiftEA to Apple Mail
///
/// Uses the optimistic update pattern:
/// 1. Update local DB status immediately
/// 2. Execute AppleScript to move message in Apple Mail
/// 3. On success: clear pending action and delete exported .md file
/// 4. On failure: rollback local status to original state
public final class MailSyncBackward: @unchecked Sendable {
    private let mailDatabase: MailDatabase
    private let appleScriptService: AppleScriptServiceProtocol
    private let fileManager: FileManager

    public init(
        mailDatabase: MailDatabase,
        appleScriptService: AppleScriptServiceProtocol = AppleScriptService.shared,
        fileManager: FileManager = .default
    ) {
        self.mailDatabase = mailDatabase
        self.appleScriptService = appleScriptService
        self.fileManager = fileManager
    }

    // MARK: - Private Helpers

    /// Delete the exported .md file for a message after archive/delete
    ///
    /// This cleans up orphaned .md files when messages are archived or deleted.
    /// Logs a warning if deletion fails but does not throw (non-fatal).
    ///
    /// - Parameter message: The message whose export file should be deleted
    private func deleteExportedFile(message: MailMessage) {
        guard let exportPath = message.exportPath else {
            return
        }

        do {
            if fileManager.fileExists(atPath: exportPath) {
                try fileManager.removeItem(atPath: exportPath)
            }
        } catch {
            // Log warning but don't fail - this is a cleanup operation
            // The message was already successfully archived/deleted in Mail.app
            print("Warning: Failed to delete exported file at \(exportPath): \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    /// Archive a message using optimistic update pattern
    ///
    /// Flow:
    /// 1. Set mailbox_status = 'archived' and pending_sync_action = 'archive'
    /// 2. Execute AppleScript to move message to Archive
    /// 3. On success: clear pending_sync_action
    /// 4. On failure: rollback status but keep pending action for retry via processPendingActions()
    ///
    /// - Parameter id: The SwiftEA message ID to archive
    /// - Throws: BackwardSyncError if the operation fails
    public func archiveMessage(id: String) throws {
        // Step 1: Get current message state for potential rollback
        guard let message = try mailDatabase.getMessage(id: id) else {
            throw BackwardSyncError.messageNotFound(id: id)
        }

        guard let rfc822MessageId = message.messageId else {
            throw BackwardSyncError.noMessageId(id: id)
        }

        let originalStatus = message.mailboxStatus

        // Step 2: Optimistic update - set status and pending action
        try mailDatabase.updateMailboxStatus(id: id, status: .archived)
        try mailDatabase.setPendingSyncAction(id: id, action: .archive)

        // Step 3: Execute AppleScript to move to Archive
        do {
            let script = MailSyncBackwardScripts.archiveMessage(byMessageId: rfc822MessageId)
            _ = try appleScriptService.executeMailScript(script)

            // Step 4a: Success - clear pending action and delete exported file
            try mailDatabase.clearPendingSyncAction(id: id)
            deleteExportedFile(message: message)
        } catch {
            // Step 4b: Failure - rollback status but keep pending action for retry
            // The pending_sync_action is retained so processPendingActions() can retry
            do {
                try mailDatabase.updateMailboxStatus(id: id, status: originalStatus)
            } catch let rollbackError {
                throw BackwardSyncError.rollbackFailed(id: id, underlying: rollbackError)
            }
            throw BackwardSyncError.appleScriptFailed(id: id, underlying: error)
        }
    }

    /// Delete a message using optimistic update pattern
    ///
    /// Flow:
    /// 1. Set mailbox_status = 'deleted' and pending_sync_action = 'delete'
    /// 2. Execute AppleScript to move message to Trash
    /// 3. On success: clear pending_sync_action
    /// 4. On failure: rollback status but keep pending action for retry via processPendingActions()
    ///
    /// - Parameter id: The SwiftEA message ID to delete
    /// - Throws: BackwardSyncError if the operation fails
    public func deleteMessage(id: String) throws {
        // Step 1: Get current message state for potential rollback
        guard let message = try mailDatabase.getMessage(id: id) else {
            throw BackwardSyncError.messageNotFound(id: id)
        }

        guard let rfc822MessageId = message.messageId else {
            throw BackwardSyncError.noMessageId(id: id)
        }

        let originalStatus = message.mailboxStatus

        // Step 2: Optimistic update - set status and pending action
        try mailDatabase.updateMailboxStatus(id: id, status: .deleted)
        try mailDatabase.setPendingSyncAction(id: id, action: .delete)

        // Step 3: Execute AppleScript to move to Trash
        do {
            let script = MailSyncBackwardScripts.deleteMessage(byMessageId: rfc822MessageId)
            _ = try appleScriptService.executeMailScript(script)

            // Step 4a: Success - clear pending action and delete exported file
            try mailDatabase.clearPendingSyncAction(id: id)
            deleteExportedFile(message: message)
        } catch {
            // Step 4b: Failure - rollback status but keep pending action for retry
            // The pending_sync_action is retained so processPendingActions() can retry
            do {
                try mailDatabase.updateMailboxStatus(id: id, status: originalStatus)
            } catch let rollbackError {
                throw BackwardSyncError.rollbackFailed(id: id, underlying: rollbackError)
            }
            throw BackwardSyncError.appleScriptFailed(id: id, underlying: error)
        }
    }

    /// Process all messages with pending sync actions
    ///
    /// This method is designed to be called during sync to process any
    /// queued actions that haven't been synced yet (e.g., from a previous
    /// failed sync attempt).
    ///
    /// - Returns: BackwardSyncResult with counts of archived, deleted, and failed operations
    public func processPendingActions() throws -> BackwardSyncResult {
        var archived = 0
        var deleted = 0
        var failed = 0
        var errors: [String] = []

        // Get all messages with pending actions (oldest first for fairness)
        let pendingMessages = try mailDatabase.getMessagesWithPendingActions()

        for message in pendingMessages {
            guard let action = message.pendingSyncAction else {
                continue
            }

            guard let rfc822MessageId = message.messageId else {
                errors.append("Message \(message.id) has no RFC822 Message-ID")
                failed += 1
                continue
            }

            do {
                switch action {
                case .archive:
                    let script = MailSyncBackwardScripts.archiveMessage(byMessageId: rfc822MessageId)
                    _ = try appleScriptService.executeMailScript(script)
                    try mailDatabase.clearPendingSyncAction(id: message.id)
                    archived += 1

                case .delete:
                    let script = MailSyncBackwardScripts.deleteMessage(byMessageId: rfc822MessageId)
                    _ = try appleScriptService.executeMailScript(script)
                    try mailDatabase.clearPendingSyncAction(id: message.id)
                    deleted += 1
                }
            } catch {
                errors.append("Failed to \(action.rawValue) message \(message.id): \(error.localizedDescription)")
                failed += 1
                // Don't clear the pending action - it will be retried next sync
            }
        }

        return BackwardSyncResult(archived: archived, deleted: deleted, failed: failed, errors: errors)
    }
}

// MARK: - AppleScript Templates for Backward Sync

/// AppleScript templates for moving messages to Archive and Trash
public struct MailSyncBackwardScripts {

    /// Common script fragment to find a message by ID using two-stage search
    ///
    /// Mail.app doesn't support global message searches - we must search within each mailbox.
    /// Uses a two-stage approach for performance:
    /// 1. First searches common mailboxes (Inbox, Sent, Archive, Drafts, Junk, Trash)
    /// 2. If not found, falls back to searching ALL mailboxes in each account
    ///
    /// This balances performance (fast search of common folders) with completeness
    /// (fallback finds messages in custom folders).
    private static func messageSearchScript(messageId: String) -> String {
        """
        set targetMsgId to "\(escapeAppleScript(messageId))"
        set theMessage to missing value

        -- Stage 1: Search common mailboxes first (fast path)
        set commonMailboxes to {"Inbox", "Sent Items", "Sent", "Archive", "Drafts", "Junk", "Spam", "Trash", "Deleted Items"}
        set searchedFolders to {}

        repeat with acc in accounts
            repeat with mboxName in commonMailboxes
                try
                    set targetMbox to mailbox mboxName of acc
                    set foundMsgs to (every message of targetMbox whose message id is targetMsgId)
                    if (count of foundMsgs) > 0 then
                        set theMessage to item 1 of foundMsgs
                        exit repeat
                    end if
                    -- Track which folders we actually searched (mailbox exists)
                    if mboxName is not in searchedFolders then
                        set end of searchedFolders to mboxName
                    end if
                end try
            end repeat
            if theMessage is not missing value then exit repeat
        end repeat

        -- Stage 2: If not found, search ALL mailboxes as fallback
        if theMessage is missing value then
            repeat with acc in accounts
                try
                    set allMailboxes to every mailbox of acc
                    repeat with mbox in allMailboxes
                        try
                            set foundMsgs to (every message of mbox whose message id is targetMsgId)
                            if (count of foundMsgs) > 0 then
                                set theMessage to item 1 of foundMsgs
                                exit repeat
                            end if
                        end try
                    end repeat
                end try
                if theMessage is not missing value then exit repeat
            end repeat
        end if

        if theMessage is missing value then
            error "Message not found. Searched common folders: " & (searchedFolders as text) & " plus all account mailboxes" number -1728
        end if
        """
    }

    /// Generate script to archive a message (move to Archive mailbox)
    ///
    /// Uses the account's Archive mailbox which Mail.app creates automatically.
    /// Supports localized folder names by trying multiple common names.
    /// - Parameter messageId: The RFC822 Message-ID to search for
    /// - Returns: AppleScript to move the message to Archive
    public static func archiveMessage(byMessageId messageId: String) -> String {
        // Try multiple archive mailbox names for different locales
        // English: Archive, All Mail
        // Spanish: Archivo
        // French: Archives
        // German: Archiv
        let archiveNames = ["Archive", "All Mail", "Archives", "Archivo", "Archiv"]

        var script = messageSearchScript(messageId: messageId)
        script += """
        set theAccount to account of mailbox of theMessage
        set archiveMailbox to missing value

        """

        // Try each archive name
        for (index, name) in archiveNames.enumerated() {
            if index > 0 {
                script += "if archiveMailbox is missing value then\n"
            }
            script += """
            try
                set archiveMailbox to mailbox "\(name)" of theAccount
            end try
            """
            if index < archiveNames.count - 1 {
                script += "\nend if\n"
            }
        }

        script += """

        if archiveMailbox is missing value then
            error "Archive mailbox not found. Checked: \(archiveNames.joined(separator: ", "))" number -1729
        end if

        move theMessage to archiveMailbox
        return "archived"
        """

        return script
    }

    /// Generate script to delete a message (move to Trash mailbox)
    ///
    /// Uses the account's Trash mailbox.
    /// Supports localized folder names by trying multiple common names.
    /// - Parameter messageId: The RFC822 Message-ID to search for
    /// - Returns: AppleScript to move the message to Trash
    public static func deleteMessage(byMessageId messageId: String) -> String {
        // Try multiple trash mailbox names for different locales
        // English: Trash, Deleted Items
        // Spanish: Papelera
        // French: Corbeille
        // German: Papierkorb
        let trashNames = ["Trash", "Deleted Items", "Papelera", "Corbeille", "Papierkorb"]

        var script = messageSearchScript(messageId: messageId)
        script += """
        set theAccount to account of mailbox of theMessage
        set trashMailbox to missing value

        """

        // Try each trash name
        for (index, name) in trashNames.enumerated() {
            if index > 0 {
                script += "if trashMailbox is missing value then\n"
            }
            script += """
            try
                set trashMailbox to mailbox "\(name)" of theAccount
            end try
            """
            if index < trashNames.count - 1 {
                script += "\nend if\n"
            }
        }

        script += """

        if trashMailbox is missing value then
            error "Trash mailbox not found. Checked: \(trashNames.joined(separator: ", "))" number -1730
        end if

        move theMessage to trashMailbox
        return "deleted"
        """

        return script
    }

    /// Strip RFC822 angle brackets from message ID for Mail.app AppleScript lookup
    ///
    /// Mail.app's AppleScript interface expects message IDs without angle brackets,
    /// but RFC822 Message-ID headers include them (e.g., `<foo@bar.com>`).
    private static func stripAngleBrackets(_ messageId: String) -> String {
        var result = messageId
        if result.hasPrefix("<") { result.removeFirst() }
        if result.hasSuffix(">") { result.removeLast() }
        return result
    }

    /// Escape a string for safe use in AppleScript
    private static func escapeAppleScript(_ string: String) -> String {
        // First strip angle brackets for message IDs, then escape special characters
        stripAngleBrackets(string)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
