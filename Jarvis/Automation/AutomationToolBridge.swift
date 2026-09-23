//
//  AutomationToolBridge.swift
//  JARVIS
//
//  The single place where an assistant tool call becomes a real action
//  on the Mac. Everything the model can do passes through this type, so
//  permission checks, path validation, and user confirmations are
//  enforced in exactly one place.
//

import Foundation
import os

/// Executes assistant tool calls against the automation services.
@MainActor
final class AutomationToolBridge: AssistantToolExecuting {

    private let settings: AppSettings
    private let confirmations: AutomationConfirmationCenter
    private let calendarAutomation: CalendarAutomation
    private let calendarStore: CalendarStore
    private let tasks: TaskService
    private let homework: HomeworkService
    private let notes: NoteService
    private let fileSearch: FileSearchService
    private let monitor: SystemMonitorService
    private let shell: ShellCommandRunner
    private let launcher: ApplicationLauncher
    private let browser: BrowserAutomation
    private let finder: FinderAutomation
    private let scripts: AppleScriptRunner
    private let music: MusicAutomation

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Automation")

    init(
        settings: AppSettings,
        confirmations: AutomationConfirmationCenter,
        calendarAutomation: CalendarAutomation,
        calendarStore: CalendarStore,
        tasks: TaskService,
        homework: HomeworkService,
        notes: NoteService,
        fileSearch: FileSearchService,
        monitor: SystemMonitorService
    ) {
        self.settings = settings
        self.confirmations = confirmations
        self.calendarAutomation = calendarAutomation
        self.calendarStore = calendarStore
        self.tasks = tasks
        self.homework = homework
        self.notes = notes
        self.fileSearch = fileSearch
        self.monitor = monitor
        self.shell = ShellCommandRunner.shared
        self.launcher = ApplicationLauncher.shared
        self.browser = BrowserAutomation.shared
        self.finder = FinderAutomation.shared
        self.scripts = AppleScriptRunner.shared
        self.music = MusicAutomation.shared
    }

    // MARK: - Dispatch

