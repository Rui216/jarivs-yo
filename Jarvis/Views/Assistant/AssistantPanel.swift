//
//  AssistantPanel.swift
//  JARVIS
//
//  The assistant column: streaming transcript, status line, input field,
//  and the dictation button. All provider specific behaviour lives
//  behind ChatViewModel, so this view only renders state and forwards
//  user intent.
//

import SwiftUI
import AppKit

/// Assistant column with transcript and input.
struct AssistantColumn: View {

    var body: some View {
        VStack(spacing: 0) {
            AssistantPanel()
            Divider().overlay(JarvisTheme.Palette.stroke)
            QuickNotesCard()
        }
        .background(JarvisTheme.Palette.canvasElevated)
    }
}

/// Chat transcript and composer.
struct AssistantPanel: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var scrollTarget = UUID()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(JarvisTheme.Palette.stroke)
            transcript
            Divider().overlay(JarvisTheme.Palette.stroke)
            composer
        }
        .frame(maxHeight: .infinity)
        .onChange(of: environment.chat.bubbles.count) { _, _ in
            scrollToBottom()
        }
        .onChange(of: environment.appState.pendingAssistantPrompt) { _, newValue in
            guard let prompt = newValue else { return }
            environment.chat.draft = prompt
            environment.appState.pendingAssistantPrompt = nil
            inputFocused = true
        }
        .onAppear {
            scrollToBottom(animated: false)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            ZStack {
                Circle()
                    .fill(JarvisTheme.Palette.accent.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("AI Assistant")
                    .font(JarvisTheme.Typography.title(14))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                HStack(spacing: 5) {
                    StatusDot(color: environment.chat.activity.tint, size: 6)
                    Text(environment.chat.statusText)
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if environment.chat.isBusy {
                Button {
                    environment.chat.cancel()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(JarvisTheme.Palette.danger)
                .help("Stop the response")
            }

            Menu {
                Button("Clear conversation") {
                    environment.chat.clearConversation()
                }
                Button("AI provider settings") {
                    environment.appState.destination = .settings
                }
                Divider()
                Button("Check automation permission") {
                    Task { await environment.probeAutomationPermission() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
        .padding(.horizontal, JarvisTheme.Spacing.regular)
        .padding(.vertical, JarvisTheme.Spacing.regular)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                    if environment.chat.bubbles.isEmpty {
                        welcome
                    }

                    ForEach(environment.chat.bubbles) { bubble in
                        ChatBubbleView(bubble: bubble)
                            .id(bubble.id)
                    }

                    if environment.chat.isBusy, let working = workingLabel {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(working)
                                .font(JarvisTheme.Typography.caption(10))
                                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                        }
                        .padding(.leading, 4)
                        .id("working-indicator")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("transcript-bottom")
                }
                .padding(.horizontal, JarvisTheme.Spacing.regular)
                .padding(.vertical, JarvisTheme.Spacing.regular)
            }
            .onChange(of: environment.chat.bubbles.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .onChange(of: environment.chat.activity) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            Text("Ready when you are")
                .font(JarvisTheme.Typography.headline(13))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Text("Ask for anything on this Mac: open an application, start a search, put an event on the calendar, find a file, add a task, or check system status. Anything that changes your machine is shown to you before it runs.")
                .font(JarvisTheme.Typography.caption(11))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        environment.chat.send(suggestion)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(suggestion)
                                .font(JarvisTheme.Typography.caption(11))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(JarvisTheme.Palette.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(JarvisTheme.Palette.accent.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(JarvisTheme.Palette.accent.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    private var suggestions: [String] {
        [
            "What is on my calendar for the rest of today",
            "Open Chrome in a new tab with the news",
            "Add a task to submit the lab report by Friday",
            "How is the machine doing right now"
        ]
    }

    // MARK: - Composer

    private var composer: some View {
        @Bindable var chat = environment.chat

        return VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            if let error = environment.chat.dictationError {
                Text(error)
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if environment.chat.needsProviderKey {
                Button {
                    environment.appState.destination = .settings
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add an API key for \(environment.settings.selectedProvider.displayName)")
                            .font(JarvisTheme.Typography.caption(11))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(JarvisTheme.Palette.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(JarvisTheme.Palette.warning.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(JarvisTheme.Palette.warning.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: JarvisTheme.Spacing.tight) {
                TextField("Ask JARVIS", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .jarvisField(focused: inputFocused)
                    .focused($inputFocused)
                    .onSubmit {
                        environment.chat.send()
                    }

                Button {
                    Task { await environment.chat.toggleDictation() }
                } label: {
                    Image(systemName: environment.chat.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(environment.chat.isListening
                                         ? JarvisTheme.Palette.canvas
                                         : JarvisTheme.Palette.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                                .fill(environment.chat.isListening
                                      ? AnyShapeStyle(JarvisTheme.Palette.danger)
                                      : AnyShapeStyle(JarvisTheme.Palette.accent.opacity(0.12)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                                .strokeBorder(JarvisTheme.Palette.accent.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(environment.chat.isListening ? "Stop dictation" : "Dictate a message")

                Button {
                    environment.chat.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(JarvisTheme.Palette.canvas)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                                .fill(JarvisTheme.accentGradient)
                        )
                }
                .buttonStyle(.plain)
                .disabled(environment.chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || environment.chat.isBusy)
                .help("Send")
            }

            HStack(spacing: 6) {
                Text(environment.settings.selectedProvider.shortName)
                    .font(JarvisTheme.Typography.caption(9))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                Text(environment.settings.model(for: environment.settings.selectedProvider))
                    .font(JarvisTheme.Typography.caption(9))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("Return sends, Shift+Return adds a line")
                    .font(JarvisTheme.Typography.caption(9))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary.opacity(0.8))
            }
        }
        .padding(JarvisTheme.Spacing.regular)
    }

    // MARK: - Helpers

    private var workingLabel: String? {
        switch environment.chat.activity {
        case .working(let detail): return detail
        case .thinking: return "Thinking"
        case .listening: return "Listening"
        case .idle: return nil
        }
    }

    private func scrollToBottom(animated: Bool = true) {
        scrollTarget = UUID()
    }
}
