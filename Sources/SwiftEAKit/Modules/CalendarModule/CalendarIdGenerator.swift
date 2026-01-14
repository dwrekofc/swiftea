// CalendarIdGenerator.swift - Stable ID generation for calendar events
//
// Implements multi-ID strategy from design doc:
// - Primary: calendarItemExternalIdentifier (most stable for CalDAV/iCloud)
// - Fallback: SHA-256 hash of calendar_id + summary + start_time
// - Recurring: UID + occurrence date

import Foundation
import CryptoKit

// MARK: - Event Identity

/// Captures all EventKit identifiers for an event.
/// Used for ID reconciliation during sync operations.
public struct EventKitIdentity: Sendable, Equatable {
    /// EKEvent.eventIdentifier - fast local lookup, may change after sync
    public let eventIdentifier: String?

    /// EKEvent.calendarItemExternalIdentifier - most stable, can be nil before sync
    public let externalIdentifier: String?

    /// EKCalendar.calendarIdentifier - stable calendar-level ID
    public let calendarIdentifier: String

    public init(
        eventIdentifier: String?,
        externalIdentifier: String?,
        calendarIdentifier: String
    ) {
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarIdentifier = calendarIdentifier
    }
}

// MARK: - Calendar ID Generator

/// Generates stable, deterministic IDs for calendar events.
/// Implements multi-ID strategy for EventKit sync stability.
public struct CalendarIdGenerator: Sendable {

    public init() {}

    // MARK: - Public ID Generation

    /// Generate a stable public ID for a calendar event.
    ///
    /// ID selection priority:
    /// 1. calendarItemExternalIdentifier (most stable for synced events)
    /// 2. Hash fallback for local-only or pre-sync events
    ///
    /// - Parameters:
    ///   - identity: EventKit identifiers for the event
    ///   - summary: Event title/summary (for hash fallback)
    ///   - startDate: Event start time (for hash fallback)
    ///   - occurrenceDate: For recurring instances, the specific occurrence date
    /// - Returns: A stable, deterministic ID string
    public func generatePublicId(
        identity: EventKitIdentity,
        summary: String?,
        startDate: Date,
        occurrenceDate: Date? = nil
    ) -> String {
        // Primary: Use external identifier if available (most stable)
        if let externalId = identity.externalIdentifier, !externalId.isEmpty {
            if let occDate = occurrenceDate {
                // Recurring instance: combine external ID with occurrence date
                return generateRecurringInstanceId(
                    baseId: externalId,
                    occurrenceDate: occDate
                )
            }
            // Single event: normalize and use external ID directly
            return normalizeExternalId(externalId)
        }

        // Fallback: Generate hash-based ID
        return generateFallbackId(
            calendarId: identity.calendarIdentifier,
            summary: summary,
            startDate: startDate,
            occurrenceDate: occurrenceDate
        )
    }

    /// Generate a fallback hash ID when external identifier is not available.
    /// Uses SHA-256 of calendar_id + summary + start_time.
    ///
    /// - Parameters:
    ///   - calendarId: Calendar identifier
    ///   - summary: Event title/summary
    ///   - startDate: Event start time
    ///   - occurrenceDate: For recurring instances
    /// - Returns: Hash-based ID
    public func generateFallbackId(
        calendarId: String,
        summary: String?,
        startDate: Date,
        occurrenceDate: Date? = nil
    ) -> String {
        var components: [String] = []

        components.append("cal:\(calendarId)")

        if let summary = summary, !summary.isEmpty {
            components.append("sum:\(summary)")
        }

        components.append("start:\(Int(startDate.timeIntervalSince1970))")

        if let occDate = occurrenceDate {
            components.append("occ:\(Int(occDate.timeIntervalSince1970))")
        }

        let digest = components.joined(separator: "|")
        return hashString("cal-event:\(digest)")
    }

    /// Generate ID for a recurring event instance.
    /// Combines the base event ID with the occurrence date.
    ///
    /// - Parameters:
    ///   - baseId: The master event's ID or external identifier
    ///   - occurrenceDate: The specific occurrence date
    /// - Returns: Instance-specific ID
    public func generateRecurringInstanceId(
        baseId: String,
        occurrenceDate: Date
    ) -> String {
        let occTimestamp = Int(occurrenceDate.timeIntervalSince1970)
        return hashString("recur:\(baseId)|\(occTimestamp)")
    }

    // MARK: - ID Reconciliation

    /// Result of ID reconciliation during sync.
    public enum ReconciliationResult: Equatable, Sendable {
        /// IDs match - no action needed
        case match

        /// External ID changed - update stored identity but keep public ID
        case externalIdChanged(newExternalId: String)

        /// EventKit ID changed - update stored identity for future lookups
        case eventKitIdChanged(newEventKitId: String)

        /// Both IDs changed - update both stored identities
        case bothIdsChanged(newEventKitId: String, newExternalId: String)

        /// Event not found - may have been deleted
        case notFound

        /// New event - needs full insert
        case newEvent
    }