    /// Runs one tool call. Never throws: failures are returned as error
    /// results so the model can explain them to the user.
    func execute(_ call: AssistantToolCall) async -> AssistantToolResult {
        guard AssistantToolName.all.contains(call.name) else {
            return .failure(
                summary: call.summary,
                message: "The tool \(call.name) does not exist. Available tools: \(AssistantToolName.all.sorted().joined(separator: ", "))."
            )
        }

        do {
            switch call.name {
            case AssistantToolName.openApplication:
                return try await performOpenApplication(call)
            case AssistantToolName.listApplications:
                return performListApplications(call)
            case AssistantToolName.openURL:
                return try await performOpenURL(call)
            case AssistantToolName.openBrowserTab:
                return try await performOpenBrowserTab(call)
            case AssistantToolName.webSearch:
                return try await performWebSearch(call)
            case AssistantToolName.openFileOrFolder:
                return try performOpenPath(call)
            case AssistantToolName.revealInFinder:
                return try performReveal(call)
            case AssistantToolName.findFiles:
                return try await performFindFiles(call)
            case AssistantToolName.runAppleScript:
                return await performAppleScript(call)
            case AssistantToolName.runTerminalCommand:
                return await performTerminalCommand(call)
            case AssistantToolName.createCalendarEvent:
                return try await performCreateEvent(call)
            case AssistantToolName.createReminder:
                return try await performCreateReminder(call)
            case AssistantToolName.listUpcomingEvents:
                return performListEvents(call)
            case AssistantToolName.controlMusic:
                return try await performMusic(call)
            case AssistantToolName.systemStatus:
                return await performSystemStatus(call)
            case AssistantToolName.createTask:
                return performCreateTask(call)
            case AssistantToolName.createHomework:
                return performCreateHomework(call)
            case AssistantToolName.completeTask:
                return performCompleteTask(call)
            case AssistantToolName.saveNote:
                return performSaveNote(call)
            default:
                return .failure(summary: call.summary, message: "The tool \(call.name) is not implemented.")
            }
        } catch let error as AutomationError {
            logger.debug("Tool \(call.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            var message = error.localizedDescription
            if let suggestion = error.recoverySuggestion {
                message += " " + suggestion
            }
            return .failure(summary: call.summary, message: message)
        } catch {
            logger.error("Tool \(call.name, privacy: .public) threw an unexpected error")
            return .failure(summary: call.summary, message: error.localizedDescription)
        }
    }

    // MARK: - Applications

    private func performOpenApplication(_ call: AssistantToolCall) async throws -> AssistantToolResult {
        guard let name = call.string("application") else {
            return .failure(summary: call.summary, message: "The application name was missing.")
        }
        let application = try await launcher.launch(matching: name)
        return .success(
            summary: "Opened \(application.name)",
            content: "Opened \(application.name) (bundle identifier \(application.bundleIdentifier.isEmpty ? "unknown" : application.bundleIdentifier))."
        )
    }

    private func performListApplications(_ call: AssistantToolCall) -> AssistantToolResult {
        let applications = launcher.installedApplications()
        guard !applications.isEmpty else {
            return .failure(summary: call.summary, message: "No applications were found in the standard folders.")
        }
        let listing = applications.prefix(150).map { application -> String in
            application.bundleIdentifier.isEmpty
                ? application.name
                : "\(application.name) (\(application.bundleIdentifier))"
        }
        return .success(
            summary: "Listed \(applications.count) applications",
            content: "Installed applications:\n" + listing.joined(separator: "\n")
        )
    }

    // MARK: - Browsing

    private func performOpenURL(_ call: AssistantToolCall) async throws -> AssistantToolResult {
        guard let raw = call.string("url") else {
            return .failure(summary: call.summary, message: "The address was missing.")
        }
        let url = try BrowserAutomation.normalizedURL(from: raw)
        guard browser.openInDefaultBrowser(url) else {
            return .failure(summary: call.summary, message: "The default browser refused to open \(url.absoluteString).")
        }
        return .success(summary: "Opened \(url.host ?? url.absoluteString)", content: "Opened \(url.absoluteString) in the default browser.")
    }

    private func performOpenBrowserTab(_ call: AssistantToolCall) async throws -> AssistantToolResult {
        guard let raw = call.string("url") else {
            return .failure(summary: call.summary, message: "The address was missing.")
        }
        let url = try BrowserAutomation.normalizedURL(from: raw)
        let target = BrowserTarget.from(name: call.string("browser"))
        let newWindow = call.bool("new_window") ?? false
        try await browser.open(url: url, in: target, newWindow: newWindow)

        let destination = target == .systemDefault ? "the default browser" : target.displayName
        return .success(
            summary: "Opened \(url.host ?? url.absoluteString) in \(destination)",
            content: "Opened \(url.absoluteString) in \(destination) as a new \(newWindow ? "window" : "tab")."
        )
    }

    private func performWebSearch(_ call: AssistantToolCall) async throws -> AssistantToolResult {
        guard let query = call.string("query") else {
            return .failure(summary: call.summary, message: "The search query was missing.")
        }
        let engine = SearchEngine.from(name: call.string("engine"))
        try await browser.search(query, engine: engine)
        return .success(
            summary: "Searched \(engine.displayName) for \(query)",
            content: "Opened a \(engine.displayName) search for \(query) in the default browser."
        )
    }

    // MARK: - Files

    private func performOpenPath(_ call: AssistantToolCall) throws -> AssistantToolResult {
        guard let path = call.string("path") else {
            return .failure(summary: call.summary, message: "The path was missing.")
        }
        let url = try finder.open(path: path)
        return .success(summary: "Opened \(url.lastPathComponent)", content: "Opened \(url.path).")
    }

    private func performReveal(_ call: AssistantToolCall) throws -> AssistantToolResult {
        guard let path = call.string("path") else {
            return .failure(summary: call.summary, message: "The path was missing.")
        }
        let url = try finder.reveal(path: path)
        return .success(
            summary: "Revealed \(url.lastPathComponent) in Finder",
            content: "Revealed \(url.path) in Finder."
        )
    }

    private func performFindFiles(_ call: AssistantToolCall) async throws -> AssistantToolResult {
        guard let query = call.string("query") else {
            return .failure(summary: call.summary, message: "The search query was missing.")
        }
        let limit = min(max(call.int("limit") ?? 15, 1), 50)
        let matches = try await fileSearch.search(query: query, limit: limit)
        guard !matches.isEmpty else {
            return .success(
                summary: "No files matched \(query)",
                content: "No files in the home folder matched \(query)."
            )
        }
        let listing = matches.map { "\($0.path) (\(SystemMetrics.formatBytes($0.sizeBytes, style: .decimal)), modified \(JarvisTimeFormat.shortDate($0.modifiedAt)))" }
        return .success(
            summary: "Found \(matches.count) file(s) for \(query)",
            content: "Matches for \(query):\n" + listing.joined(separator: "\n")
        )
    }

    // MARK: - Scripts and commands

    private func performAppleScript(_ call: AssistantToolCall) async -> AssistantToolResult {
        guard let script = call.string("script") else {
            return .failure(summary: call.summary, message: "The script was missing.")
        }
        let purpose = call.string("purpose") ?? "Run an AppleScript"

        if settings.confirmAppleScript {
            let approved = await confirmations.requestApproval(
                AutomationConfirmationRequest(
                    title: "Run AppleScript",
                    detail: purpose,
                    payload: script,
                    confirmLabel: "Run script",
                    symbolName: "applescript"
                )
            )
            guard approved else {
                return .denied(
                    summary: "AppleScript declined",
                    message: "The user declined to run the AppleScript. Do not retry unless they ask."
                )
            }
        }

        do {
            let output = try await scripts.run(script: script)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(
                summary: purpose,
                content: trimmed.isEmpty ? "The script ran and returned no output." : "Script output: \(trimmed)"
            )
        } catch let error as AutomationError {
            var message = error.localizedDescription
            if let suggestion = error.recoverySuggestion {
                message += " " + suggestion
            }
            return .failure(summary: "AppleScript failed", message: message)
        } catch {
            return .failure(summary: "AppleScript failed", message: error.localizedDescription)
        }
    }

    private func performTerminalCommand(_ call: AssistantToolCall) async -> AssistantToolResult {
        guard let commandText = call.string("command") else {
            return .failure(summary: call.summary, message: "The command was missing.")
        }
        let purpose = call.string("purpose") ?? "Run a terminal command"

        let command: ValidatedCommand
        do {
            command = try shell.validate(commandText)
        } catch let error as AutomationError {
            return .failure(
                summary: "Command refused",
                message: "\(error.localizedDescription) Only read only commands from the whitelist can be proposed, and no shell metacharacters are accepted."
            )
        }

        let approved = await confirmations.requestApproval(
            AutomationConfirmationRequest(
                title: "Run a terminal command",
                detail: "\(purpose)\n\nCommand: \(command.displayCommand)\n\n\(command.summary)",
                payload: command.displayCommand,
                confirmLabel: "Run \(command.binaryName)",
                symbolName: "terminal",
                timeoutSeconds: 120
            )
        )
        guard approved else {
            return .denied(
                summary: "Command declined by the user",
                message: "The user declined to run \(command.displayCommand). Do not propose it again unless they ask."
            )
        }

        do {
            let result = try await shell.run(command)
            let description = ShellCommandRunner.describe(result, command: command)
            if result.exitCode == 0 {
                return .success(summary: "Ran \(command.displayCommand)", content: description)
            }
            return .failure(summary: "\(command.binaryName) exited with status \(result.exitCode)", message: description)
        } catch let error as AutomationError {
            return .failure(summary: "\(command.binaryName) failed", message: error.localizedDescription)
        } catch {
            return .failure(summary: "\(command.binaryName) failed", message: error.localizedDescription)
        }
    }

    // MARK: - Calendar and reminders

    private func performCreateEvent(_ call: AssistantToolCall) async throws -> AssistantToolResult {
        guard let title = call.string("title") else {
            return .failure(summary: call.summary, message: "The event title was missing.")
        }
        guard let start = JarvisDateParser.date(from: call.string("start")),
              let end = JarvisDateParser.date(from: call.string("end")) else {
            return .failure(
                summary: call.summary,
                message: "The start or end time could not be read. Use ISO 8601 such as 2026-03-14T09:00:00Z."
            )
        }

        if calendarAutomation.calendarAccessState != .granted {
            let granted = await calendarAutomation.requestCalendarAccess()
            guard granted else {
                return .failure(
                    summary: "Calendar access needed",
                    message: "Calendar access was not granted, so the event was not created. The user can enable it in Settings, Permissions."
                )
            }
        }

        let snapshot = try await calendarAutomation.createEvent(
            title: title,
            start: start,
            end: end,
            notes: call.string("notes"),
            location: call.string("location"),
            calendarName: call.string("calendar")
        )
        calendarStore.upsert([snapshot])

        return .success(
            summary: "Created event \(title)",
            content: "Created \(snapshot.title) on \(JarvisTimeFormat.shortDate(snapshot.start)) from \(JarvisTimeFormat.shortTime(snapshot.start)) to \(JarvisTimeFormat.shortTime(snapshot.end)) in the \(snapshot.calendarName.isEmpty ? "default" : snapshot.calendarName) calendar."
        )
    }

    private func performCreateReminder(_ call: AssistantToolCall) async throws -> AssistantToolResult {
        guard let title = call.string("title") else {
            return .failure(summary: call.summary, message: "The reminder title was missing.")
        }
        let due = JarvisDateParser.date(from: call.string("due"))

        if calendarAutomation.remindersAccessState != .granted {
            let granted = await calendarAutomation.requestRemindersAccess()
            guard granted else {
                return .failure(
                    summary: "Reminders access needed",
                    message: "Reminders access was not granted, so nothing was created. The user can enable it in Settings, Permissions."
                )
            }
        }

        try await calendarAutomation.createReminder(
            title: title,
            dueDate: due,
            notes: call.string("notes"),
            listName: call.string("list")
        )

        let dueText = due.map { " due \(JarvisTimeFormat.shortDate($0)) at \(JarvisTimeFormat.shortTime($0))" } ?? ""
        return .success(
            summary: "Created reminder \(title)",
            content: "Created the reminder \(title)\(dueText) in the Reminders app."
        )
    }

    private func performListEvents(_ call: AssistantToolCall) -> AssistantToolResult {
        guard calendarAutomation.calendarAccessState == .granted else {
            return .failure(
                summary: "Calendar access needed",
                message: "Calendar access has not been granted, so the schedule cannot be read. The user can enable it in Settings, Permissions."
            )
        }
        let days = min(max(call.int("days") ?? 7, 1), 30)
        let events = calendarAutomation.upcomingEvents(days: days, limit: 60)
        guard !events.isEmpty else {
            return .success(summary: "No events in the next \(days) day(s)", content: "The calendar is clear for the next \(days) day(s).")
        }
        let listing = events.map { event -> String in
            let day = JarvisTimeFormat.shortDate(event.start)
            let window = event.isAllDay ? "all day" : "\(JarvisTimeFormat.shortTime(event.start)) to \(JarvisTimeFormat.shortTime(event.end))"
            return "\(day), \(window): \(event.title)\(event.location.isEmpty ? "" : " at \(event.location)")"
        }
        return .success(
            summary: "Read \(events.count) event(s)",
            content: "Events for the next \(days) day(s):\n" + listing.joined(separator: "\n")
        )
    }

    // MARK: - Media and system

    private func performMusic(_ call: AssistantToolCall) async throws -> AssistantToolResult {
        let action = MusicAction.from(name: call.string("action"))
        let application = MusicApplication.from(name: call.string("application"))
        let description = try await music.perform(action, in: application)
        return .success(summary: description, content: description)
    }

    private func performSystemStatus(_ call: AssistantToolCall) async -> AssistantToolResult {
        let metrics = monitor.refreshNow()
        let content = """
        Processor: \(Int((metrics.processorUsage * 100).rounded())) percent across \(metrics.processorCount) cores
        Memory: \(SystemMetrics.formatBytes(Int64(metrics.memoryUsedBytes))) of \(SystemMetrics.formatBytes(Int64(metrics.memoryTotalBytes))) used
        Disk: \(SystemMetrics.formatBytes(metrics.diskUsedBytes)) of \(SystemMetrics.formatBytes(metrics.diskTotalBytes)) used
        Network: \(SystemMetrics.formatRate(metrics.downloadBytesPerSecond)) down, \(SystemMetrics.formatRate(metrics.uploadBytesPerSecond)) up on \(metrics.networkInterfaceName)
        Uptime: \(SystemMetrics.formatUptime(metrics.uptimeSeconds))
        """
        return .success(summary: "Read system status", content: content)
    }

    // MARK: - Local data

    private func performCreateTask(_ call: AssistantToolCall) -> AssistantToolResult {
        guard let title = call.string("title") else {
            return .failure(summary: call.summary, message: "The task title was missing.")
        }
        let due = JarvisDateParser.date(from: call.string("due"))
        let priority = TaskPriority(rawValue: call.string("priority")?.lowercased() ?? "") ?? .normal
        let item = tasks.create(title: title, detail: "", dueDate: due, priority: priority)

        let dueText = due.map { " due \(JarvisTimeFormat.shortDate($0))" } ?? ""
        return .success(
            summary: "Added task \(item.title)",
            content: "Added \(item.title) to the dashboard to-do list\(dueText) with \(priority.displayName.lowercased()) priority."
        )
    }

    private func performCreateHomework(_ call: AssistantToolCall) -> AssistantToolResult {
        guard let title = call.string("title"), let subject = call.string("subject") else {
            return .failure(summary: call.summary, message: "Both the assignment title and the subject are required.")
        }
        let due = JarvisDateParser.date(from: call.string("due")) ?? Date()
        let item = homework.create(title: title, subject: subject, detail: "", dueDate: due)
        return .success(
            summary: "Added homework \(item.title)",
            content: "Added \(item.title) for \(item.subject), due \(JarvisTimeFormat.shortDate(item.dueDate))."
        )
    }

    private func performCompleteTask(_ call: AssistantToolCall) -> AssistantToolResult {
        guard let title = call.string("title") else {
            return .failure(summary: call.summary, message: "The task title was missing.")
        }
        guard let item = tasks.completeTask(matching: title) else {
            let open = tasks.openTasks(limit: 12).map(\.title)
            let hint = open.isEmpty ? "The to-do list is empty." : "Open tasks: " + open.joined(separator: ", ")
            return .failure(summary: "No matching task", message: "No open task matched \(title). \(hint)")
        }
        return .success(summary: "Completed \(item.title)", content: "Marked \(item.title) as done.")
    }

    private func performSaveNote(_ call: AssistantToolCall) -> AssistantToolResult {
        guard let text = call.string("text") else {
            return .failure(summary: call.summary, message: "The note text was missing.")
        }
        let note = notes.createNote(text: text)
        return .success(
            summary: "Saved a note",
            content: "Saved a note starting with \(note.headline)."
        )
    }
}
