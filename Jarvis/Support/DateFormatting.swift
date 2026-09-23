//
//  DateFormatting.swift
//  JARVIS
//
//  Date and duration helpers shared by the dashboard, the assistant
//  tools, and the calendar views. Models from the network and from the
//  model itself arrive as ISO 8601 strings, so parsing is deliberately
//  tolerant of the shapes providers actually emit.
//

import Foundation

/// Parses date strings coming from models, files, and form fields.
enum JarvisDateParser {

    private static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateTimeNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let spaceSeparated: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Parses an ISO 8601 string, falling back to common local formats.
    ///
    /// A date without a time component is interpreted at the start of that
    /// day in the user's calendar. Timestamps without a zone are read as
    /// local time, which matches how people write times in a chat.
    static func date(from string: String?) -> Date? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if let date = internetDateTime.date(from: raw) { return date }
        if let date = internetDateTimeNoFraction.date(from: raw) { return date }

        // ISO 8601 without a zone, for example 2026-03-14T09:00:00.
        if let date = localISOFormatter().date(from: raw) { return date }
        if let date = spaceSeparated.date(from: raw) { return date }
        if let date = dateOnly.date(from: raw) { return date }

        // Relative wording the model sometimes produces.
        return relativeDate(from: raw)
    }

    private static func localISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        return formatter
    }

    /// Handles short relative phrases such as "tomorrow 9am" or "in 2 days".
    private static func relativeDate(from raw: String) -> Date? {
        let lowered = raw.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lowered.contains("tomorrow") {
            guard let base = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return applyingTimeWord(from: lowered, to: base, calendar: calendar)
        }
        if lowered.contains("today") {
            return applyingTimeWord(from: lowered, to: now, calendar: calendar)
        }
        if lowered.hasPrefix("in ") {
            let fragments = lowered.dropFirst(3).split(separator: " ")
            if let amount = Int(fragments.first ?? ""), fragments.count >= 2 {
                let unit = fragments[1]
                if unit.hasPrefix("min") { return calendar.date(byAdding: .minute, value: amount, to: now) }
                if unit.hasPrefix("h") { return calendar.date(byAdding: .hour, value: amount, to: now) }
                if unit.hasPrefix("d") { return calendar.date(byAdding: .day, value: amount, to: now) }
                if unit.hasPrefix("w") { return calendar.date(byAdding: .weekOfYear, value: amount, to: now) }
            }
        }
        return nil
    }

    /// Applies "9am" or "14:30" style wording to a base date.
    private static func applyingTimeWord(from raw: String, to base: Date, calendar: Calendar) -> Date? {
        guard let range = raw.range(of: "[0-9]{1,2}(:[0-9]{2})?\\s?(am|pm)?", options: .regularExpression) else {
            return base
        }
        let token = raw[range].replacingOccurrences(of: " ", with: "")
        let isPM = token.hasSuffix("pm")
        let isAM = token.hasSuffix("am")
        let timePart = token.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "")
        let pieces = timePart.split(separator: ":")
        guard let hourValue = Int(pieces.first ?? "") else { return base }
        var hour = hourValue
        let minute = pieces.count > 1 ? (Int(pieces[1]) ?? 0) : 0
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }
}

/// Formats durations and relative times for the interface.
enum JarvisTimeFormat {

    /// Clock string for a duration in seconds, for example "24:59".
    static func clock(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let remainder = clamped % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    /// Short relative description such as "in 12 min" or "in 3 h".
    static func relative(from date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        let isFuture = interval >= 0
        let magnitude = abs(interval)

        let description: String
        switch magnitude {
        case ..<60:
            return isFuture ? "now" : "just now"
        case ..<3_600:
            description = "\(Int(magnitude / 60)) min"
        case ..<86_400:
            description = "\(Int(magnitude / 3_600)) h"
        default:
            description = "\(Int(magnitude / 86_400)) d"
        }
        return isFuture ? "in \(description)" : "\(description) ago"
    }

    /// Time of day for an event, for example "09:30".
    static func shortTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Day and month, for example "Mar 14".
    static func shortDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Full weekday label, for example "Saturday".
    static func weekday(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
