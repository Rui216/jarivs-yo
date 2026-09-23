//
//  TodoCard.swift
//  JARVIS
//
//  The dashboard to-do list: checkboxes, priorities, inline creation,
//  and a clear completed action. The same TaskService calls back this
//  card and the assistant tools.
//

import SwiftUI
import SwiftData

/// To-do list with checkboxes and an add field.
struct TodoCard: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @State private var newTitle = ""
    @State private var priority: TaskPriority = .normal
    @FocusState private var inputFocused: Bool

    var body: some View {
        JarvisCard(title: "To-Do", symbolName: "checklist") {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                inputRow

                if visibleTasks.isEmpty {
                    EmptyStateView(
                        symbolName: "checkmark.circle",
                        title: "Nothing to do",
                        message: "Add a task above, or ask the assistant to create one."
                    )
                } else {
                    VStack(spacing: 2) {
                        ForEach(visibleTasks) { task in
                            taskRow(task)
                        }
                    }
                }

                if !completedTasks.isEmpty {
                    Divider().overlay(JarvisTheme.Palette.stroke)
                    HStack {
                        Text("\(completedTasks.count) completed")
                            .font(JarvisTheme.Typography.caption(10))
                            .foregroundStyle(JarvisTheme.Palette.textTertiary)
                        Spacer()
                        Button("Clear completed") {
                            environment.tasks.clearCompleted()
                        }
                        .buttonStyle(.plain)
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.danger)
                    }
                }
            }
        } accessory: {
            StatusChip(
                text: "\(openTasks.count) open",
                tint: JarvisTheme.Palette.accent
            )
        }
    }

    // MARK: - Rows

    private var inputRow: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            TextField("Add a task", text: $newTitle)
                .jarvisField(focused: inputFocused)
                .focused($inputFocused)
                .onSubmit(addTask)

            Menu {
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases) { level in
                        Label(level.displayName, systemImage: level.symbolName).tag(level)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(priority.tint)
                        .frame(width: 7, height: 7)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                        .fill(JarvisTheme.Palette.canvas.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                        .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Priority for the next task")

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(JarvisTheme.Palette.canvas)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                            .fill(JarvisTheme.accentGradient)
                    )
            }
            .buttonStyle(.plain)
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Add the task")
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.tight) {
            Button {
                environment.tasks.toggle(task)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(task.isDone ? JarvisTheme.Palette.success : JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(JarvisTheme.Typography.body(13))
                    .foregroundStyle(task.isDone ? JarvisTheme.Palette.textTertiary : JarvisTheme.Palette.textPrimary)
                    .strikethrough(task.isDone, color: JarvisTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if task.priority != .normal {
                        StatusChip(text: task.priority.displayName, tint: task.priority.tint)
                    }
                    if let dueDate = task.dueDate {
                        Text("\(JarvisTimeFormat.shortDate(dueDate)) - \(JarvisTimeFormat.relative(from: dueDate))")
                            .font(JarvisTheme.Typography.caption(10))
                            .foregroundStyle(task.isOverdue ? JarvisTheme.Palette.danger : JarvisTheme.Palette.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                environment.tasks.delete(task)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Delete the task")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(task.isOverdue ? JarvisTheme.Palette.danger.opacity(0.07) : Color.clear)
        )
    }

    // MARK: - Actions

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        environment.tasks.create(title: title, priority: priority)
        newTitle = ""
        priority = .normal
        inputFocused = true
    }

    // MARK: - Data

    private var openTasks: [TaskItem] {
        tasks.filter { !$0.isDone }
    }

    private var completedTasks: [TaskItem] {
        tasks.filter(\.isDone)
    }

    private var visibleTasks: [TaskItem] {
        let open = openTasks.sorted { left, right in
            if left.isOverdue != right.isOverdue { return left.isOverdue }
            if left.priority != right.priority {
                return priorityRank(left.priority) > priorityRank(right.priority)
            }
            return left.createdAt > right.createdAt
        }
        guard environment.settings.showsCompletedTasks else {
            return Array(open.prefix(12))
        }
        return Array((open + completedTasks).prefix(16))
    }

    private func priorityRank(_ value: TaskPriority) -> Int {
        switch value {
        case .high: return 2
        case .normal: return 1
        case .low: return 0
        }
    }
}
