//
//  AppEnvironment.swift
//  JARVIS
//
//  Composition root. Every service, store, and view model is created
//  once here and injected into the view tree, which keeps view code free
//  of construction logic and makes dependencies explicit.
//

import Foundation
import SwiftUI
import SwiftData
import EventKit

/// Owns the long lived objects the application needs.
@MainActor
@Observable
final class AppEnvironment {

    // MARK: - Storage

    /// SwiftData container backing tasks, homework, notes, and caches.
    let modelContainer: ModelContainer

    // MARK: - Preferences and secrets

    /// Non secret preferences.
    let settings: AppSettings
    /// Keychain access for provider API keys.
    let apiKeys: APIKeyStore

    // MARK: - Domain services

    /// Wraps the EventKit store.
    let calendarAutomation: CalendarAutomation
    /// Caches calendar events into SwiftData.
    let calendarStore: CalendarStore
    /// To-do list mutations.
    let tasks: TaskService
    /// Homework tracker mutations.
    let homework: HomeworkService
    /// Quick note mutations.
    let notes: NoteService
    /// Folder browsing and file search.
    let fileSearch: FileSearchService
    /// Quick Tools launcher.
    let quickTools: QuickToolsService

    // MARK: - Live monitors

    /// Machine statistics.
    let monitor: SystemMonitorService
    /// Local weather.
    let weather: WeatherService
    /// Ticking clock.
    let clock: ClockService
    /// Focus timer.
    let focusTimer: FocusTimerService

    // MARK: - Permissions and confirmation

    /// Privacy permission state and requests.
    let permissions: PermissionService
    /// Approvals for commands and scripts.
    let confirmations: AutomationConfirmationCenter

    // MARK: - Assistant

    /// Provider agnostic chat loop.
    let chatService: AIChatService
    /// Executes assistant tool calls.
    let automation: AutomationToolBridge
    /// Assistant panel state.
    let chat: ChatViewModel
    /// Dictation.
    let speech: SpeechRecognitionService

    // MARK: - Shell

    /// Sidebar and panel state.
    let appState: AppState

    /// Result of the most recent automation permission probe, when one ran.
    var automationProbeResult: Bool?

    // MARK: - Lifecycle

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = modelContainer.mainContext

        let settings = AppSettings()
        let keychain = KeychainStore.shared
        let apiKeys = APIKeyStore(keychain: keychain)
        let eventStore = EKEventStore()
        let permissions = PermissionService(eventStore: eventStore)
        let calendarAutomation = CalendarAutomation(store: eventStore)
        let calendarStore = CalendarStore(context: context, automation: calendarAutomation)
        let tasks = TaskService(context: context)
        let homework = HomeworkService(context: context)
        let notes = NoteService(context: context)
        let fileSearch = FileSearchService()
        let quickTools = QuickToolsService()
        let monitor = SystemMonitorService()
        let weather = WeatherService()
        let clock = ClockService()
        let speech = SpeechRecognitionService()
        let focusTimer = FocusTimerService(
            context: context,
            defaultPreset: FocusPreset(rawValue: settings.focusPresetMinutes) ?? .short
        )
        let confirmations = AutomationConfirmationCenter()
        let chatService = AIChatService()
        let appState = AppState()

        let automation = AutomationToolBridge(
            settings: settings,
            confirmations: confirmations,
            calendarAutomation: calendarAutomation,
            calendarStore: calendarStore,
            tasks: tasks,
            homework: homework,
            notes: notes,
            fileSearch: fileSearch,
            monitor: monitor
        )

        let chat = ChatViewModel(
            context: context,
            settings: settings,
            apiKeys: apiKeys,
            chatService: chatService,
            executor: automation,
            calendarAutomation: calendarAutomation,
            permissions: permissions,
            speech: speech
        )

        self.settings = settings
        self.apiKeys = apiKeys
        self.calendarAutomation = calendarAutomation
        self.calendarStore = calendarStore
        self.tasks = tasks
        self.homework = homework
        self.notes = notes
        self.fileSearch = fileSearch
        self.quickTools = quickTools
        self.monitor = monitor
        self.weather = weather
        self.clock = clock
        self.focusTimer = focusTimer
        self.permissions = permissions
        self.confirmations = confirmations
        self.chatService = chatService
        self.automation = automation
        self.chat = chat
        self.speech = speech
        self.appState = appState

        quickTools.seedDefaultsIfNeeded(context: context)
        chat.loadHistory()
        focusTimer.refreshTodayTotals()
    }

    // MARK: - Startup

    /// Starts the timers and performs the first refresh.
    func start() {
        clock.start()
        monitor.start()
        Task { [weak self] in
            await self?.refreshAll()
        }
    }

    /// Stops every background timer. Called when the app terminates.
    func stop() {
        clock.stop()
        monitor.stop()
        speech.stop()
    }

    /// Refreshes calendar and weather data.
    func refreshAll() async {
        await calendarStore.refresh()
        await weather.refresh(settings: settings)
    }

    // MARK: - Permissions

    /// Runs a harmless Apple Event so macOS can prompt for automation
    /// permission, and records the result for the Settings screen.
    @discardableResult
    func probeAutomationPermission() async -> Bool {
        let granted = await AppleScriptRunner.shared.probeAutomationPermission()
        automationProbeResult = granted
        return granted
    }

    /// Permission rows shown by the Settings screen.
    var permissionSummaries: [PermissionSummary] {
        permissions.makeSummaries(automationProbeSucceeded: automationProbeResult)
    }

    /// Requests calendar and reminders access, prompting when needed.
    func requestCalendarAccess() async -> Bool {
        let granted = await calendarAutomation.requestCalendarAccess()
        if granted {
            await calendarStore.refresh()
        }
        return granted
    }

    /// Requests reminders access.
    func requestRemindersAccess() async -> Bool {
        await calendarAutomation.requestRemindersAccess()
    }

    /// Requests microphone access for dictation.
    func requestMicrophoneAccess() async -> Bool {
        await permissions.requestMicrophoneAccess()
    }
}
