// CalendarExporter.swift - Export calendar data to various formats
//
// Supports three export formats:
// - Markdown: YAML frontmatter + body (Obsidian-compatible)
// - JSON: ClaudEA envelope format
// - ICS: RFC 5545 iCalendar format

import Foundation
import ICalendarKit

// MARK: - Export Format

/// Supported export formats for calendar data
public enum CalendarExportFormat: String, CaseIterable, Sendable {
    case markdown = "md"
    case json
    case ics

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .ics: return "ics"
        }
    }
}

// MARK: - Exporter Protocol

/// Protocol for calendar export implementations
public protocol CalendarExporter {
    /// Export a single event
    func export(event: StoredEvent, attendees: [StoredAttendee], calendar: StoredCalendar?) -> String

    /// Export multiple events
    func export(events: [(StoredEvent, [StoredAttendee], StoredCalendar?)], query: String?) -> String
}

// MARK: - Date Formatter

/// Shared date formatting utilities for export
public enum CalendarDateFormatter {
    /// Format a UTC timestamp for JSON/ISO output
    public static func formatISO(_ timestamp: Int, isAllDay: Bool = false) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        if isAllDay {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: date)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Format a UTC timestamp for human-readable output
    public static func formatReadable(_ timestamp: Int, isAllDay: Bool = false, timezone: String? = nil) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))

        let formatter = DateFormatter()
        if isAllDay {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }

        // Use specified timezone or current
        if let tz = timezone, let timeZone = TimeZone(identifier: tz) {
            formatter.timeZone = timeZone
        } else {
            formatter.timeZone = TimeZone.current
        }

        return formatter.string(from: date)
    }

    /// Format a date range
    public static func formatRange(
        start: Int,
        end: Int,
        isAllDay: Bool,
        timezone: String? = nil
    ) -> String {
        let startStr = formatReadable(start, isAllDay: isAllDay, timezone: timezone)
        let endStr = formatReadable(end, isAllDay: isAllDay, timezone: timezone)

        // For same-day events, only show end time
        let startDate = Date(timeIntervalSince1970: TimeInterval(start))
        let endDate = Date(timeIntervalSince1970: TimeInterval(end))
        let calendar = Calendar.current

        if isAllDay {
            if calendar.isDate(startDate, inSameDayAs: endDate) {
                return startStr
            }
            return "\(startStr) - \(endStr)"
        }

        if calendar.isDate(startDate, inSameDayAs: endDate) {
            // Same day: show date once, both times
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            if let tz = timezone, let timeZone = TimeZone(identifier: tz) {
                dateFormatter.timeZone = timeZone
            }

            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            if let tz = timezone, let timeZone = TimeZone(identifier: tz) {
                timeFormatter.timeZone = timeZone
            }

            let dateStr = dateFormatter.string(from: startDate)
            let startTime = timeFormatter.string(from: startDate)
            let endTime = timeFormatter.string(from: endDate)

            return "\(dateStr) \(startTime) - \(endTime)"
        }

        return "\(startStr) - \(endStr)"
    }
}

// MARK: - Markdown Exporter

/// Exports calendar events to Markdown with YAML frontmatter (Obsidian-compatible)
public struct MarkdownCalendarExporter: CalendarExporter {
    public init() {}

