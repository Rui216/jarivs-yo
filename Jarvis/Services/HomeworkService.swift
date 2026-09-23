//
//  HomeworkService.swift
//  JARVIS
//
//  Mutations and summaries for the homework tracker.
//

import Foundation
import SwiftData

/// Creates and updates homework assignments.
@MainActor
final class HomeworkService {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Writing

    /// Creates an assignment and returns the stored item.
    @discardableResult
    func create(
        title: String,
        subject: String,
        detail: String = "",
        dueDate: Date
    ) -> HomeworkItem {
        let item = HomeworkItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: detail,
            dueDate: dueDate
        )
        context.insert(item)
        save()
        return item
    }

    /// Flips the completion state of an assignment.
    func toggle(_ item: HomeworkItem) {
        item.isDone.toggle()
        item.completedAt = item.isDone ? Date() : nil
        save()
    }

    /// Deletes an assignment.
    func delete(_ item: HomeworkItem) {
        context.delete(item)
        save()
    }

    // MARK: - Reading

    /// Assignments due soonest first, intended for the reminders card.
    func upcoming(limit: Int = 8, includeCompleted: Bool = false) -> [HomeworkItem] {
        let descriptor = FetchDescriptor<HomeworkItem>(
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let filtered = includeCompleted ? all : all.filter { !$0.isDone }
        return Array(filtered.prefix(limit))
    }

    /// Counts used by the homework screen header.
    func counts() -> (open: Int, overdue: Int, done: Int, dueThisWeek: Int) {
        let all = (try? context.fetch(FetchDescriptor<HomeworkItem>())) ?? []
        let open = all.filter { !$0.isDone }
        let overdue = open.filter(\.isOverdue).count
        let dueThisWeek = open.filter { (0...7).contains($0.daysRemaining) }.count
        return (open.count, overdue, all.count - open.count, dueThisWeek)
    }

    /// The next assignment due, used by the assistant summary.
    func nextDue() -> HomeworkItem? {
        upcoming(limit: 1).first
    }

    // MARK: - Internals

    private func save() {
        do {
            try context.save()
        } catch {
            Log.services.error("Homework save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
