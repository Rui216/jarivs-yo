//
//  ChatViewModel.swift
//  JARVIS
//
//  Drives the assistant panel: turns the input into a provider request,
//  streams the answer into the transcript, shows which automation step is
//  running, and persists the conversation so it survives a relaunch.
//

import Foundation
import SwiftData
import AppKit
import os

/// Assistant panel state.
@MainActor
@Observable
final class ChatViewModel {

    /// One rendered message.
    struct Bubble: Identifiable, Equatable {
        /// Identifier used for list rendering.
        let id: UUID
        /// Who wrote the message.
        var role: ChatRole
        /// Visible text.
        var text: String
        /// One line summaries of automation performed while answering.
        var actionSummaries: [String]
        /// Error text when the turn failed.
        var errorText: String
        /// Footer note such as a budget warning.
        var footnote: String
        /// When the message was created.
        var timestamp: Date
        /// True while tokens are still arriving.
        var isStreaming: Bool

        init(
            id: UUID = UUID(),
            role: ChatRole,
            text: String,
            actionSummaries: [String] = [],
            errorText: String = "",
            footnote: String = "",
            timestamp: Date = Date(),
            isStreaming: Bool = false
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.actionSummaries = actionSummaries
            self.errorText = errorText
            self.footnote = footnote
            self.timestamp = timestamp
            self.isStreaming = isStreaming
        }
    }

    /// Text bound to the input field.
    var draft: String = ""

    /// Transcript, oldest first.
    private(set) var bubbles: [Bubble] = []

    /// What the assistant is doing right now.
    private(set) var activity: AssistantActivity = .idle

    /// True when the assistant cannot run because no key is stored.
    private(set) var needsProviderKey = false

    /// Last error message, cleared on the next successful send.
    private(set) var lastErrorMessage: String?

    private let context: ModelContext
    private let settings: AppSettings
    private let apiKeys: APIKeyStore
    private let chatService: AIChatService
    private let executor: AutomationToolBridge
    private let calendarAutomation: CalendarAutomation
    private let permissions: PermissionService
    private let speech: SpeechRecognitionService
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Assistant")

    private var conversation: [AIMessage] = []
    private var runTask: Task<Void, Never>?
    private var streamingBubbleID: UUID?

    init(
        context: ModelContext,
        settings: AppSettings,
        apiKeys: APIKeyStore,
        chatService: AIChatService,
        executor: AutomationToolBridge,
        calendarAutomation: CalendarAutomation,
        permissions: PermissionService,
        speech: SpeechRecognitionService
    ) {
        self.context = context
        self.settings = settings
        self.apiKeys = apiKeys
        self.chatService = chatService
        self.executor = executor
        self.calendarAutomation = calendarAutomation
        self.permissions = permissions
        self.speech = speech
    }

    // MARK: - Derived state

    /// True while a response is being produced.
    var isBusy: Bool { activity.isBusy }

    /// True while the microphone is open.
    var isListening: Bool { speech.isListening }

    /// Message describing a dictation problem, if any.
    var dictationError: String? { speech.errorMessage }

    /// Provider currently selected.
    var provider: AIProviderID { settings.selectedProvider }

    /// Model currently selected.
    var model: String { settings.model(for: settings.selectedProvider) }

    /// Label shown under the assistant header.
    var statusText: String {
        if needsProviderKey { return "Add an API key in Settings" }
        return "\(provider.shortName) - \(activity.label)"
    }

    // MARK: - History

    /// Loads the most recent messages from local storage.
    func loadHistory() {
        var descriptor = FetchDescriptor<ChatMessageRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        let records = (try? context.fetch(descriptor))?.reversed() ?? []

        bubbles = records.map { record in
            Bubble(
                role: record.role,
                text: record.text,
                actionSummaries: record.actionSummary.isEmpty ? [] : [record.actionSummary],
                errorText: record.errorText,
                timestamp: record.createdAt,
                isStreaming: false
            )
        }

        conversation = records.compactMap { record in
            guard record.errorText.isEmpty else { return nil }
            switch record.role {
            case .user: return AIMessage.text(.user, record.text)
            case .assistant: return record.text.isEmpty ? nil : AIMessage.text(.assistant, record.text)
            }
        }

        needsProviderKey = !apiKeys.hasKey(for: settings.selectedProvider)
    }

    /// Clears the transcript, both on screen and on disk.
    func clearConversation() {
        cancel()
        let existing = (try? context.fetch(FetchDescriptor<ChatMessageRecord>())) ?? []
        for record in existing {
            context.delete(record)
        }
        try? context.save()
        bubbles.removeAll()
        conversation.removeAll()
        lastErrorMessage = nil
    }

    // MARK: - Sending

