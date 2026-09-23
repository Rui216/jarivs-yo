//
//  TaskItem.swift
//  JARVIS
//
//  A to-do entry shown on the dashboard and on the Tasks screen.
//  Persisted with SwiftData.
//

import Foundation
import SwiftData

/// Priority assigned to a task.
enum TaskPriority: String, CaseIterable, Identifiable, Codable {
    case low
    case normal
    case high

    var id: String { rawValue }

    /// Human readable name used in menus and lists.
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}

/// A single to-do item.
@Model
final class TaskItem {
    /// Short description of the work to be done.
    var title: String
    /// Optional longer description.
    var detail: String
    /// Whether the task has been completed.
    var isDone: Bool
    /// Creation timestamp, also used as the default sort key.
    var createdAt: Date
    /// Optional due date.
    var dueDate: Date?
    /// Timestamp recorded when the task was completed.
    var completedAt: Date?
    /// Raw storage for `priority` so SwiftData only persists a string.
    var priorityRaw: String

    /// Typed accessor for the stored priority.
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    /// Not persisted. True when the due date is in the past and the task is open.
    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < Date()
    }

    /// Not persisted. True when the task is due within the next 24 hours.
    var isDueSoon: Bool {
        guard let dueDate, !isDone else { return false }
        let interval = dueDate.timeIntervalSinceNow
        return interval > 0 && interval <= 86_400
    }

    init(
        title: String,
        detail: String = "",
        isDone: Bool = false,
        createdAt: Date = Date(),
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        priority: TaskPriority = .normal
    ) {
        self.title = title
        self.detail = detail
        self.isDone = isDone
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.priorityRaw = priority.rawValue
    }
}

extension TaskItem {
    /// Flips the completion state and keeps the timestamp in sync.
    func toggleCompletion() {
        isDone.toggle()
        completedAt = isDone ? Date() : nil
    }
}
