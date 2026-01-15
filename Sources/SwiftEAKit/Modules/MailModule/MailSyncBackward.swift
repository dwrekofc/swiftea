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
/// 3. On success: clear pending action
/// 4. On failure: rollback local status to original state
public final class MailSyncBackward: @unchecked Sendable {
    private let mailDatabase: MailDatabase
    private let appleScriptService: AppleScriptService

    public init(mailDatabase: MailDatabase, appleScriptService: AppleScriptService = .shared) {
        self.mailDatabase = mailDatabase
        self.appleScriptService = appleScriptService
    }

    // MARK: - Public API

    /// Archive a message using optimistic update pattern
    ///
    /// Flow:
    /// 1. Set mailbox_status = 'archived' and pending_sync_action = 'archive'
    /// 2. Execute AppleScript to move message to Archive
    /// 3. On success: clear pending_sync_action
    /// 4. On failure: rollback to original status
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

            // Step 4a: Success - clear pending action
            try mailDatabase.clearPendingSyncAction(id: id)
        } catch {
            // Step 4b: Failure - rollback to original status
            do {
                try mailDatabase.updateMailboxStatus(id: id, status: originalStatus)
                try mailDatabase.clearPendingSyncAction(id: id)
            } catch let rollbackError {
                // Log but don't throw rollback error - the original error is more important
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
    /// 4. On failure: rollback to original status
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

            // Step 4a: Success - clear pending action
            try mailDatabase.clearPendingSyncAction(id: id)
        } catch {
            // Step 4b: Failure - rollback to original status
            do {
                try mailDatabase.updateMailboxStatus(id: id, status: originalStatus)
                try mailDatabase.clearPendingSyncAction(id: id)
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
    /// - Parameter messageId: The RFC822 Message-ID to search for
    /// - Returns: AppleScript to move the message to Archive
    public static func archiveMessage(byMessageId messageId: String) -> String {
        """
        set targetMessages to (every message whose message id is "\(escapeAppleScript(messageId))")
        if (count of targetMessages) = 0 then
            error "Message not found" number -1728
        end if
        set theMessage to item 1 of targetMessages
        set theAccount to account of mailbox of theMessage
        set archiveMailbox to mailbox "Archive" of theAccount
        move theMessage to archiveMailbox
        return "archived"
        """
    }

    /// Generate script to delete a message (move to Trash mailbox)
    ///
    /// Uses the account's Trash mailbox.
    /// - Parameter messageId: The RFC822 Message-ID to search for
    /// - Returns: AppleScript to move the message to Trash
    public static func deleteMessage(byMessageId messageId: String) -> String {
        """
        set targetMessages to (every message whose message id is "\(escapeAppleScript(messageId))")
        if (count of targetMessages) = 0 then
            error "Message not found" number -1728
        end if
        set theMessage to item 1 of targetMessages
        delete theMessage
        return "deleted"
        """
    }

    /// Escape a string for safe use in AppleScript
    private static func escapeAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