    /// Sends the draft, or an explicit prompt, to the assistant.
    func send(_ override: String? = nil) {
        let message = (override ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isBusy else { return }
        if override == nil {
            draft = ""
        }
        lastErrorMessage = nil

        appendPersisted(role: .user, text: message, actionSummary: "", errorText: "")
        conversation.append(.text(.user, message))

        let provider = settings.selectedProvider
        guard let apiKey = apiKeys.secret(for: provider) else {
            needsProviderKey = true
            let text = "I need an API key for \(provider.displayName) before I can answer. Open Settings, AI Providers, and save a key."
            appendPersisted(role: .assistant, text: text, actionSummary: "", errorText: text)
            return
        }
        needsProviderKey = false

        let bubbleID = UUID()
        bubbles.append(Bubble(id: bubbleID, role: .assistant, text: "", isStreaming: true))
        streamingBubbleID = bubbleID
        activity = .thinking

        let request = AssistantRunRequest(
            providerID: provider,
            model: settings.model(for: provider),
            apiKey: apiKey,
            systemPrompt: makeSystemPrompt(),
            messages: conversation,
            tools: settings.enabledToolSchemas
        )

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in self.chatService.run(
                    request: request,
                    executor: self.executor,
                    limits: .standard
                ) {
                    self.handle(event, bubbleID: bubbleID)
                }
            } catch let error as AIServiceError {
                self.fail(message: error.errorDescription ?? "The request failed.", bubbleID: bubbleID)
            } catch {
                self.fail(message: error.localizedDescription, bubbleID: bubbleID)
            }
        }
    }

    /// Cancels the request in flight and keeps whatever text arrived.
    func cancel() {
        runTask?.cancel()
        runTask = nil

        if let streamingBubbleID, let index = bubbles.firstIndex(where: { $0.id == streamingBubbleID }) {
            bubbles[index].isStreaming = false
            if !bubbles[index].text.isEmpty {
                bubbles[index].footnote = "Stopped"
            }
        }
        streamingBubbleID = nil
        activity = .idle
    }

    // MARK: - Dictation

    /// Starts or stops microphone dictation into the draft field.
    func toggleDictation() async {
        if speech.isListening {
            speech.stop()
            activity = .idle
            return
        }
        speech.onTranscriptChange = { [weak self] text in
            self?.draft = text
        }
        activity = .listening
        await speech.start()
        if !speech.isListening {
            activity = .idle
        }
    }

    // MARK: - Event handling

    private func handle(_ event: AssistantRunEvent, bubbleID: UUID) {
        switch event {
        case .iterationStarted(_):
            if case .working = activity {
                activity = .thinking
            }

        case .textDelta(let chunk):
            appendStreamingText(chunk, bubbleID: bubbleID)

        case .toolStarted(let call):
            activity = .working(call.summary)

        case .toolFinished(_, let result):
            if let index = bubbles.firstIndex(where: { $0.id == bubbleID }),
               !result.summary.isEmpty,
               !bubbles[index].actionSummaries.contains(result.summary) {
                bubbles[index].actionSummaries.append(result.summary)
            }
            activity = .thinking

        case .completed(let outcome):
            finish(outcome: outcome, bubbleID: bubbleID)
        }
    }

    private func appendStreamingText(_ chunk: String, bubbleID: UUID) {
        guard let index = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        bubbles[index].text += chunk
    }

    private func finish(outcome: AssistantRunOutcome, bubbleID: UUID) {
        conversation = outcome.conversation

        guard let index = bubbles.firstIndex(where: { $0.id == bubbleID }) else {
            activity = .idle
            streamingBubbleID = nil
            return
        }

        var text = bubbles[index].text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !outcome.finalText.isEmpty {
            text = outcome.finalText
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "Done."
        }

        bubbles[index].text = text
        bubbles[index].isStreaming = false
        if outcome.didExhaustBudget {
            bubbles[index].footnote = "Stopped after reaching the step limit. Ask again to continue."
        }

        activity = .idle
        streamingBubbleID = nil
        runTask = nil

        persist(
            role: .assistant,
            text: text,
            actionSummary: outcome.actionSummaries.joined(separator: " | "),
            errorText: ""
        )
    }

    private func fail(message: String, bubbleID: UUID) {
        if let index = bubbles.firstIndex(where: { $0.id == bubbleID }) {
            bubbles[index].isStreaming = false
            if bubbles[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bubbles[index].text = message
            }
            bubbles[index].errorText = message
        }
        activity = .idle
        streamingBubbleID = nil
        runTask = nil
        lastErrorMessage = message

        logger.debug("Assistant turn failed: \(message, privacy: .public)")
        persist(role: .assistant, text: message, actionSummary: "", errorText: message)
    }

    // MARK: - Persistence

    private func appendPersisted(role: ChatRole, text: String, actionSummary: String, errorText: String) {
        bubbles.append(Bubble(
            role: role,
            text: text,
            actionSummaries: [],
            errorText: errorText,
            timestamp: Date()
        ))
        persist(role: role, text: text, actionSummary: actionSummary, errorText: errorText)
    }

    private func persist(role: ChatRole, text: String, actionSummary: String, errorText: String) {
        let record = ChatMessageRecord(
            role: role,
            text: text,
            actionSummary: actionSummary,
            errorText: errorText
        )
        context.insert(record)
        do {
            try context.save()
        } catch {
            logger.error("Chat history save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Prompt

    /// Builds the system prompt from live environment details.
    private func makeSystemPrompt() -> String {
        let context = AssistantContext(
            userName: settings.userName,
            tools: settings.enabledToolSchemas,
            frontmostApplication: NSWorkspace.shared.frontmostApplication?.localizedName,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            hasCalendarAccess: calendarAutomation.calendarAccessState == .granted,
            hasAccessibilityAccess: permissions.accessibilityState == .granted
        )
        return context.systemPrompt()
    }
}
