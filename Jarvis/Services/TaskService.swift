//
//  TaskService.swift
//  JARVIS
//
//  Mutations for the to-do list. Reads in the interface use SwiftData
//  queries so lists stay live; writes funnel through here so the
//  assistant tools and the interface behave identically.
//

import Foundation
import SwiftData

/// Creates, completes, and deletes to-do items.
@MainActor
final class TaskService {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Writing

    /// Creates a task and returns the stored item.
    @discardableResult
    func create(
        title: String,
        detail: String = "",
        dueDate: Date? = nil,
        priority: TaskPriority = .normal
    ) -> TaskItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = TaskItem(
            title: trimmed.isEmpty ? "Untitled task" : trimmed,
            detail: detail,
            dueDate: dueDate,
            priority: priority
        )
        context.insert(item)
        save()
        return item
    }

    /// Flips the completion state of a task.
    func toggle(_ item: TaskItem) {
        item.toggleCompletion()
        save()
    }

    /// Marks a task done without toggling it back when it was already done.
    func markDone(_ item: TaskItem) {
        guard !item.isDone else { return }
        item.isDone = true
        item.completedAt = Date()
        save()
    }

    /// Deletes a task.
    func delete(_ item: TaskItem) {
        context.delete(item)
        save()
    }

    /// Removes every completed task.
    func clearCompleted() {
        for item in completedTasks() {
            context.delete(item)
        }
        save()
    }

    /// Completes the first open task whose title matches the query.
    ///
    /// Matching is case insensitive and falls back to a substring match so a
    /// shortened title from the model still resolves.
    func completeTask(matching title: String) -> TaskItem? {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return nil }

        let open = openTasks(limit: 200)
        let match = open.first { $0.title.lowercased() == query }
            ?? open.first { $0.title.lowercased().contains(query) }
            ?? open.first { query.contains($0.title.lowercased()) }

        guard let match else { return nil }
        match.isDone = true
        match.completedAt = Date()
        save()
        return match
    }

    // MARK: - Reading

    /// Open tasks, newest first.
    func openTasks(limit: Int = 100) -> [TaskItem] {
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.isDone == false },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Completed tasks, most recently completed first.
    func completedTasks(limit: Int = 100) -> [TaskItem] {
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.isDone == true },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Counts used by the dashboard summary line.
    func counts() -> (open: Int, done: Int, overdue: Int) {
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let open = all.filter { !$0.isDone }
        return (open.count, all.count - open.count, open.filter(\.isOverdue).count)
    }

    /// Tasks due today or already overdue, used by the Up Next panel.
    func focusTasks(limit: Int = 5) -> [TaskItem] {
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(for: Date()).addingTimeInterval(86_400)
        return openTasks(limit: 200)
            .filter { item in
                guard let due = item.dueDate else { return false }
                return due < endOfToday
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Internals

    private func save() {
        do {
            try context.save()
        } catch {
            Log.services.error("Task save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
