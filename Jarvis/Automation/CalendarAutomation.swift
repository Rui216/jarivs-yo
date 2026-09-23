//
//  CalendarAutomation.swift
//  JARVIS
//
//  EventKit access for calendar events and reminders. Reads use the
//  store directly; writes go through EventKit with full access granted by
//  the user. Access state is reported so the UI can explain what is
//  missing instead of failing silently.
//

import Foundation
import EventKit
import os

/// Value type snapshot of a calendar event.
struct CalendarEventSnapshot: Identifiable, Equatable, Sendable {
    /// Stable identifier from the event store.
    let id: String
    /// Event title.
    var title: String
    /// Start date.
    var start: Date
    /// End date.
    var end: Date
    /// Whether the event spans the whole day.
    var isAllDay: Bool
    /// Optional location text.
    var location: String
    /// Calendar the event belongs to.
    var calendarName: String

    /// Duration in minutes.
    var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }
}

/// Reads and writes calendar events and reminders.
@MainActor
final class CalendarAutomation {

    private let store: EKEventStore
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Calendar")

    init(store: EKEventStore) {
        self.store = store
    }

    // MARK: - Access

    /// Current calendar authorization state.
    var calendarAccessState: PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess, .writeOnly: return .granted
        default: return .unknown
        }
    }

    /// Current reminders authorization state.
    var remindersAccessState: PermissionState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess, .writeOnly: return .granted
        default: return .unknown
        }
    }

    /// Requests calendar access, prompting once if needed.
    func requestCalendarAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Requests reminders access, prompting once if needed.
    func requestRemindersAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            logger.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Reading

    /// Names of calendars the user can write to.
    func writableCalendarNames() -> [String] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map(\.title)
            .sorted()
    }

    /// Events between two dates, sorted by start time.
    func events(from start: Date, to end: Date, limit: Int = 200) -> [CalendarEventSnapshot] {
        guard calendarAccessState == .granted else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let matches = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        return matches.prefix(limit).map { event in
            CalendarEventSnapshot(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Untitled event",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location ?? "",
                calendarName: event.calendar?.title ?? ""
            )
        }
    }

    /// Events for the rest of today plus the next `days` days.
    func upcomingEvents(days: Int, limit: Int = 200) -> [CalendarEventSnapshot] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: max(1, days), to: start) else {
            return []
        }
        return events(from: start, to: end, limit: limit)
    }

    /// The next event starting after now, if any within the given window.
    func nextEvent(withinHours hours: Int = 48) -> CalendarEventSnapshot? {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .hour, value: hours, to: now) else { return nil }
        return events(from: now, to: end, limit: 50).first
    }

    // MARK: - Writing

    /// Creates a calendar event and returns the stored snapshot.
    ///
    /// Throws `AutomationError.calendarAccessDenied` when access is missing
    /// and `AutomationError.calendarOperationFailed` when EventKit refuses
    /// the save.
    @discardableResult
    func createEvent(
        title: String,
        start: Date,
        end: Date,
        notes: String? = nil,
        location: String? = nil,
        calendarName: String? = nil,
        alarmMinutesBefore: Int? = 10
    ) async throws -> CalendarEventSnapshot {
        guard calendarAccessState == .granted else {
            throw AutomationError.calendarAccessDenied
        }
        guard end > start else {
            throw AutomationError.calendarOperationFailed("the end time must be after the start time.")
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        if let notes, !notes.isEmpty { event.notes = notes }
        if let location, !location.isEmpty { event.location = location }

        if let calendarName, let match = bestMatch(for: calendarName, in: store.calendars(for: .event)) {
            event.calendar = match
        } else {
            guard let fallback = store.defaultCalendarForNewEvents else {
                throw AutomationError.calendarOperationFailed("no writable calendar is available.")
            }
            event.calendar = fallback
        }

        if let alarmMinutesBefore {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-60 * alarmMinutesBefore)))
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            logger.error("Saving the event failed: \(error.localizedDescription, privacy: .public)")
            throw AutomationError.calendarOperationFailed(error.localizedDescription)
        }

        logger.debug("Created calendar event with title length \(title.count, privacy: .public)")

        return CalendarEventSnapshot(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location ?? "",
            calendarName: event.calendar?.title ?? ""
        )
    }

    /// Creates a reminder and returns its title when saved.
    @discardableResult
    func createReminder(
        title: String,
        dueDate: Date? = nil,
        notes: String? = nil,
        listName: String? = nil
    ) async throws -> String {
        guard remindersAccessState == .granted else {
            throw AutomationError.remindersAccessDenied
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        if let notes, !notes.isEmpty { reminder.notes = notes }

        if let listName, let match = bestMatch(for: listName, in: store.calendars(for: .reminder)) {
            reminder.calendar = match
        } else {
            guard let fallback = store.defaultCalendarForNewReminders() else {
                throw AutomationError.calendarOperationFailed("no writable reminder list is available.")
            }
            reminder.calendar = fallback
        }

        if let dueDate {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = components
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            logger.error("Saving the reminder failed: \(error.localizedDescription, privacy: .public)")
            throw AutomationError.calendarOperationFailed(error.localizedDescription)
        }

        return title
    }

    /// Picks the calendar or reminder list that best matches a spoken name.
    ///
    /// An exact case insensitive match wins, then a name that contains the
    /// request, then a request that contains the name. The shortest candidate
    /// is preferred so "Home" does not select "Home and Family Errands" when
    /// both contain the word.
    private func bestMatch(for name: String, in candidates: [EKCalendar]) -> EKCalendar? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }

        if let exact = candidates.first(where: { $0.title.compare(wanted, options: .caseInsensitive) == .orderedSame }) {
            return exact
        }

        let partial = candidates
            .filter {
                $0.title.range(of: wanted, options: .caseInsensitive) != nil
                    || wanted.range(of: $0.title, options: .caseInsensitive) != nil
            }
            .sorted { $0.title.count < $1.title.count }

        return partial.first
    }
}
