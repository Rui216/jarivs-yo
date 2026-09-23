//
//  HomeworkItem.swift
//  JARVIS
//
//  Coursework tracked on the Homework screen and in the dashboard
//  Homework Reminders card. Persisted with SwiftData.
//

import Foundation
import SwiftData

/// A piece of homework with a subject and a due date.
@Model
final class HomeworkItem {
    /// Assignment title, for example "Chapter 4 problem set".
    var title: String
    /// Course or subject name used for grouping.
    var subject: String
    /// Optional details or instructions.
    var detail: String
    /// Due date for the assignment.
    var dueDate: Date
    /// Whether the assignment is finished.
    var isDone: Bool
    /// When the assignment was created.
    var createdAt: Date
    /// When the assignment was completed.
    var completedAt: Date?

    /// Not persisted. True when the due date has passed and the work is open.
    var isOverdue: Bool {
        !isDone && dueDate < Date()
    }

    /// Not persisted. Whole days remaining until the due date, negative when late.
    var daysRemaining: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: dueDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// Not persisted. Short relative description of the due date.
    var dueDescription: String {
        if isDone { return "Completed" }
        switch daysRemaining {
        case ..<0: return "Overdue by \(abs(daysRemaining)) day(s)"
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "Due in \(daysRemaining) days"
        }
    }

    init(
        title: String,
        subject: String,
        detail: String = "",
        dueDate: Date,
        isDone: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.title = title
        self.subject = subject
        self.detail = detail
        self.dueDate = dueDate
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
