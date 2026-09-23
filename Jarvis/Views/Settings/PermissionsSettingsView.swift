//
//  PermissionsSettingsView.swift
//  JARVIS
//
//  Every privacy permission JARVIS can ask for, with the reason for each
//  request, a request button, and a deep link into System Settings. The
//  command whitelist is shown here too, because it is the other half of
//  the same safety story.
//

import SwiftUI
import SwiftData
import AppKit

/// Permission status and requests.
struct PermissionsSettingsView: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var automationResult: Bool?
    @State private var autoScriptNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
            JarvisCard(title: "Permissions", symbolName: "lock.shield") {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                    Text("macOS asks for each of these the first time it is needed. JARVIS explains why before the prompt appears, and every request can be revoked in System Settings at any time.")
                        .font(JarvisTheme.Typography.caption(11))
                        .foregroundStyle(JarvisTheme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 6) {
                        ForEach(environment.permissionSummaries) { summary in
                            permissionRow(summary)
                        }
                    }

                    HStack(spacing: JarvisTheme.Spacing.tight) {
                        Button("Run the automation check") {
                            Task {
                                let granted = await environment.probeAutomationPermission()
                                automationResult = granted
                            }
                        }
                        .buttonStyle(.jarvisSecondary)

                        Button("Open Automation settings") {
                            environment.permissions.openSettingsPane(.automation)
                        }
                        .buttonStyle(.jarvisSecondary)

                        Button("Open Accessibility settings") {
                            environment.permissions.openSettingsPane(.accessibility)
                        }
                        .buttonStyle(.jarvisSecondary)

                        Button("Request accessibility") {
                            _ = environment.permissions.hasAccessibilityPermission(promptIfNeeded: true)
                        }
                        .buttonStyle(.jarvisSecondary)
                    }

                    if let automationResult {
                        Text(automationResult
                             ? "The automation probe reached Finder, so Apple Events are permitted."
                             : "macOS refused the automation probe. Open Automation settings, enable JARVIS for the target application, then run the check again.")
                            .font(JarvisTheme.Typography.caption(11))
                            .foregroundStyle(automationResult ? JarvisTheme.Palette.success : JarvisTheme.Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            JarvisCard(title: "Accessibility and automation", symbolName: "hand.raised") {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
                    explanation(
                        title: "Automation (Apple Events)",
                        body: "Sent to another application when JARVIS opens a browser tab, controls music, or asks Finder for information. macOS records the grant per target application."
                    )
                    explanation(
                        title: "Accessibility",
                        body: "Needed only for reading window state and driving menus. JARVIS works without it, so grant it only if you want those features."
                    )
                    explanation(
                        title: "Calendar and reminders",
                        body: "EventKit access is required to read your schedule and to create events or reminders you ask for."
                    )
                    explanation(
                        title: "Microphone and speech",
                        body: "The microphone opens only while you hold the dictation button. Audio is transcribed in place and never written to disk."
                    )

                    if let autoScriptNote {
                        Text(autoScriptNote)
                            .font(JarvisTheme.Typography.caption(10))
                            .foregroundStyle(JarvisTheme.Palette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
            }

            CommandWhitelistSection()
        }
        .onAppear {
            automationResult = environment.automationProbeResult
            autoScriptNote = environment.settings.confirmAppleScript
                ? "AppleScript runs are confirmed by you before they execute."
                : "AppleScript runs execute without a confirmation dialog. Terminal commands still always ask."
        }
    }

    private func permissionRow(_ summary: PermissionSummary) -> some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.regular) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.title)
                        .font(JarvisTheme.Typography.headline(12))
                        .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    StatusChip(text: summary.state.displayName, tint: tint(for: summary.state))
                }
                Text(summary.purpose)
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                if summary.canRequest {
                    Button("Request") {
                        Task { await request(summary) }
                    }
                    .buttonStyle(.jarvisSecondary)
                }
                if let url = summary.settingsURL {
                    Button("System Settings") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.jarvisSecondary)
                }
            }
        }
        .padding(JarvisTheme.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(JarvisTheme.Palette.canvas.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
        )
    }

    private func explanation(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(JarvisTheme.Typography.headline(11))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Text(body)
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func tint(for state: PermissionState) -> Color {
        switch state {
        case .granted: return JarvisTheme.Palette.success
        case .denied, .restricted: return JarvisTheme.Palette.danger
        case .notDetermined: return JarvisTheme.Palette.warning
        case .unknown: return JarvisTheme.Palette.textTertiary
        }
    }

    private func request(_ summary: PermissionSummary) async {
        switch summary.id {
        case "calendar":
            _ = await environment.requestCalendarAccess()
        case "reminders":
            _ = await environment.requestRemindersAccess()
        case "microphone":
            _ = await environment.requestMicrophoneAccess()
        case "automation":
            automationResult = await environment.probeAutomationPermission()
        case "accessibility":
            _ = environment.permissions.hasAccessibilityPermission(promptIfNeeded: true)
        default:
            break
        }
    }
}

