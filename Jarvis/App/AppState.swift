//
//  AppState.swift
//  JARVIS
//
//  Navigation and window level state for the shell: which screen the
//  sidebar is showing and whether the assistant column is expanded.
//

import Foundation

/// Screens reachable from the sidebar.
enum SidebarDestination: String, CaseIterable, Identifiable, Hashable, Codable {
    case home
    case tasks
    case calendar
    case homework
    case files
    case apps
    case settings

    var id: String { rawValue }

    /// Label shown in the sidebar.
    var displayName: String {
        switch self {
        case .home: return "Home"
        case .tasks: return "Tasks"
        case .calendar: return "Calendar"
        case .homework: return "Homework"
        case .files: return "Files"
        case .apps: return "Apps"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol shown next to the label.
    var symbolName: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .tasks: return "checklist"
        case .calendar: return "calendar"
        case .homework: return "book.closed"
        case .files: return "folder"
        case .apps: return "square.grid.3x3"
        case .settings: return "gearshape"
        }
    }

    /// Single key, 1 through 7, that selects this screen from the
    /// Navigate menu while the Command key is held.
    var shortcutKey: Character {
        switch self {
        case .home: return "1"
        case .tasks: return "2"
        case .calendar: return "3"
        case .homework: return "4"
        case .files: return "5"
        case .apps: return "6"
        case .settings: return "7"
        }
    }

    /// One line description used by the sidebar tooltips.
    var summary: String {
        switch self {
        case .home: return "Dashboard with today's overview"
        case .tasks: return "All to-do items and homework in one list"
        case .calendar: return "Month view of your calendar"
        case .homework: return "Assignments, subjects, and due dates"
        case .files: return "Browse your folders"
        case .apps: return "Quick Tools shortcuts"
        case .settings: return "Provider keys, permissions, and preferences"
        }
    }
}

/// Sidebar and panel state.
@MainActor
@Observable
final class AppState {

    /// Screen currently shown in the main column.
    var destination: SidebarDestination = .home

    /// Whether the assistant column is visible.
    var isAssistantVisible: Bool = true

    /// Whether the sidebar is collapsed to icons only.
    var isSidebarCollapsed: Bool = false

    /// Draft text the dashboard wants to pre-fill in the assistant input,
    /// for example when a task is sent to the assistant for planning.
    var pendingAssistantPrompt: String?

    /// Routes a prompt to the assistant and focuses its panel.
    func sendToAssistant(_ prompt: String) {
        isAssistantVisible = true
        pendingAssistantPrompt = prompt
    }
}
