//
//  MiniCalendarCard.swift
//  JARVIS
//
//  Month grid with a marker on days that hold events, built from the
//  cached calendar so it stays instant.
//

import SwiftUI
import SwiftData

/// Compact month grid for the dashboard.
struct MiniCalendarCard: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \CalendarEventItem.startDate, order: .forward) private var cachedEvents: [CalendarEventItem]

    @State private var displayedMonth = Date()

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4, alignment: .center),
        count: 7
    )

    var body: some View {
        JarvisCard(title: "Calendar", symbolName: "calendar") {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
                monthHeader
                weekdayHeader
                monthGrid

                Divider().overlay(JarvisTheme.Palette.stroke)

                HStack(spacing: 6) {
                    StatusChip(
                        text: "\(eventsThisMonth) event(s) this month",
                        tint: JarvisTheme.Palette.info
                    )
                    if environment.calendarAutomation.calendarAccessState != .granted {
                        StatusChip(
                            text: "Access off",
                            symbolName: "lock",
                            tint: JarvisTheme.Palette.warning
                        )
                    }
                }
            }
        } accessory: {
            Button {
                environment.appState.destination = .calendar
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(JarvisTheme.Palette.textTertiary)
            .help("Open the calendar screen")
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack(spacing: 6) {
            Text(monthTitle)
                .font(JarvisTheme.Typography.headline(13))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)

            Spacer(minLength: 0)

            monthButton(symbolName: "chevron.left") { shiftMonth(by: -1) }
            monthButton(symbolName: "arrow.counterclockwise") { displayedMonth = Date() }
            monthButton(symbolName: "chevron.right") { shiftMonth(by: 1) }
        }
    }

    private func monthButton(symbolName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(JarvisTheme.Palette.canvas.opacity(0.6))
                )
                .overlay(
                    Circle().strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(JarvisTheme.Typography.caption(9))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(gridDays.indices, id: \.self) { index in
                if let day = gridDays[index] {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 26)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: environment.clock.now)
        let hasEvents = eventCount(on: day) > 0

        return VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(JarvisTheme.Typography.caption(11))
                .monospacedDigit()
                .foregroundStyle(
                    isToday
                        ? JarvisTheme.Palette.canvas
                        : JarvisTheme.Palette.textSecondary
                )
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(isToday ? JarvisTheme.Palette.accent : Color.clear)
                )

            Circle()
                .fill(hasEvents ? JarvisTheme.Palette.info : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected && !isToday ? JarvisTheme.Palette.accent.opacity(0.1) : Color.clear)
        )
        .help(hasEvents ? "\(eventCount(on: day)) event(s)" : "")
    }

    // MARK: - Data

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        var calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        // Rotate so the first column matches the first weekday of the locale.
        let firstWeekday = calendar.firstWeekday - 1
        _ = calendar
        return Array(symbols[firstWeekday...] + symbols[..<firstWeekday])
    }

    /// Days of the displayed month, padded with nil for the leading offset.
    private var gridDays: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstDay = interval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30

        let weekday = calendar.component(.weekday, from: firstDay)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: offset, to: firstDay) {
                days.append(date)
            }
        }
        // Pad the last row so the grid keeps its shape.
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private func eventCount(on day: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        return cachedEvents.filter { $0.startDate >= start && $0.startDate < end }.count
    }

    private var eventsThisMonth: Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return 0 }
        return cachedEvents.filter { $0.startDate >= interval.start && $0.startDate < interval.end }.count
    }

    private func shiftMonth(by value: Int) {
        if let shifted = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = shifted
        }
    }
}
