//
//  SetupSheet.swift
//  JARVIS
//
//  First run setup: the name used in greetings, the permissions the
//  dashboard depends on, and a pointer to the API key screen. Each
//  permission row explains why it is needed before macOS prompts.
//

import SwiftUI

/// First run setup sheet.
struct SetupSheet: View {

    @Environment(AppEnvironment.self) private var environment
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var isRequestingCalendar = false
    @State private var isRequestingReminders = false
    @State private var automationResult: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
            header
            nameSection
            permissionSection
            providerSection
            footer
        }
        .padding(JarvisTheme.Spacing.section)
        .frame(width: 560)
        .background(JarvisTheme.canvasGradient)
        .onAppear {
            name = environment.settings.userName
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            HStack(spacing: JarvisTheme.Spacing.tight) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(JarvisTheme.accentGradient)
                        .frame(width: 40, height: 40)
                        .jarvisGlow(radius: 16, opacity: 0.4)
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(JarvisTheme.Palette.canvas)
                }
                Text("Welcome to JARVIS")
                    .font(JarvisTheme.Typography.display(22))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
            }
            Text("A two minute setup. Everything here can be changed later in Settings.")
                .font(JarvisTheme.Typography.body(12))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Your name")
            TextField("Name used in greetings", text: $name)
                .jarvisField()
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            SectionLabel(text: "Permissions")

            permissionRow(
                symbolName: "calendar",
                title: "Calendar",
                detail: "Reads today's schedule and creates events you ask for.",
                state: environment.calendarAutomation.calendarAccessState,
                isBusy: isRequestingCalendar
            ) {
                isRequestingCalendar = true
                Task {
                    _ = await environment.requestCalendarAccess()
                    isRequestingCalendar = false
                }
            }

            permissionRow(
                symbolName: "checklist",
                title: "Reminders",
                detail: "Creates reminders for homework and tasks when asked.",
                state: environment.calendarAutomation.remindersAccessState,
                isBusy: isRequestingReminders
            ) {
                isRequestingReminders = true
                Task {
                    _ = await environment.requestRemindersAccess()
                    isRequestingReminders = false
                }
            }

            permissionRow(
                symbolName: "applescript",
                title: "Automation",
                detail: "Opens applications, drives browser tabs, and controls music. macOS asks once per target application.",
                state: automationResult.map { $0 ? .granted : .denied } ?? .notDetermined,
                isBusy: false
            ) {
                Task { automationResult = await environment.probeAutomationPermission() }
            }
        }
    }

    private func permissionRow(
        symbolName: String,
        title: String,
        detail: String,
        state: PermissionState,
        isBusy: Bool,
        request: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.regular) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(JarvisTheme.Palette.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(JarvisTheme.Typography.headline(12))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                Text(detail)
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if state == .granted {
                StatusChip(text: "Granted", symbolName: "checkmark", tint: JarvisTheme.Palette.success)
            } else {
                Button(isBusy ? "Requesting..." : "Request") {
                    request()
                }
                .buttonStyle(.jarvisSecondary)
                .disabled(isBusy)
            }
        }
        .padding(JarvisTheme.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .fill(JarvisTheme.Palette.card.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
        )
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Assistant provider")
            HStack(spacing: JarvisTheme.Spacing.tight) {
                Text("Add an API key for Anthropic, OpenAI, Google, OpenRouter, or Groq in Settings, AI Providers. Keys are stored in the macOS keychain and never leave this Mac except in requests to the provider you choose.")
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            Button("Open Settings instead") {
                environment.appState.destination = .settings
                finish()
            }
            .buttonStyle(.jarvisSecondary)

            Spacer()

            Button("Get started") {
                finish()
            }
            .buttonStyle(.jarvisPrimary)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        environment.settings.userName = trimmed.isEmpty ? environment.settings.userName : trimmed
        environment.settings.completedSetup = true
        environment.settings.persist()
        isPresented = false
    }
}
