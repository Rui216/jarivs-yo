//
//  UpNextCard.swift
//  JARVIS
//
//  The next calendar event with the rest of today's schedule below it.
//  Reads the SwiftData cache so the card renders before EventKit has
//  answered, and offers the permission request when access is missing.
//

import SwiftUI
import SwiftData

/// Next event and the rest of today's schedule.
struct UpNextCard: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \CalendarEventItem.startDate, order: .forward) private var cachedEvents: [CalendarEventItem]

    @State private var isRequestingAccess = false

    var body: some View {
        JarvisCard(title: "Up Next", symbolName: "calendar.badge.clock") {
            if environment.calendarAutomation.calendarAccessState != .granted {
                accessPrompt
            } else if upcoming.isEmpty {
                EmptyStateView(
                    symbolName: "calendar",
                    title: "Nothing scheduled",
                    message: environment.calendarStore.lastSyncDate == nil
                        ? "Refreshing the calendar."
                        : "The rest of today is clear."
                )
            } else {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                    if let first = upcoming.first {
                        featuredEvent(first)
                    }
                    if upcoming.count > 1 {
                        Divider().overlay(JarvisTheme.Palette.stroke)
                        VStack(spacing: JarvisTheme.Spacing.tight) {
                            ForEach(upcoming.dropFirst().prefix(4)) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
        } accessory: {
            Button {
                Task { await environment.calendarStore.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(JarvisTheme.Palette.textTertiary)
            .help("Refresh the calendar")
        }
    }

    // MARK: - Pieces

    private func featuredEvent(_ event: CalendarEventItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: JarvisTheme.Spacing.tight) {
                StatusChip(
                    text: event.isInProgress ? "In progress" : JarvisTimeFormat.relative(from: event.startDate),
                    symbolName: event.isInProgress ? "play.fill" : "clock",
                    tint: event.isInProgress ? JarvisTheme.Palette.success : JarvisTheme.Palette.accent
                )
                if !event.calendarName.isEmpty {
                    StatusChip(text: event.calendarName, tint: JarvisTheme.Palette.textSecondary)
                }
            }

            Text(event.title)
                .font(JarvisTheme.Typography.title(19))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(timeRange(for: event))
                .font(JarvisTheme.Typography.caption(11))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)

            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin.and.ellipse")
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(JarvisTheme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .fill(JarvisTheme.Palette.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .strokeBorder(JarvisTheme.Palette.accent.opacity(0.28), lineWidth: 1)
        )
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.tight) {
            VStack(spacing: 2) {
                Text(JarvisTimeFormat.shortTime(event.startDate))
                    .font(JarvisTheme.Typography.caption(11))
                    .monospacedDigit()
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                Text(JarvisTimeFormat.shortTime(event.endDate))
                    .font(JarvisTheme.Typography.caption(9))
                    .monospacedDigit()
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(JarvisTheme.Typography.headline(12))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    .lineLimit(1)
                if !event.calendarName.isEmpty {
                    Text(event.calendarName)
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            Text("Calendar access is off")
                .font(JarvisTheme.Typography.headline(13))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Text("JARVIS reads your calendars to show the schedule here and to create events you ask for. You can also use the assistant to take care of it.")
                .font(JarvisTheme.Typography.caption(11))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(isRequestingAccess ? "Requesting..." : "Grant calendar access") {
                isRequestingAccess = true
                Task {
                    _ = await environment.requestCalendarAccess()
                    isRequestingAccess = false
                }
            }
            .buttonStyle(.jarvisPrimary)
            .disabled(isRequestingAccess)
        }
    }

    // MARK: - Data

    /// Today's remaining events, in start order.
    private var upcoming: [CalendarEventItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: environment.clock.now)
        let end = start.addingTimeInterval(86_400)
        return cachedEvents.filter { $0.startDate >= start && $0.startDate < end && $0.endDate >= environment.clock.now }
    }

    private func timeRange(for event: CalendarEventItem) -> String {
        if event.isAllDay { return "All day" }
        let start = JarvisTimeFormat.shortTime(event.startDate)
        let end = JarvisTimeFormat.shortTime(event.endDate)
        let duration = event.durationMinutes
        return "\(start) to \(end) - \(duration) min"
    }
}
