//
//  ClockCard.swift
//  JARVIS
//
//  The large clock card: seconds, full date, and a one line summary of
//  the day built from the task list, the calendar cache, and the focus
//  timer.
//

import SwiftUI
import SwiftData

/// Large clock with the current date.
struct ClockCard: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \CalendarEventItem.startDate, order: .forward) private var cachedEvents: [CalendarEventItem]

    var body: some View {
        JarvisCard(title: "Local time", symbolName: "clock", isElevated: true) {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
                Text(environment.clock.timeText)
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    .jarvisGlow(radius: 22, opacity: 0.22)
                    .contentTransition(.numericText())

                Text(environment.clock.dateText)
                    .font(JarvisTheme.Typography.headline(14))
                    .foregroundStyle(JarvisTheme.Palette.accent)

                Text(summaryLine)
                    .font(JarvisTheme.Typography.body(12))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
                    .padding(.top, 2)

                Divider()
                    .overlay(JarvisTheme.Palette.stroke)
                    .padding(.vertical, 6)

                HStack(spacing: JarvisTheme.Spacing.section) {
                    statColumn(value: "\(eventsTodayCount)", label: "Events today")
                    statColumn(value: "\(focusMinutes)", label: "Focus minutes")
                    statColumn(value: SystemMetrics.formatUptime(environment.monitor.metrics.uptimeSeconds), label: "Uptime")
                }
            } accessory: {
                StatusChip(
                    text: environment.clock.isTicking ? "Live" : "Paused",
                    symbolName: "dot.radiowaves.left.and.right",
                    tint: environment.clock.isTicking ? JarvisTheme.Palette.success : JarvisTheme.Palette.textTertiary
                )
            }
        }
    }

    // MARK: - Pieces

    private func statColumn(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(JarvisTheme.Typography.title(18))
                .monospacedDigit()
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Text(label.uppercased())
                .font(JarvisTheme.Typography.caption(9))
                .tracking(0.8)
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
        }
    }

    private var summaryLine: String {
        let now = environment.clock.now
        let horizon = now.addingTimeInterval(12 * 3_600)
        if let next = cachedEvents.first(where: { $0.startDate >= now && $0.startDate <= horizon }) {
            return "Next: \(next.title) at \(JarvisTimeFormat.shortTime(next.startDate))."
        }
        if environment.calendarAutomation.calendarAccessState == .granted {
            return "Nothing on the calendar for the rest of today."
        }
        return "Grant calendar access in Settings to see the schedule here."
    }

    private var eventsTodayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: environment.clock.now)
        let end = start.addingTimeInterval(86_400)
        return cachedEvents.filter { $0.startDate >= start && $0.startDate < end }.count
    }

    private var focusMinutes: Int {
        environment.focusTimer.focusedSecondsToday / 60
    }
}