// MARK: - Whitelist

/// Shows the commands the assistant is allowed to propose.
struct CommandWhitelistSection: View {

    var body: some View {
        JarvisCard(title: "Command whitelist", symbolName: "terminal") {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                Text("The assistant can only propose read only commands from this list. Commands never pass through a shell, arguments are validated against each rule set, paths must stay inside your home folder, /tmp, /Applications, or /Volumes, and you approve the exact text before anything runs.")
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(CommandWhitelist.groupedByCategory) { group in
                    if !group.binaries.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            SectionLabel(text: group.category.displayName)
                            VStack(spacing: 4) {
                                ForEach(group.binaries) { binary in
                                    HStack(alignment: .top, spacing: JarvisTheme.Spacing.tight) {
                                        Text(binary.path)
                                            .font(JarvisTheme.Typography.mono(10))
                                            .foregroundStyle(JarvisTheme.Palette.accent)
                                            .frame(width: 150, alignment: .leading)
                                        Text(binary.summary)
                                            .font(JarvisTheme.Typography.caption(10))
                                            .foregroundStyle(JarvisTheme.Palette.textTertiary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                }

                Text("Binaries that write, delete, install, download, escalate privileges, or open a shell are not present in this list, so the assistant cannot propose them at all.")
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Quick Tools

/// Compact Quick Tools summary inside Settings.
struct QuickToolsSettingsSection: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \AppShortcut.sortOrder, order: .forward) private var shortcuts: [AppShortcut]

    var body: some View {
        JarvisCard(title: "Quick Tools", symbolName: "bolt") {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                Text("Tiles are managed on the Apps screen. Toggle a tile here to show or hide it on the dashboard.")
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)

                ForEach(shortcuts) { shortcut in
                    HStack(spacing: JarvisTheme.Spacing.regular) {
                        Image(systemName: shortcut.symbolName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: UInt32(truncatingIfNeeded: shortcut.tintHex)))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shortcut.name)
                                .font(JarvisTheme.Typography.headline(12))
                                .foregroundStyle(JarvisTheme.Palette.textPrimary)
                            Text("\(shortcut.kind.displayName) - \(shortcut.target)")
                                .font(JarvisTheme.Typography.caption(10))
                                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: Binding(
                            get: { shortcut.isEnabled },
                            set: { newValue in
                                environment.quickTools.setEnabled(newValue, for: shortcut)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(JarvisTheme.Palette.accent)
                    }
                    .padding(JarvisTheme.Spacing.tight)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(JarvisTheme.Palette.canvas.opacity(0.4))
                    )
                }

                Button("Manage tiles on the Apps screen") {
                    environment.appState.destination = .apps
                }
                .buttonStyle(.jarvisSecondary)
            }
        }
    }
}
