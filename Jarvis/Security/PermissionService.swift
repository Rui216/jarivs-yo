//
//  PermissionService.swift
//  JARVIS
//
//  Central place for every privacy permission the app depends on:
//  calendar, reminders, accessibility, automation, microphone, and
//  speech recognition. Each helper explains why the permission is
//  needed and deep links to the matching System Settings pane when
//  macOS will not show a prompt again.
//

import Foundation
import AppKit
import ApplicationServices
import EventKit
import AVFoundation

/// Normalized permission state used across the UI.
enum PermissionState: String {
    case notDetermined
    case granted
    case denied
    case restricted
    case unknown

    /// Caption rendered in the permissions list.
    var displayName: String {
        switch self {
        case .notDetermined: return "Not requested"
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted by policy"
        case .unknown: return "Unknown"
        }
    }
}

/// A single permission row rendered by the Settings screen.
struct PermissionSummary: Identifiable {
    /// Stable identifier used for list rendering.
    let id: String
    /// Display name of the permission.
    let title: String
    /// Why the app needs the permission.
    let purpose: String
    /// Current state.
    let state: PermissionState
    /// Deep link into System Settings, when one is available.
    let settingsURL: URL?

    /// True when the row should offer a request action.
    var canRequest: Bool {
        state == .notDetermined
    }
}

/// System Settings panes that can be deep linked from the app.
enum PrivacyPane {
    case accessibility
    case automation
    case calendars
    case reminders
    case microphone
    case speechRecognition

    /// URL that opens the matching pane in System Settings.
    var url: URL? {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .automation: anchor = "Privacy_Automation"
        case .calendars: anchor = "Privacy_Calendars"
        case .reminders: anchor = "Privacy_Reminders"
        case .microphone: anchor = "Privacy_Microphone"
        case .speechRecognition: anchor = "Privacy_SpeechRecognition"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

/// Queries and requests privacy permissions.
@MainActor
final class PermissionService {

    private let eventStore: EKEventStore

    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    // MARK: - Calendar and reminders

    /// Current calendar authorization state.
    var calendarState: PermissionState {
        Self.normalize(EKEventStore.authorizationStatus(for: .event))
    }

    /// Current reminders authorization state.
    var remindersState: PermissionState {
        Self.normalize(EKEventStore.authorizationStatus(for: .reminder))
    }

    /// Requests calendar access. Returns true when access is granted.
    func requestCalendarAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Requests reminders access. Returns true when access is granted.
    func requestRemindersAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Accessibility

    /// Whether the process is trusted for accessibility control.
    ///
    /// Accessibility permission is required to read window titles and to
    /// drive other applications through System Events based automation.
    var accessibilityState: PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Asks the system to show the accessibility prompt once.
    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Reports whether the app holds accessibility trust, optionally prompting.
    func hasAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        if promptIfNeeded {
            promptForAccessibility()
        }
        return AXIsProcessTrusted()
    }

    // MARK: - Microphone and speech

    /// Current microphone authorization state.
    var microphoneState: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    /// Requests microphone access. Returns true when access is granted.
    func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Deep links

    /// Opens the matching System Settings pane.
    func openSettingsPane(_ pane: PrivacyPane) {
        guard let url = pane.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the app specific automation pane.
    func openAutomationSettings() {
        openSettingsPane(.automation)
    }

    // MARK: - Summaries

    /// Builds the permission list rendered by Settings, in the order the
    /// app normally requests them.
    ///
    /// Automation status cannot be queried without triggering a system
    /// prompt, so that row is described as "asked on first use" and links
    /// straight to the automation pane.
    func makeSummaries(automationProbeSucceeded: Bool?) -> [PermissionSummary] {
        var rows: [PermissionSummary] = []

        rows.append(
            PermissionSummary(
                id: "automation",
                title: "Automation (Apple Events)",
                purpose: "Open and control other applications, manage browser tabs, and reveal files in Finder.",
                state: automationProbeSucceeded.map { $0 ? .granted : .denied } ?? .notDetermined,
                settingsURL: PrivacyPane.automation.url
            )
        )

        rows.append(
            PermissionSummary(
                id: "accessibility",
                title: "Accessibility",
                purpose: "Let the assistant drive menus and read window state in other applications.",
                state: accessibilityState,
                settingsURL: PrivacyPane.accessibility.url
            )
        )

        rows.append(
            PermissionSummary(
                id: "calendar",
                title: "Calendar",
                purpose: "Show today's schedule in Up Next and create events you ask for.",
                state: calendarState,
                settingsURL: PrivacyPane.calendars.url
            )
        )

        rows.append(
            PermissionSummary(
                id: "reminders",
                title: "Reminders",
                purpose: "Create reminders for homework and tasks when you request it.",
                state: remindersState,
                settingsURL: PrivacyPane.reminders.url
            )
        )

        rows.append(
            PermissionSummary(
                id: "microphone",
                title: "Microphone",
                purpose: "Dictate messages to the assistant using the mic button.",
                state: microphoneState,
                settingsURL: PrivacyPane.microphone.url
            )
        )

        return rows
    }

    // MARK: - Internals

    private static func normalize(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess, .writeOnly: return .granted
        default: return .unknown
        }
    }
}