    public func export(event: StoredEvent, attendees: [StoredAttendee], calendar: StoredCalendar?) -> String {
        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("id: \(event.id)")
        lines.append("type: calendar-event")
        if let calendar = calendar {
            lines.append("calendar: \(escapeYaml(calendar.title))")
        }
        lines.append("calendar_id: \(event.calendarId)")
        lines.append("start: \(CalendarDateFormatter.formatISO(event.startDateUtc, isAllDay: event.isAllDay))")
        lines.append("end: \(CalendarDateFormatter.formatISO(event.endDateUtc, isAllDay: event.isAllDay))")
        lines.append("is_all_day: \(event.isAllDay)")

        if let location = event.location {
            lines.append("location: \(escapeYaml(location))")
        }
        if let status = event.status {
            lines.append("status: \(status)")
        }
        if event.recurrenceRule != nil || event.masterEventId != nil {
            lines.append("is_recurring: true")
        }
        if let url = event.url {
            lines.append("url: \(escapeYaml(url))")
        }

        // Attendees in frontmatter
        if !attendees.isEmpty {
            lines.append("attendees:")
            for attendee in attendees {
                let name = attendee.name ?? "Unknown"
                let email = attendee.email ?? ""
                let status = attendee.responseStatus ?? "unknown"
                let role = attendee.isOrganizer ? " (organizer)" : ""
                lines.append("  - name: \(escapeYaml(name))")
                if !email.isEmpty {
                    lines.append("    email: \(email)")
                }
                lines.append("    status: \(status)\(role)")
            }
        }

        lines.append("---")
        lines.append("")

        // Title
        let title = event.summary ?? "Untitled Event"
        lines.append("# \(title)")
        lines.append("")

        // Time
        let timeStr = CalendarDateFormatter.formatRange(
            start: event.startDateUtc,
            end: event.endDateUtc,
            isAllDay: event.isAllDay,
            timezone: event.startTimezone
        )
        lines.append("**When:** \(timeStr)")

        // Location
        if let location = event.location, !location.isEmpty {
            lines.append("")
            lines.append("**Where:** \(location)")
        }

        // Calendar
        if let calendar = calendar {
            lines.append("")
            lines.append("**Calendar:** \(calendar.title)")
        }

        // Attendees section
        if !attendees.isEmpty {
            lines.append("")
            lines.append("## Attendees")
            lines.append("")
            for attendee in attendees {
                let name = attendee.name ?? "Unknown"
                let statusEmoji = attendeeStatusEmoji(attendee.responseStatus)
                let role = attendee.isOrganizer ? " _organizer_" : ""
                let optional = attendee.isOptional ? " _(optional)_" : ""
                lines.append("- \(statusEmoji) \(name)\(role)\(optional)")
            }
        }

        // Description
        if let description = event.eventDescription, !description.isEmpty {
            lines.append("")
            lines.append("## Description")
            lines.append("")
            lines.append(description)
        }

        // URL
        if let url = event.url {
            lines.append("")
            lines.append("**Link:** [\(url)](\(url))")
        }

        return lines.joined(separator: "\n")
    }

    public func export(events: [(StoredEvent, [StoredAttendee], StoredCalendar?)], query: String?) -> String {
        var lines: [String] = []

        lines.append("# Calendar Events")
        if let query = query {
            lines.append("")
            lines.append("_Query: \(query)_")
        }
        lines.append("")
        lines.append("Total: \(events.count) event(s)")
        lines.append("")
        lines.append("---")

        for (event, attendees, calendar) in events {
            lines.append("")
            lines.append(exportSummary(event: event, attendees: attendees, calendar: calendar))
            lines.append("")
            lines.append("---")
        }

        return lines.joined(separator: "\n")
    }

    /// Export a brief summary for list view
    private func exportSummary(event: StoredEvent, attendees: [StoredAttendee], calendar: StoredCalendar?) -> String {
        var lines: [String] = []

        let title = event.summary ?? "Untitled Event"
        lines.append("## \(title)")

        let timeStr = CalendarDateFormatter.formatRange(
            start: event.startDateUtc,
            end: event.endDateUtc,
            isAllDay: event.isAllDay,
            timezone: event.startTimezone
        )
        lines.append("When: \(timeStr)")

        if let location = event.location, !location.isEmpty {
            lines.append("Where: \(location)")
        }

        if let calendar = calendar {
            lines.append("Calendar: \(calendar.title)")
        }

        if !attendees.isEmpty {
            let names = attendees.prefix(3).compactMap { $0.name }.joined(separator: ", ")
            let more = attendees.count > 3 ? " (+\(attendees.count - 3) more)" : ""
            lines.append("Attendees: \(names)\(more)")
        }

        lines.append("")
        lines.append("ID: `\(event.id)`")

        return lines.joined(separator: "\n")
    }

    private func escapeYaml(_ value: String) -> String {
        // Quote strings containing special YAML characters
        if value.contains(":") || value.contains("#") ||
           value.contains("\"") || value.contains("'") ||
           value.hasPrefix("-") || value.hasPrefix("[") ||
           value.hasPrefix("{") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func attendeeStatusEmoji(_ status: String?) -> String {
        switch status?.lowercased() {
        case "accepted": return "[x]"
        case "declined": return "[-]"
        case "tentative": return "[?]"
        case "needs-action", "needsaction": return "[ ]"
        default: return "-"
        }
    }
}

// MARK: - JSON Exporter

/// Exports calendar events to JSON with ClaudEA envelope format
public struct JSONCalendarExporter: CalendarExporter {
    private let encoder: JSONEncoder

