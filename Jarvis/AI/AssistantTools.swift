//
//  AssistantTools.swift
//  JARVIS
//
//  Definitions of every action the assistant can take on the machine,
//  expressed as JSON Schema function declarations. The schemas are the
//  contract between the model and the automation layer; execution lives
//  in AutomationToolBridge.
//

import Foundation

// MARK: - Tool names

/// Canonical tool names shared by the schema catalog, the automation
/// bridge, and the confirmation prompts.
enum AssistantToolName {
    static let openApplication = "open_application"
    static let listApplications = "list_installed_applications"
    static let openURL = "open_url"
    static let openBrowserTab = "open_browser_tab"
    static let webSearch = "search_web"
    static let openFileOrFolder = "open_file_or_folder"
    static let revealInFinder = "reveal_in_finder"
    static let findFiles = "find_files"
    static let runAppleScript = "run_applescript"
    static let runTerminalCommand = "run_terminal_command"
    static let createCalendarEvent = "create_calendar_event"
    static let createReminder = "create_reminder"
    static let listUpcomingEvents = "list_upcoming_events"
    static let controlMusic = "control_music_playback"
    static let systemStatus = "get_system_status"
    static let createTask = "create_task"
    static let createHomework = "create_homework"
    static let completeTask = "complete_task"
    static let saveNote = "save_note"

    /// Every tool the catalog can expose.
    static let all: [String] = [
        openApplication, listApplications, openURL, openBrowserTab, webSearch,
        openFileOrFolder, revealInFinder, findFiles, runAppleScript, runTerminalCommand,
        createCalendarEvent, createReminder, listUpcomingEvents, controlMusic, systemStatus,
        createTask, createHomework, completeTask, saveNote
    ]

    /// Tools that change something outside the app and therefore always
    /// require an explicit user confirmation before running.
    static let confirmationRequired: Set<String> = [
        runTerminalCommand
    ]
}

// MARK: - Tool call value types

/// A tool call requested by the model.
struct AssistantToolCall: Sendable, Identifiable, Equatable {
    /// Provider supplied call identifier, echoed back with the result.
    let id: String
    /// Function name, expected to be one of `AssistantToolName`.
    let name: String
    /// Raw JSON arguments produced by the model.
    let argumentsJSON: String

