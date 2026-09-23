//
//  TasksView.swift
//  JARVIS
//
//  Full task list: filtering, search, inline creation, priority changes,
//  and completion. Writes go through TaskService so the assistant and
//  this screen can never disagree about the data.
//

import SwiftUI
import SwiftData

/// All to-do items with filtering and search.
struct TasksView: View {

    /// Filter applied to the list.
    enum Filter: String, CaseIterable, Identifiable {
        case open
        case all
        case done

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .open: return "Open"
            case .all: return "All"
            case .done: return "Done"
            }
        }
    }

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @State private var filter: Filter = .open
    @State private var searchText = ""
    @State private var newTitle = ""
    @State private var newPriority: TaskPriority = .normal
    @State private var newDueDate: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
                header
                summaryCards
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
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            Text("Tasks")
                .font(JarvisTheme.Typography.display(26))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Text("Everything on your plate, with the assistant able to add and complete items for you.")
                .font(JarvisTheme.Typography.body(12))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
        }
    }

    private var summaryCards: some View {
        let counts = environment.tasks.counts()
        return HStack(spacing: JarvisTheme.Spacing.regular) {
            summaryCard(title: "Open", value: "\(counts.open)", tint: JarvisTheme.Palette.accent, symbolName: "circle")
            summaryCard(title: "Overdue", value: "\(counts.overdue)", tint: JarvisTheme.Palette.danger, symbolName: "exclamationmark.circle")
            summaryCard(title: "Completed", value: "\(counts.done)", tint: JarvisTheme.Palette.success, symbolName: "checkmark.circle")
        }
    }

    private func summaryCard(title: String, value: String, tint: Color, symbolName: String) -> some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(JarvisTheme.Typography.title(18))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                Text(title.uppercased())
                    .font(JarvisTheme.Typography.caption(9))
                    .tracking(0.8)
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(JarvisTheme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            TextField("Add a task and press Return", text: $newTitle)
                .jarvisField()
                .onSubmit(addTask)

            Menu {
                Picker("Priority", selection: $newPriority) {
                    ForEach(TaskPriority.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(newPriority.displayName)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(newPriority.tint)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 92)

            DatePicker(
                "",
                selection: Binding(
                    get: { newDueDate ?? Date().addingTimeInterval(86_400) },
                    set: { newDueDate = $0 }
                ),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)

            Button("Add", action: addTask)
                .buttonStyle(.jarvisPrimary)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(JarvisTheme.Spacing.regular)
        .jarvisCard()
    }

    // MARK: - List

    private var list: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            HStack(spacing: JarvisTheme.Spacing.tight) {
                ForEach(Filter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.displayName)
                            .font(JarvisTheme.Typography.caption(11))
                            .foregroundStyle(filter == option ? JarvisTheme.Palette.canvas : JarvisTheme.Palette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(filter == option
                                          ? AnyShapeStyle(JarvisTheme.accentGradient)
                                          : AnyShapeStyle(JarvisTheme.Palette.canvas.opacity(0.5)))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(JarvisTheme.Typography.body(12))
                        .foregroundStyle(JarvisTheme.Palette.textPrimary)
                        .frame(width: 180)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(JarvisTheme.Palette.canvas.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
                )
            }

            if filteredTasks.isEmpty {
                EmptyStateView(
                    symbolName: "checklist",
                    title: "Nothing here",
                    message: filter == .done ? "No completed tasks yet." : "Add a task above to get started."
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(filteredTasks) { task in
                        row(task)
                    }
                }
            }
        }
        .padding(JarvisTheme.Spacing.loose)
        .jarvisCard()
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.regular) {
            Button {
                environment.tasks.toggle(task)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(task.isDone ? JarvisTheme.Palette.success : JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(JarvisTheme.Typography.headline(13))
                    .foregroundStyle(task.isDone ? JarvisTheme.Palette.textTertiary : JarvisTheme.Palette.textPrimary)
                    .strikethrough(task.isDone, color: JarvisTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(JarvisTheme.Typography.caption(11))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }

                HStack(spacing: 8) {
                    StatusChip(text: task.priority.displayName, tint: task.priority.tint)
                    Text("Created \(JarvisTimeFormat.relative(from: task.createdAt))")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    if let due = task.dueDate {
                        Text("Due \(JarvisTimeFormat.shortDate(due))")
                            .font(JarvisTheme.Typography.caption(10))
                            .foregroundStyle(task.isOverdue ? JarvisTheme.Palette.danger : JarvisTheme.Palette.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            Menu {
                Picker("Priority", selection: Binding(
                    get: { task.priority },
                    set: { task.priority = $0; try? environment.modelContainer.mainContext.save() }
                )) {
                    ForEach(TaskPriority.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Button("Ask the assistant to schedule it") {
                    environment.appState.sendToAssistant("Find a good time for the task \"\(task.title)\" and put it on my calendar.")
                }

                Button("Delete", role: .destructive) {
                    environment.tasks.delete(task)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .padding(JarvisTheme.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .fill(JarvisTheme.Palette.canvas.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .strokeBorder(
                    task.isOverdue ? JarvisTheme.Palette.danger.opacity(0.4) : JarvisTheme.Palette.stroke,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Data

    private var filteredTasks: [TaskItem] {
        var items = tasks
        switch filter {
        case .open: items = items.filter { !$0.isDone }
        case .done: items = items.filter(\.isDone)
        case .all: break
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            items = items.filter { $0.title.lowercased().contains(query) || $0.detail.lowercased().contains(query) }
        }
        return items
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        environment.tasks.create(title: title, dueDate: newDueDate, priority: newPriority)
        newTitle = ""
        newPriority = .normal
        newDueDate = nil
    }
}