    /// Reconcile stored identity with current EventKit identity.
    /// Used during sync to handle ID changes (e.g., after iCloud sync completes).
    ///
    /// - Parameters:
    ///   - stored: Previously stored identity (from database)
    ///   - current: Current identity from EventKit
    /// - Returns: Reconciliation result indicating what changed
    public func reconcileIdentity(
        stored: EventKitIdentity?,
        current: EventKitIdentity
    ) -> ReconciliationResult {
        guard let stored = stored else {
            return .newEvent
        }

        // Check if either ID matches
        let eventKitIdMatches = stored.eventIdentifier == current.eventIdentifier
            && stored.eventIdentifier != nil
        let externalIdMatches = stored.externalIdentifier == current.externalIdentifier
            && stored.externalIdentifier != nil

        // Both match - no change
        if eventKitIdMatches && externalIdMatches {
            return .match
        }

        // At least one matches - update the other
        if eventKitIdMatches && !externalIdMatches {
            if let newExternal = current.externalIdentifier {
                return .externalIdChanged(newExternalId: newExternal)
            }
            return .match // External was nil before, still nil
        }

        if externalIdMatches && !eventKitIdMatches {
            if let newEventKit = current.eventIdentifier {
                return .eventKitIdChanged(newEventKitId: newEventKit)
            }
            return .match // EventKit was nil before, still nil
        }

        // Neither matches but calendar matches - likely ID refresh after sync
        if stored.calendarIdentifier == current.calendarIdentifier {
            let newEventKit = current.eventIdentifier
            let newExternal = current.externalIdentifier

            if newEventKit != nil || newExternal != nil {
                if let ek = newEventKit, let ext = newExternal {
                    return .bothIdsChanged(newEventKitId: ek, newExternalId: ext)
                } else if let ek = newEventKit {
                    return .eventKitIdChanged(newEventKitId: ek)
                } else if let ext = newExternal {
                    return .externalIdChanged(newExternalId: ext)
                }
            }
        }

        return .notFound
    }

    /// Check if an event should be considered the same based on content matching.
    /// Used as last resort when IDs don't match.
    ///
    /// - Parameters:
    ///   - storedSummary: Summary from database
    ///   - storedStart: Start date from database
    ///   - currentSummary: Summary from EventKit
    ///   - currentStart: Start date from EventKit
    ///   - tolerance: Time tolerance for start date comparison (default: 60 seconds)
    /// - Returns: True if events appear to be the same
    public func contentMatches(
        storedSummary: String?,
        storedStart: Date,
        currentSummary: String?,
        currentStart: Date,
        tolerance: TimeInterval = 60
    ) -> Bool {
        // Summaries must match (normalized)
        let normalizedStored = (storedSummary ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let normalizedCurrent = (currentSummary ?? "").lowercased().trimmingCharacters(in: .whitespaces)

        guard normalizedStored == normalizedCurrent else {
            return false
        }

        // Start times must be within tolerance
        let timeDiff = abs(storedStart.timeIntervalSince(currentStart))
        return timeDiff <= tolerance
    }

    // MARK: - Calendar ID

    /// Generate a stable ID for a calendar.
    /// Prefers the calendar's identifier from EventKit.
    ///
    /// - Parameters:
    ///   - calendarIdentifier: EKCalendar.calendarIdentifier
    ///   - title: Calendar title (fallback)
    ///   - source: Calendar source name (fallback)
    /// - Returns: Stable calendar ID
    public func generateCalendarId(
        calendarIdentifier: String?,
        title: String,
        source: String?
    ) -> String {
        // Prefer EventKit's calendar identifier
        if let calId = calendarIdentifier, !calId.isEmpty {
            return normalizeExternalId(calId)
        }

        // Fallback: hash title + source
        var components = ["title:\(title)"]
        if let src = source {
            components.append("src:\(src)")
        }
        return hashString("calendar:\(components.joined(separator: "|"))")
    }

    // MARK: - Validation

    /// Check if a string looks like a valid stable ID.
    public func isValidId(_ id: String) -> Bool {
        // Valid IDs are 32 lowercase hex characters (128 bits)
        guard id.count == 32 else { return false }
        return id.allSatisfy { $0.isHexDigit }
    }

    /// Check if an ID looks like a normalized external ID (not hashed).
    public func isExternalId(_ id: String) -> Bool {
        // External IDs from EventKit typically contain specific patterns
        // They're usually UUIDs or similar structured identifiers
        return !isValidId(id) && !id.isEmpty
    }

    // MARK: - Private Helpers

    /// Normalize an external identifier for consistent storage.
    /// Removes whitespace and lowercases for comparison.
    private func normalizeExternalId(_ externalId: String) -> String {
        externalId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate a SHA-256 hash and return first 32 characters.
    private func hashString(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return String(hashString.prefix(32))
    }
}

// MARK: - Helper Extensions

private extension Character {
    var isHexDigit: Bool {
        return ("0"..."9").contains(self) || ("a"..."f").contains(self)
    }
}

// MARK: - Convenience Extensions

extension CalendarIdGenerator {
    /// Generate public ID with minimal parameters (for simple cases).
    public func generatePublicId(
        externalIdentifier: String?,
        calendarIdentifier: String,
        summary: String?,
        startDate: Date
    ) -> String {
        let identity = EventKitIdentity(
            eventIdentifier: nil,
            externalIdentifier: externalIdentifier,
            calendarIdentifier: calendarIdentifier
        )
        return generatePublicId(
            identity: identity,
            summary: summary,
            startDate: startDate
        )
    }
}
