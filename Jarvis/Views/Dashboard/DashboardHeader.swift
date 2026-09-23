//
//  DashboardHeader.swift
//  JARVIS
//
//  Greeting with the user name, the live date, the local weather, and a
//  compact summary of the day.
//

import SwiftUI
import SwiftData

/// Header row above the dashboard grid.
struct DashboardHeader: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \HomeworkItem.dueDate, order: .forward) private var homework: [HomeworkItem]
    @Query(sort: \CalendarEventItem.startDate, order: .forward) private var cachedEvents: [CalendarEventItem]

    var body: some View {
        HStack(alignment: .center, spacing: JarvisTheme.Spacing.loose) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(environment.clock.greeting), \(displayName)")
                    .font(JarvisTheme.Typography.display(26))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)

                HStack(spacing: JarvisTheme.Spacing.tight) {
                    Text(environment.clock.dateText)
                        .font(JarvisTheme.Typography.body(12))
                        .foregroundStyle(JarvisTheme.Palette.textSecondary)
                    Text(environment.clock.shortTimeText)
                        .font(JarvisTheme.Typography.caption(12))
                        .monospacedDigit()
                        .foregroundStyle(JarvisTheme.Palette.accent)
                }

                summaryChips
            }

            Spacer(minLength: JarvisTheme.Spacing.regular)

            WeatherChip()
        }
    }

    // MARK: - Pieces

    private var displayName: String {
        let name = environment.settings.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "there" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var summaryChips: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            StatusChip(
                text: "\(openTaskCount) open task(s)",
                symbolName: "checklist",
                tint: JarvisTheme.Palette.accent
            )
            StatusChip(
                text: "\(upcomingHomeworkCount) homework due",
                symbolName: "book.closed",
                tint: JarvisTheme.Palette.violet
            )
            StatusChip(
                text: "\(eventsTodayCount) event(s) today",
                symbolName: "calendar",
                tint: JarvisTheme.Palette.info
            )
        }
    }

    private var openTaskCount: Int {
        tasks.filter { !$0.isDone }.count
    }

    private var upcomingHomeworkCount: Int {
        homework.filter { !$0.isDone && $0.daysRemaining <= 7 }.count
    }

    private var eventsTodayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: environment.clock.now)
        let end = start.addingTimeInterval(86_400)
        return cachedEvents.filter { $0.startDate >= start && $0.startDate < end }.count
    }
}

/// Weather readout for the header.
struct WeatherChip: View {

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: JarvisTheme.Spacing.regular) {
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(iconColor)
                .jarvisGlow(iconColor, radius: 10, opacity: 0.35)

            VStack(alignment: .leading, spacing: 2) {
                Text(temperatureText)
                    .font(JarvisTheme.Typography.title(18))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                Text(subtitle)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, JarvisTheme.Spacing.loose)
        .padding(.vertical, JarvisTheme.Spacing.regular)
        .jarvisCard(elevated: true)
        .task {
            await environment.weather.refresh(settings: environment.settings)
        }
    }

    private var iconName: String {
        guard let snapshot = environment.weather.snapshot else { return "cloud.sun" }
        return snapshot.condition.symbolName
    }

    private var iconColor: Color {
        guard let snapshot = environment.weather.snapshot else { return JarvisTheme.Palette.textTertiary }
        return snapshot.condition.tint
    }

    private var temperatureText: String {
        guard let snapshot = environment.weather.snapshot else { return "--" }
        return snapshot.temperatureText(unit: environment.settings.temperatureUnit)
    }

    private var subtitle: String {
        switch environment.weather.status {
        case .notConfigured:
            return "Add a location in Settings"
        case .loading:
            return "Refreshing"
        case .failed(let message):
            return message
        case .ready:
            guard let snapshot = environment.weather.snapshot else { return "No reading" }
            let wind = Int(snapshot.windKph.rounded())
            return "\(snapshot.locationName) - \(snapshot.condition.summary) - wind \(wind) km/h"
        }
    }
}