    public init(prettyPrinted: Bool = true) {
        encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
    }

    public func export(event: StoredEvent, attendees: [StoredAttendee], calendar: StoredCalendar?) -> String {
        let exportable = createExportable(event: event, attendees: attendees, calendar: calendar)
        let envelope = CalendarExportEnvelope(items: [exportable])

        do {
            let data = try encoder.encode(envelope)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to encode: \(error.localizedDescription)\"}"
        }
    }

    public func export(events: [(StoredEvent, [StoredAttendee], StoredCalendar?)], query: String?) -> String {
        let items = events.map { createExportable(event: $0.0, attendees: $0.1, calendar: $0.2) }
        let envelope = CalendarExportEnvelope(query: query, items: items)

        do {
            let data = try encoder.encode(envelope)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to encode: \(error.localizedDescription)\"}"
        }
    }

    private func createExportable(event: StoredEvent, attendees: [StoredAttendee], calendar: StoredCalendar?) -> ExportableEvent {
        let exportableAttendees = attendees.map { attendee in
            ExportableAttendee(
                name: attendee.name,
                email: attendee.email,
                responseStatus: attendee.responseStatus,
                isOrganizer: attendee.isOrganizer
            )
        }

        return ExportableEvent(
            id: event.id,
            title: event.summary,
            calendar: calendar?.title ?? "Unknown",
            calendarId: event.calendarId,
            start: CalendarDateFormatter.formatISO(event.startDateUtc, isAllDay: event.isAllDay),
            end: CalendarDateFormatter.formatISO(event.endDateUtc, isAllDay: event.isAllDay),
            isAllDay: event.isAllDay,
            location: event.location,
            description: event.eventDescription,
            url: event.url,
            status: event.status,
            isRecurring: event.recurrenceRule != nil || event.masterEventId != nil,
            attendees: exportableAttendees
        )
    }
}

// MARK: - ICS Exporter

/// Exports calendar events to ICS format (RFC 5545)
public struct ICSCalendarExporter: CalendarExporter {
    public init() {}

    public func export(event: StoredEvent, attendees: [StoredAttendee], calendar: StoredCalendar?) -> String {
        let icsEvent = createICSEvent(event: event, attendees: attendees)
        var icsCalendar = ICalendar()
        icsCalendar.events = [icsEvent]
        return icsCalendar.vEncoded
    }

    public func export(events: [(StoredEvent, [StoredAttendee], StoredCalendar?)], query: String?) -> String {
        let icsEvents = events.map { createICSEvent(event: $0.0, attendees: $0.1) }
        var icsCalendar = ICalendar()
        icsCalendar.events = icsEvents
        return icsCalendar.vEncoded
    }

    private func createICSEvent(event: StoredEvent, attendees: [StoredAttendee]) -> ICalendarEvent {
        // Dates
        let startDate = Date(timeIntervalSince1970: TimeInterval(event.startDateUtc))
        let endDate = Date(timeIntervalSince1970: TimeInterval(event.endDateUtc))

        let dtstart: ICalendarDate
        let dtend: ICalendarDate

        if event.isAllDay {
            // All-day events use DATE format, not DATE-TIME
            dtstart = .dateOnly(startDate)
            dtend = .dateOnly(endDate)
        } else {
            dtstart = .dateTime(startDate)
            dtend = .dateTime(endDate)
        }

        // Create event
        var icsEvent = ICalendarEvent(
            dtstamp: Date(),
            uid: event.externalId ?? event.id,
            created: event.createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            description: event.eventDescription,
            dtstart: dtstart,
            lastModified: event.updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            location: event.location,
            status: event.status?.uppercased(),
            summary: event.summary ?? "Untitled",
            url: event.url.flatMap { URL(string: $0) },
            dtend: dtend
        )

        // Set all-day flag for Microsoft compatibility
        if event.isAllDay {
            icsEvent.xMicrosoftCDOAllDayEvent = true
        }

        return icsEvent
    }
}

// MARK: - Factory

/// Factory for creating exporters by format
public enum CalendarExporterFactory {
    public static func create(format: CalendarExportFormat) -> CalendarExporter {
        switch format {
        case .markdown:
            return MarkdownCalendarExporter()
        case .json:
            return JSONCalendarExporter()
        case .ics:
            return ICSCalendarExporter()
        }
    }
}
