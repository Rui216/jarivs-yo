//
//  HomeworkView.swift
//  JARVIS
//
//  Homework tracker: assignments grouped by due window, a per subject
//  breakdown, quick add, and an option to mirror an assignment into the
//  Reminders app through EventKit.
//

import SwiftUI
import SwiftData

/// Assignment tracker screen.
struct HomeworkView: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \HomeworkItem.dueDate, order: .forward) private var homework: [HomeworkItem]

    @State private var showsCompleted = false
    @State private var title = ""
    @State private var subject = ""
    @State private var dueDate = Date().addingTimeInterval(86_400)
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
                header
                summary
                composer
                list
            }
            .padding(JarvisTheme.Layout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
                Text("Homework")
                    .font(JarvisTheme.Typography.display(26))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                Text("Track assignments by subject and due date, and let the assistant create reminders for them.")
                    .font(JarvisTheme.Typography.body(12))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
            }
            Spacer(minLength: 0)

            Toggle("Show completed", isOn: $showsCompleted)
                .toggleStyle(.switch)
                .tint(JarvisTheme.Palette.accent)
                .font(JarvisTheme.Typography.caption(11))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
        }
    }

    private var summary: some View {
        let counts = environment.homework.counts()
        return HStack(spacing: JarvisTheme.Spacing.regular) {
            summaryCard(title: "Open", value: "\(counts.open)", tint: JarvisTheme.Palette.accent)
            summaryCard(title: "Due this week", value: "\(counts.dueThisWeek)", tint: JarvisTheme.Palette.violet)
            summaryCard(title: "Overdue", value: "\(counts.overdue)", tint: JarvisTheme.Palette.danger)
            summaryCard(title: "Completed", value: "\(counts.done)", tint: JarvisTheme.Palette.success)
        }
    }

    private func summaryCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(JarvisTheme.Typography.title(20))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Text(title.uppercased())
                .font(JarvisTheme.Typography.caption(9))
                .tracking(0.8)
                .foregroundStyle(tint)
        }
        .padding(JarvisTheme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            HStack(spacing: JarvisTheme.Spacing.tight) {
                TextField("Assignment title", text: $title)
                    .jarvisField()
                TextField("Subject", text: $subject)
                    .jarvisField()
                    .frame(width: 160)
                DatePicker("", selection: $dueDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(width: 112)
                Button("Add assignment") {
                    addAssignment()
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
            }
        }
        .padding(JarvisTheme.Spacing.regular)
        .jarvisCard()
    }

    // MARK: - List

    private var list: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            if visibleItems.isEmpty {
                EmptyStateView(
                    symbolName: "book.closed",
                    title: "No assignments",
                    message: "Add one above, or ask the assistant to add homework for you."
                )
            } else {
                ForEach(groupedItems) { group in
                    VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
                        SectionLabel(text: group.id)
                        VStack(spacing: 6) {
                            ForEach(group.items) { item in
                                row(item)
                            }
                        }
                    }
                }
            }
        }
        .padding(JarvisTheme.Spacing.loose)
        .jarvisCard()
    }

    private func row(_ item: HomeworkItem) -> some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.regular) {
            Button {
                environment.homework.toggle(item)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(item.isDone ? JarvisTheme.Palette.success : JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(JarvisTheme.Typography.headline(13))
                    .foregroundStyle(item.isDone ? JarvisTheme.Palette.textTertiary : JarvisTheme.Palette.textPrimary)
                    .strikethrough(item.isDone, color: JarvisTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if !item.subject.isEmpty {
                        StatusChip(text: item.subject, tint: JarvisTheme.Palette.violet)
                    }
                    Text(item.dueDescription)
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(item.isOverdue ? JarvisTheme.Palette.danger : JarvisTheme.Palette.textTertiary)
                    Text("Due \(JarvisTimeFormat.shortDate(item.dueDate))")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }
            }

            Spacer(minLength: 0)

            Button {
                createReminder(for: item)
            } label: {
                Text("Remind me")
                    .font(JarvisTheme.Typography.caption(10))
            }
            .buttonStyle(.jarvisSecondary)

            Button {
                environment.homework.delete(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(JarvisTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .fill(JarvisTheme.Palette.canvas.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .strokeBorder(
                    item.isOverdue ? JarvisTheme.Palette.danger.opacity(0.4) : JarvisTheme.Palette.stroke,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Data

    private var visibleItems: [HomeworkItem] {
        showsCompleted ? homework : homework.filter { !$0.isDone }
    }

    /// One due window section in the list.
    private struct HomeworkGroup: Identifiable {
        /// Section title, also used as the identity.
        let id: String
        /// Assignments in the section, already ordered by due date.
        let items: [HomeworkItem]
    }

    /// Groups assignments into the due windows used by the list headers.
    private var groupedItems: [HomeworkGroup] {
        var overdue: [HomeworkItem] = []
        var today: [HomeworkItem] = []
        var week: [HomeworkItem] = []
        var later: [HomeworkItem] = []
        var done: [HomeworkItem] = []

        for item in visibleItems {
            if item.isDone {
                done.append(item)
            } else if item.isOverdue {
                overdue.append(item)
            } else if item.daysRemaining == 0 {
                today.append(item)
            } else if item.daysRemaining <= 7 {
                week.append(item)
            } else {
                later.append(item)
            }
        }

        var groups: [HomeworkGroup] = []
        if !overdue.isEmpty { groups.append(HomeworkGroup(id: "Overdue", items: overdue)) }
        if !today.isEmpty { groups.append(HomeworkGroup(id: "Due today", items: today)) }
        if !week.isEmpty { groups.append(HomeworkGroup(id: "This week", items: week)) }
        if !later.isEmpty { groups.append(HomeworkGroup(id: "Later", items: later)) }
        if !done.isEmpty { groups.append(HomeworkGroup(id: "Completed", items: done)) }
        return groups
    }

    private func addAssignment() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        environment.homework.create(
            title: trimmedTitle,
            subject: trimmedSubject.isEmpty ? "General" : trimmedSubject,
            dueDate: dueDate
        )
        title = ""
        subject = ""
        dueDate = Date().addingTimeInterval(86_400)
    }

    private func createReminder(for item: HomeworkItem) {
        Task {
            if environment.calendarAutomation.remindersAccessState != .granted {
                let granted = await environment.requestRemindersAccess()
                guard granted else {
                    statusMessage = "Reminders access was not granted. Enable it in Settings, Permissions."
                    return
                }
            }
            do {
                try await environment.calendarAutomation.createReminder(
                    title: "Homework: \(item.title)",
                    dueDate: item.dueDate,
                    notes: item.subject.isEmpty ? nil : "Subject: \(item.subject)",
                    listName: nil
                )
                statusMessage = "Reminder created for \(item.title)."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
