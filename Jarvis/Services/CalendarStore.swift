//
//  CalendarStore.swift
//  JARVIS
//
//  Keeps a local SwiftData mirror of the user's calendar so the
//  dashboard renders instantly and keeps working when EventKit access is
//  missing. EventKit remains the source of truth; this type only caches.
//

import Foundation
import SwiftData
import os

/// One cached event from the SwiftData mirror.
struct CachedEvent: Identifiable, Equatable, Sendable {
    /// Event identifier from EventKit.
    let id: String
    /// Event title.
    var title: String
    /// Start date.
    var start: Date
    /// End date.
    var end: Date
    /// Whether the event lasts all day.
    var isAllDay: Bool
    /// Calendar name.
    var calendarName: String

    /// Converts a cached event into the snapshot type used by automation.
    var snapshot: CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: "",
            calendarName: calendarName
        )
    }
}

/// Synchronizes EventKit events into SwiftData.
@MainActor
@Observable
final class CalendarStore {

    /// Number of days of events kept in the cache.
    static let cacheHorizonDays = 30

    private let context: ModelContext
    private let automation: CalendarAutomation
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Calendar")

    /// When the cache was last refreshed.
    private(set) var lastSyncDate: Date?

    /// Last synchronization error, shown in the calendar screen.
    private(set) var lastErrorMessage: String?

    /// Whether a refresh is in flight.
    private(set) var isSyncing = false

    init(context: ModelContext, automation: CalendarAutomation) {
        self.context = context
        self.automation = automation
    }

    /// True when calendar access has been granted.
    var hasAccess: Bool {
        automation.calendarAccessState == .granted
    }

    /// Re-reads the calendar and updates the cache.
    ///
    /// Does nothing when access has not been granted so the interface can
    /// show the permission prompt instead of an empty list.
    func refresh() async {
        guard hasAccess else {
            lastErrorMessage = nil
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: Self.cacheHorizonDays, to: start) else {
            return
        }

        let snapshots = automation.events(from: start, to: end, limit: 500)
        upsert(snapshots)
        pruneEvents(before: start, after: end)

        lastSyncDate = Date()
        lastErrorMessage = nil
        logger.debug("Calendar cache refreshed with \(snapshots.count, privacy: .public) events")
    }

    /// Inserts or updates cached events.
    func upsert(_ snapshots: [CalendarEventSnapshot]) {
        guard !snapshots.isEmpty else { return }

        for snapshot in snapshots {
            let identifier = snapshot.id
            var descriptor = FetchDescriptor<CalendarEventItem>(
                predicate: #Predicate { $0.eventIdentifier == identifier }
            )
            descriptor.fetchLimit = 1

            if let existing = (try? context.fetch(descriptor))?.first {
                existing.title = snapshot.title
                existing.startDate = snapshot.start
                existing.endDate = snapshot.end
                existing.isAllDay = snapshot.isAllDay
                existing.location = snapshot.location
                existing.calendarName = snapshot.calendarName
            } else {
                context.insert(CalendarEventItem(
                    eventIdentifier: snapshot.id,
                    title: snapshot.title,
                    startDate: snapshot.start,
                    endDate: snapshot.end,
                    isAllDay: snapshot.isAllDay,
                    location: snapshot.location,
                    calendarName: snapshot.calendarName
                ))
            }
        }

        do {
            try context.save()
        } catch {
            logger.error("Calendar cache save failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Events cached for today, ordered by start time.
    func todaysEvents() -> [CachedEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = start.addingTimeInterval(86_400)
        return cachedEvents(from: start, to: end)
    }

    /// The next event starting after the given date within the cache window.
    func nextEvent(after date: Date = Date()) -> CachedEvent? {
        let end = date.addingTimeInterval(TimeInterval(Self.cacheHorizonDays) * 86_400)
        return cachedEvents(from: date, to: end).first
    }

    /// Events in a date range, ordered by start time.
    func cachedEvents(from start: Date, to end: Date) -> [CachedEvent] {
        let descriptor = FetchDescriptor<CalendarEventItem>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.map { item in
            CachedEvent(
                id: item.eventIdentifier,
                title: item.title,
                start: item.startDate,
                end: item.endDate,
                isAllDay: item.isAllDay,
                calendarName: item.calendarName
            )
        }
    }

    /// Events per day for the mini calendar month view.
    func eventCountsForMonth(containing date: Date) -> [Date: Int] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [:] }
        let events = cachedEvents(from: interval.start, to: interval.end)
        var counts: [Date: Int] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.start)
            counts[day, default: 0] += 1
        }
        return counts
    }

    // MARK: - Internals

    /// Removes cached events outside the cache window.
    private func pruneEvents(before start: Date, after end: Date) {
        let descriptor = FetchDescriptor<CalendarEventItem>(
            predicate: #Predicate { $0.startDate < start || $0.startDate >= end }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        for item in stale {
            context.delete(item)
        }
        try? context.save()
    }
}
