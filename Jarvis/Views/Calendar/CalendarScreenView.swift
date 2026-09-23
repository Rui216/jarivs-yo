//
//  CalendarScreenView.swift
//  JARVIS
//
//  Month view of the calendar with the selected day's schedule beside
//  it, plus event creation through EventKit.
//

import SwiftUI
import SwiftData

/// Month calendar screen.
struct CalendarScreenView: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \CalendarEventItem.startDate, order: .forward) private var cachedEvents: [CalendarEventItem]

    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var isComposingEvent = false
    @State private var isRequestingAccess = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 6, alignment: .top),
        count: 7
    )

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
            header

            if environment.calendarAutomation.calendarAccessState != .granted {
                accessPrompt
            } else {
                HStack(alignment: .top, spacing: JarvisTheme.Spacing.loose) {
                    monthGrid
                        .frame(maxWidth: .infinity)
                    dayDetail
                        .frame(width: 320)
                }
            }
        }
        .padding(JarvisTheme.Layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isComposingEvent) {
            EventComposerSheet(initialDate: selectedDate)
                .environment(environment)
        }
        .task {
            await environment.calendarStore.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: JarvisTheme.Spacing.regular) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar")
                    .font(JarvisTheme.Typography.display(26))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                Text(monthTitle)
                    .font(JarvisTheme.Typography.headline(14))
                    .foregroundStyle(JarvisTheme.Palette.accent)
            }

            Spacer(minLength: 0)

            HStack(spacing: JarvisTheme.Spacing.tight) {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.jarvisSecondary)

                Button("Today") {
                    displayedMonth = Date()
                    selectedDate = Date()
                }
                .buttonStyle(.jarvisSecondary)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.jarvisSecondary)

                Button("New event") {
                    isComposingEvent = true
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(environment.calendarAutomation.calendarAccessState != .granted)
            }
        }
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            Text("Calendar access is off")
                .font(JarvisTheme.Typography.headline(14))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Text("JARVIS needs calendar access to read your schedule and to create events. The assistant can also request it when you ask for something that needs it.")
                .font(JarvisTheme.Typography.body(12))
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
        .padding(JarvisTheme.Spacing.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Grid

    private var monthGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(JarvisTheme.Typography.caption(9))
                        .tracking(0.6)
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(gridDays.indices, id: \.self) { index in
                    if let day = gridDays[index] {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 82)
                    }
                }
            }
        }
        .padding(JarvisTheme.Spacing.regular)
        .jarvisCard()
    }

    private func dayCell(_ day: Date) -> some View {
        let events = events(on: day)
        let isToday = Calendar.current.isDateInToday(day)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)

        return Button {
            selectedDate = day
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(JarvisTheme.Typography.caption(11))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? JarvisTheme.Palette.canvas : JarvisTheme.Palette.textPrimary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isToday ? JarvisTheme.Palette.accent : Color.clear))
                    Spacer(minLength: 0)
                    if events.count > 2 {
                        Text("+\(events.count - 2)")
                            .font(JarvisTheme.Typography.caption(8))
                            .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    }
                }

                ForEach(events.prefix(2)) { event in
                    Text(event.title)
                        .font(JarvisTheme.Typography.caption(9))
                        .foregroundStyle(JarvisTheme.Palette.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(JarvisTheme.Palette.accent.opacity(0.16))
                        )
                }

                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(height: 82, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? JarvisTheme.Palette.accent.opacity(0.08) : JarvisTheme.Palette.canvas.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? JarvisTheme.Palette.accent.opacity(0.45) : JarvisTheme.Palette.stroke,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day detail

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(JarvisTimeFormat.weekday(selectedDate))
                        .font(JarvisTheme.Typography.title(15))
                        .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    Text(JarvisTimeFormat.shortDate(selectedDate))
                        .font(JarvisTheme.Typography.caption(11))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }
                Spacer()
                Button {
                    isComposingEvent = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(JarvisTheme.Palette.accent)
                .help("Add an event on this day")
            }

            let events = events(on: selectedDate)
            if events.isEmpty {
                EmptyStateView(
                    symbolName: "calendar",
                    title: "Nothing scheduled",
                    message: "No events on this day."
                )
            } else {
                ScrollView {
                    VStack(spacing: JarvisTheme.Spacing.tight) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Text("Times are shown in \(TimeZone.current.identifier).")
                .font(JarvisTheme.Typography.caption(9))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
        }
        .padding(JarvisTheme.Spacing.loose)
        .frame(maxHeight: .infinity, alignment: .top)
        .jarvisCard()
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StatusChip(
                    text: event.isAllDay ? "All day" : JarvisTimeFormat.shortTime(event.startDate),
                    tint: event.isInProgress ? JarvisTheme.Palette.success : JarvisTheme.Palette.accent
                )
                if !event.calendarName.isEmpty {
                    StatusChip(text: event.calendarName, tint: JarvisTheme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Text(event.title)
                .font(JarvisTheme.Typography.headline(12))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !event.isAllDay {
                Text("\(JarvisTimeFormat.shortTime(event.startDate)) to \(JarvisTimeFormat.shortTime(event.endDate)) - \(event.durationMinutes) min")
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            if !event.location.isEmpty {
                Text(event.location)
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(JarvisTheme.Spacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(JarvisTheme.Palette.canvas.opacity(0.45))
        )
    }

    // MARK: - Data

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday - 1
        return Array(symbols[firstWeekday...] + symbols[..<firstWeekday])
    }

    private var gridDays: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let daysInMonth = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<daysInMonth {
            days.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private func events(on day: Date) -> [CalendarEventItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        return cachedEvents.filter { $0.startDate >= start && $0.startDate < end }
    }

    private func shiftMonth(by value: Int) {
        guard let shifted = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = shifted
    }
}

// MARK: - Event composer

/// Sheet that creates a calendar event through EventKit.
struct EventComposerSheet: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    /// Day the composer opens on.
    let initialDate: Date

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3_600)
    @State private var location = ""
    @State private var notes = ""
    @State private var calendarName = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            Text("New event")
                .font(JarvisTheme.Typography.display(20))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)

            TextField("Title", text: $title)
                .jarvisField()

            HStack(spacing: JarvisTheme.Spacing.tight) {
                DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Ends", selection: $end, displayedComponents: [.date, .hourAndMinute])
            }
            .font(JarvisTheme.Typography.caption(11))

            TextField("Location", text: $location)
                .jarvisField()

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .jarvisField()

            if !environment.calendarAutomation.writableCalendarNames().isEmpty {
                Picker("Calendar", selection: $calendarName) {
                    Text("Default").tag("")
                    ForEach(environment.calendarAutomation.writableCalendarNames(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .font(JarvisTheme.Typography.caption(11))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: JarvisTheme.Spacing.tight) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.jarvisSecondary)
                Spacer()
                Button(isSaving ? "Saving..." : "Create event") {
                    save()
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(JarvisTheme.Spacing.section)
        .frame(width: 520)
        .background(JarvisTheme.canvasGradient)
        .onAppear {
            let calendar = Calendar.current
            let base = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: initialDate) ?? initialDate
            start = base
            end = base.addingTimeInterval(3_600)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let snapshot = try await environment.calendarAutomation.createEvent(
                    title: trimmed,
                    start: start,
                    end: end,
                    notes: notes.isEmpty ? nil : notes,
                    location: location.isEmpty ? nil : location,
                    calendarName: calendarName.isEmpty ? nil : calendarName
                )
                environment.calendarStore.upsert([snapshot])
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
