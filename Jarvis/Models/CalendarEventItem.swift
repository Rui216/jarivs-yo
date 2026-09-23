//
//  CalendarEventItem.swift
//  JARVIS
//
//  Local mirror of a calendar event. EventKit remains the source of
//  truth, but a cached copy lets the dashboard render "Up Next" and the
//  mini calendar instantly, and keeps working when calendar access has
//  not been granted yet.
//

import Foundation
import SwiftData

/// A cached calendar event.
@Model
final class CalendarEventItem {
    /// Stable identifier of the source event, used to update instead of duplicating.
    var eventIdentifier: String
    /// Event title.
    var title: String
    /// Event start.
    var startDate: Date
    /// Event end.
    var endDate: Date
    /// Whether the event lasts all day.
    var isAllDay: Bool
    /// Optional location string from the calendar store.
    var location: String
    /// Name of the calendar the event belongs to.
    var calendarName: String

    /// Not persisted. Duration in minutes.
    var durationMinutes: Int {
        Int(endDate.timeIntervalSince(startDate) / 60)
    }

    /// Not persisted. True when the event is running right now.
    var isInProgress: Bool {
        let now = Date()
        return startDate <= now && endDate >= now
    }

    init(
        eventIdentifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String = "",
        calendarName: String = ""
    ) {
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.calendarName = calendarName
    }
}