    /// Parsed arguments, empty when the model sent invalid JSON.
    var arguments: [String: Any] {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    /// Reads a string argument.
    func string(_ key: String) -> String? {
        let value = arguments[key]
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// Reads an integer argument.
    func int(_ key: String) -> Int? {
        if let value = arguments[key] as? Int { return value }
        if let value = arguments[key] as? Double { return Int(value) }
        if let text = arguments[key] as? String { return Int(text) }
        return nil
    }

    /// Reads a boolean argument, accepting common string spellings.
    func bool(_ key: String) -> Bool? {
        if let value = arguments[key] as? Bool { return value }
        if let value = arguments[key] as? NSNumber { return value.boolValue }
        if let text = arguments[key] as? String {
            switch text.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    /// Reads a string array argument.
    func stringArray(_ key: String) -> [String]? {
        if let values = arguments[key] as? [String] { return values }
        if let values = arguments[key] as? [Any] {
            return values.compactMap { $0 as? String }
        }
        return nil
    }

    /// One line description shown in the transcript while the tool runs.
    var summary: String {
        switch name {
        case AssistantToolName.openApplication:
            return "Open \(string("application") ?? "application")"
        case AssistantToolName.listApplications:
            return "List installed applications"
        case AssistantToolName.openURL:
            return "Open \(string("url") ?? "link")"
        case AssistantToolName.openBrowserTab:
            return "Open tab in \(string("browser") ?? "default browser")"
        case AssistantToolName.webSearch:
            return "Search the web for \(string("query") ?? "query")"
        case AssistantToolName.openFileOrFolder:
            return "Open \(string("path") ?? "path")"
        case AssistantToolName.revealInFinder:
            return "Reveal \(string("path") ?? "path") in Finder"
        case AssistantToolName.findFiles:
            return "Search files for \(string("query") ?? "query")"
        case AssistantToolName.runAppleScript:
            return string("purpose") ?? "Run AppleScript"
        case AssistantToolName.runTerminalCommand:
            return "Run \(string("command") ?? "command")"
        case AssistantToolName.createCalendarEvent:
            return "Create event \(string("title") ?? "event")"
        case AssistantToolName.createReminder:
            return "Create reminder \(string("title") ?? "reminder")"
        case AssistantToolName.listUpcomingEvents:
            return "Read upcoming events"
        case AssistantToolName.controlMusic:
            return "Music: \(string("action") ?? "control")"
        case AssistantToolName.systemStatus:
            return "Read system status"
        case AssistantToolName.createTask:
            return "Add task \(string("title") ?? "task")"
        case AssistantToolName.createHomework:
            return "Add homework \(string("title") ?? "homework")"
        case AssistantToolName.completeTask:
            return "Complete task \(string("title") ?? "task")"
        case AssistantToolName.saveNote:
            return "Save note"
        default:
            return name
        }
    }
}

/// Outcome of running a tool, returned to the model.
struct AssistantToolResult: Sendable, Equatable {
    /// Text handed back to the model.
    var content: String
    /// True when the action failed or was refused.
    var isError: Bool
    /// One line description shown in the transcript.
    var summary: String

    /// Successful result.
    static func success(summary: String, content: String) -> AssistantToolResult {
        AssistantToolResult(content: content, isError: false, summary: summary)
    }

    /// Failed result. The message is written for the model to reason about.
    static func failure(summary: String, message: String) -> AssistantToolResult {
        AssistantToolResult(content: message, isError: true, summary: summary)
    }

    /// Result produced when the user declines a confirmation prompt.
    static func denied(summary: String, message: String) -> AssistantToolResult {
        AssistantToolResult(content: message, isError: true, summary: summary)
    }
}

/// Executes tool calls. Implemented by the automation layer, which runs on
/// the main actor because it touches AppKit, EventKit, and SwiftData.
protocol AssistantToolExecuting: Sendable {
    /// Runs one tool call and returns the text handed back to the model.
    @MainActor
    func execute(_ call: AssistantToolCall) async -> AssistantToolResult
}

// MARK: - Schema catalog

/// Builds the JSON Schema declarations offered to the model.
enum AssistantToolCatalog {

    /// Schemas for every tool, in the order they are advertised.
    static var allSchemas: [AssistantToolSchema] {
        [
            openApplication,
            listApplications,
            openURL,
            openBrowserTab,
            webSearch,
            openFileOrFolder,
            revealInFinder,
            findFiles,
            runAppleScript,
            runTerminalCommand,
            createCalendarEvent,
            createReminder,
            listUpcomingEvents,
            controlMusic,
            systemStatus,
            createTask,
            createHomework,
            completeTask,
            saveNote
        ]
    }

    /// Schemas for the requested tool names, preserving catalog order.
    static func schemas(for names: Set<String>) -> [AssistantToolSchema] {
        allSchemas.filter { names.contains($0.name) }
    }

    /// Names of every tool in the catalog.
    static var allNames: Set<String> { Set(allSchemas.map(\.name)) }

    // MARK: Individual declarations

    static let openApplication = AssistantToolSchema(
        name: AssistantToolName.openApplication,
        description: "Launch an installed macOS application by name or bundle identifier.",
        parameters: object(
            properties: [
                "application": string("Application name such as Safari, or a bundle identifier such as com.apple.Safari.")
            ],
            required: ["application"]
        )
    )

    static let listApplications = AssistantToolSchema(
        name: AssistantToolName.listApplications,
        description: "List the applications installed in the system Applications folders.",
        parameters: object(properties: [:], required: [])
    )

    static let openURL = AssistantToolSchema(
        name: AssistantToolName.openURL,
        description: "Open a web address in the user default browser.",
        parameters: object(
            properties: [
                "url": string("Absolute address including the scheme, for example https://example.com.")
            ],
            required: ["url"]
        )
    )

    static let openBrowserTab = AssistantToolSchema(
        name: AssistantToolName.openBrowserTab,
        description: "Open a web address in a new tab or window of a specific browser using Apple Events.",
        parameters: object(
            properties: [
                "url": string("Absolute address to open."),
                "browser": string("Browser name: chrome, safari, edge, brave, or arc."),
                "new_window": boolean("Set to true to open a new window instead of a new tab.")
            ],
            required: ["url"]
        )
    )

    static let webSearch = AssistantToolSchema(
        name: AssistantToolName.webSearch,
        description: "Search the web in the default browser using a search engine.",
        parameters: object(
            properties: [
                "query": string("Search terms."),
                "engine": string("Search engine: google, duckduckgo, bing, or youtube.")
            ],
            required: ["query"]
        )
    )

    static let openFileOrFolder = AssistantToolSchema(
        name: AssistantToolName.openFileOrFolder,
        description: "Open a file or folder with its default application. The path is expanded and validated first.",
        parameters: object(
            properties: [
                "path": string("Absolute path, or a path starting with a tilde for the home folder.")
            ],
            required: ["path"]
        )
    )

    static let revealInFinder = AssistantToolSchema(
        name: AssistantToolName.revealInFinder,
        description: "Select an item in a new Finder window.",
        parameters: object(
            properties: [
                "path": string("Absolute path, or a path starting with a tilde for the home folder.")
            ],
            required: ["path"]
        )
    )

    static let findFiles = AssistantToolSchema(
        name: AssistantToolName.findFiles,
        description: "Search the user home folder for files whose name matches a query.",
        parameters: object(
            properties: [
                "query": string("File name fragment to search for."),
                "limit": integer("Maximum number of results, between 1 and 50. Defaults to 15.")
            ],
            required: ["query"]
        )
    )

    static let runAppleScript = AssistantToolSchema(
        name: AssistantToolName.runAppleScript,
        description: "Run a short AppleScript through osascript to automate an application. Only use for applications that expose a scripting dictionary, and prefer dedicated tools when one exists.",
        parameters: object(
            properties: [
                "purpose": string("One line description of what the script does, shown to the user."),
                "script": string("The AppleScript source. Must be shell free and must not use do shell script.")
            ],
            required: ["purpose", "script"]
        )
    )

    static let runTerminalCommand = AssistantToolSchema(
        name: AssistantToolName.runTerminalCommand,
        description: "Run a terminal command after the user approves it. The command must be built from the whitelisted binaries and a confirmation dialog is always shown first.",
        parameters: object(
            properties: [
                "command": string("The command line to run, without shell metacharacters such as pipes or redirects."),
                "purpose": string("One line description of the effect, shown in the confirmation dialog.")
            ],
            required: ["command", "purpose"]
        )
    )

    static let createCalendarEvent = AssistantToolSchema(
        name: AssistantToolName.createCalendarEvent,
        description: "Create a calendar event through EventKit. Times are local and use ISO 8601 with an offset.",
        parameters: object(
            properties: [
                "title": string("Event title."),
                "start": string("Start time, ISO 8601 such as 2026-03-14T09:00:00Z."),
                "end": string("End time, ISO 8601."),
                "notes": string("Optional notes."),
                "location": string("Optional location."),
                "calendar": string("Optional calendar name. The default calendar is used when omitted.")
            ],
            required: ["title", "start", "end"]
        )
    )

    static let createReminder = AssistantToolSchema(
        name: AssistantToolName.createReminder,
        description: "Create a reminder in the Reminders app through EventKit.",
        parameters: object(
            properties: [
                "title": string("Reminder title."),
                "due": string("Optional due date, ISO 8601."),
                "notes": string("Optional notes."),
                "list": string("Optional reminder list name.")
            ],
            required: ["title"]
        )
    )

    static let listUpcomingEvents = AssistantToolSchema(
        name: AssistantToolName.listUpcomingEvents,
        description: "Read calendar events between now and a number of days ahead.",
        parameters: object(
            properties: [
                "days": integer("How many days ahead to include, between 1 and 30. Defaults to 7.")
            ],
            required: []
        )
    )

    static let controlMusic = AssistantToolSchema(
        name: AssistantToolName.controlMusic,
        description: "Control music playback in Spotify or Music through Apple Events.",
        parameters: object(
            properties: [
                "action": string("One of: play, pause, next, previous, now_playing."),
                "application": string("Either Spotify or Music.")
            ],
            required: ["action"]
        )
    )

    static let systemStatus = AssistantToolSchema(
        name: AssistantToolName.systemStatus,
        description: "Read current processor, memory, disk, and network statistics.",
        parameters: object(properties: [:], required: [])
    )

    static let createTask = AssistantToolSchema(
        name: AssistantToolName.createTask,
        description: "Add an item to the dashboard to-do list.",
        parameters: object(
            properties: [
                "title": string("Task title."),
                "due": string("Optional due date, ISO 8601."),
                "priority": string("low, normal, or high.")
            ],
            required: ["title"]
        )
    )

    static let createHomework = AssistantToolSchema(
        name: AssistantToolName.createHomework,
        description: "Add an assignment to the Homework tracker.",
        parameters: object(
            properties: [
                "title": string("Assignment title."),
                "subject": string("Course or subject name."),
                "due": string("Due date, ISO 8601.")
            ],
            required: ["title", "subject", "due"]
        )
    )

    static let completeTask = AssistantToolSchema(
        name: AssistantToolName.completeTask,
        description: "Mark an existing to-do item as done, matched by title.",
        parameters: object(
            properties: [
                "title": string("Title of the task to complete, matched case insensitively.")
            ],
            required: ["title"]
        )
    )

    static let saveNote = AssistantToolSchema(
        name: AssistantToolName.saveNote,
        description: "Save a quick note on the dashboard.",
        parameters: object(
            properties: [
                "text": string("Note contents.")
            ],
            required: ["text"]
        )
    )

    // MARK: Schema helpers

    private static func object(properties: [String: SchemaValue], required: [String]) -> SchemaValue {
        var dictionary: [String: SchemaValue] = [
            "type": .string("object"),
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            dictionary["required"] = .array(required.map { .string($0) })
        }
        dictionary["additionalProperties"] = .boolean(false)
        return .object(dictionary)
    }

    private static func string(_ description: String) -> SchemaValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func integer(_ description: String) -> SchemaValue {
        .object(["type": .string("integer"), "description": .string(description)])
    }

    private static func boolean(_ description: String) -> SchemaValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }
}
