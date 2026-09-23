//
//  HomeworkRemindersCard.swift
//  JARVIS
//
//  Homework reminders on the dashboard: the assignments due soonest,
//  with inline completion and a compact add form.
//

import SwiftUI
import SwiftData

/// Assignments due soon, with a quick add form.
struct HomeworkRemindersCard: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \HomeworkItem.dueDate, order: .forward) private var homework: [HomeworkItem]

    @State private var isAdding = false
    @State private var newTitle = ""
    @State private var newSubject = ""
    @State private var newDueDate = Date().addingTimeInterval(86_400)
    @FocusState private var titleFocused: Bool

    var body: some View {
        JarvisCard(title: "Homework Reminders", symbolName: "book.closed") {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                if visibleItems.isEmpty {
                    EmptyStateView(
                        symbolName: "checkmark.seal",
                        title: "Nothing due",
                        message: "Add an assignment to start tracking it."
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(visibleItems) { item in
                            row(for: item)
                        }
                    }
                }

                if isAdding {
                    addForm
                }
            }
        } accessory: {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isAdding.toggle()
                    titleFocused = isAdding
                }
            } label: {
                Image(systemName: isAdding ? "xmark" : "plus")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(JarvisTheme.Palette.accent)
            .help(isAdding ? "Close the add form" : "Add homework")
        }
    }

    // MARK: - Rows

    private func row(for item: HomeworkItem) -> some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.tight) {
            Button {
                environment.homework.toggle(item)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.isDone ? JarvisTheme.Palette.success : JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(JarvisTheme.Typography.headline(12))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    .strikethrough(item.isDone, color: JarvisTheme.Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if !item.subject.isEmpty {
                        StatusChip(text: item.subject, tint: JarvisTheme.Palette.violet)
                    }
                    Text(item.dueDescription)
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(dueColor(for: item))
                }
            }

            Spacer(minLength: 0)

            IconActionButton(
                symbolName: "folder",
                tint: JarvisTheme.Palette.textTertiary,
                helpText: "Open the Homework screen"
            ) {
                environment.appState.destination = .homework
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            TextField("Assignment title", text: $newTitle)
                .jarvisField(focused: titleFocused)
                .focused($titleFocused)
                .onSubmit(add)

            HStack(spacing: JarvisTheme.Spacing.tight) {
                TextField("Subject", text: $newSubject)
                    .jarvisField()
                DatePicker("", selection: $newDueDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(width: 112)
            }

            Button("Add assignment", action: add)
                .buttonStyle(.jarvisPrimaryWide)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(JarvisTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .fill(JarvisTheme.Palette.canvas.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let subject = newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        environment.homework.create(
            title: title,
            subject: subject.isEmpty ? "General" : subject,
            dueDate: newDueDate
        )
        newTitle = ""
        newSubject = ""
        newDueDate = Date().addingTimeInterval(86_400)
        titleFocused = true
    }

    // MARK: - Data

    private var visibleItems: [HomeworkItem] {
        Array(homework.filter { !$0.isDone }.prefix(5))
    }

    private func dueColor(for item: HomeworkItem) -> Color {
        if item.isOverdue { return JarvisTheme.Palette.danger }
        if item.daysRemaining <= 1 { return JarvisTheme.Palette.warning }
        return JarvisTheme.Palette.textTertiary
    }
}
