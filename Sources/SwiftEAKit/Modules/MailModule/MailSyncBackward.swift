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

    /// Generate script to archive a message (move to Archive mailbox)
    ///
    /// Uses the account's Archive mailbox which Mail.app creates automatically.
    /// Searches inbox only for simplicity - like deleteMessage().
    /// Supports localized mailbox names for different locales.
    ///
    /// - Parameter messageId: The RFC822 Message-ID to search for
    /// - Returns: AppleScript to move the message to Archive
    public static func archiveMessage(byMessageId messageId: String) -> String {
        let escapedId = escapeAppleScript(messageId)
        return """
        set targetMsgId to "\(escapedId)"
        set candidates to {targetMsgId, "<" & targetMsgId & ">"}
        set archiveNames to {"Archive", "All Mail", "Archives", "Archivo", "Archiv"}

        repeat with cid in candidates
            try
                set m to first message of inbox whose message id is (cid as text)
                set theAccount to account of mailbox of m
                repeat with archiveName in archiveNames
                    try
                        set archiveMailbox to mailbox (archiveName as text) of theAccount
                        move m to archiveMailbox
                        return "archived"
                    end try
                end repeat
                error "Archive mailbox not found" number -1729
            on error errMsg number errNum
                if errNum is -1728 then
                    -- Message not found with this candidate, try next
                else if errNum is -1729 then
                    error errMsg number errNum
                end if
            end try
        end repeat

        error "Message not found in Inbox with ID: " & targetMsgId number -1728
        """
    }

    /// Generate script to delete a message (move to Trash)
    ///
    /// Uses Mail.app's native `delete` command which automatically moves messages to Trash.
    /// This is simpler and more reliable than manually locating Trash mailboxes.
    /// Searches global inbox directly - simple and fast.
    ///
    /// - Parameter messageId: The RFC822 Message-ID to search for
    /// - Returns: AppleScript to delete the message
    public static func deleteMessage(byMessageId messageId: String) -> String {
        let escapedId = escapeAppleScript(messageId)
        return """
        set targetMsgId to "\(escapedId)"
        set candidates to {targetMsgId, "<" & targetMsgId & ">"}

        repeat with cid in candidates
            try
                set m to first message of inbox whose message id is (cid as text)
                delete m
                return "deleted"
            on error errMsg number errNum
                if errNum is -1728 then
                    -- Message not found with this candidate, try next
                end if
            end try
        end repeat

        error "Message not found in Inbox with ID: " & targetMsgId number -1728
        """
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
