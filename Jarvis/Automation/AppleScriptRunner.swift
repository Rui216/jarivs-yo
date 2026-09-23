//
//  AppleScriptRunner.swift
//  JARVIS
//
//  Runs AppleScript through osascript for the automation features that
//  application scripting dictionaries handle better than any API, for
//  example controlling browser tabs and music playback.
//
//  Scripts are screened before they run: shell escapes, synthetic
//  keystrokes, and destructive Finder operations are refused outright.
//  The first script that targets an application triggers the standard
//  macOS automation consent prompt for that application.
//

import Foundation
import os

/// Compiles and runs AppleScript source.
@MainActor
final class AppleScriptRunner {

    /// Shared instance used by the automation layer.
    static let shared = AppleScriptRunner()

    /// osascript location on every macOS install.
    private static let osascriptURL = URL(fileURLWithPath: "/usr/bin/osascript")

    /// Default time limit for a script.
    static let defaultTimeout: TimeInterval = 25

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Automation")

    /// Script constructs that JARVIS refuses to run.
    ///
    /// The list covers shell escapes, synthetic input, and destructive
    /// Finder operations. It is a guard rail, not a sandbox: every script
    /// still runs with the user's own privileges.
    private static let blockedConstructs: [(pattern: String, reason: String)] = [
        ("do shell script", "shell escapes are not allowed inside AppleScript; use run_terminal_command instead."),
        ("osadecompile", "decompiling other scripts is not allowed."),
        ("run script", "dynamically loading another script is not allowed."),
        ("keystroke", "synthetic keystrokes are not allowed because they can drive any application."),
        ("key code", "synthetic key events are not allowed because they can drive any application."),
        ("tell application \"Terminal\"", "driving Terminal directly is not allowed."),
        ("tell application \"System Events\" to delete", "deleting items through System Events is not allowed."),
        ("delete every item", "deleting items is not allowed."),
        ("empty trash", "emptying the trash is not allowed."),
        ("shut down", "shutting the machine down is not allowed."),
        ("restart the computer", "restarting is not allowed."),
        ("log out", "logging out is not allowed."),
        ("sudo", "privilege escalation is not allowed."),
        ("set volume", "changing system volume is not allowed.")
    ]

    // MARK: - Execution

    /// Screens and runs a script, returning its standard output.
    func run(script: String, timeout: TimeInterval = AppleScriptRunner.defaultTimeout) async throws -> String {
        try Self.screen(script: script)

        let result = try await ProcessExecutor.run(
            executable: Self.osascriptURL,
            arguments: ["-e", script],
            timeout: timeout
        )

        if result.didTimeOut {
            throw AutomationError.scriptRunnerFailed(detail: "the script exceeded \(Int(timeout)) seconds.")
        }

        guard result.exitCode == 0 else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isPermissionFailure(message) {
                throw AutomationError.automationPermissionDenied(target: Self.targetApplication(in: script) ?? "the target application")
            }
            let code = Self.errorCode(in: message)
            if code != 0 {
                throw AutomationError.scriptExecutionFailed(code: code, message: Self.humanReadable(message))
            }
            throw AutomationError.scriptRunnerFailed(detail: Self.humanReadable(message))
        }

        return result.trimmedOutput
    }

    /// Runs a script that is expected to return a boolean, such as an
    /// application state probe.
    func runBoolean(script: String, timeout: TimeInterval = 10) async throws -> Bool {
        let output = try await run(script: script, timeout: timeout)
        return ["true", "yes", "1"].contains(output.lowercased())
    }

    // MARK: - Permission probing

    /// Sends a harmless Apple Event to Finder to learn whether automation
    /// permission has been granted.
    ///
    /// Returns true when the event succeeded, false when macOS refused it.
    /// The call may show the system consent prompt the first time.
    func probeAutomationPermission() async -> Bool {
        do {
            let name = try await run(
                script: "tell application \"Finder\" to get name of home",
                timeout: 15
            )
            return !name.isEmpty
        } catch {
            logger.debug("Automation probe did not succeed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Screening

    /// Refuses scripts containing blocked constructs.
    static func screen(script: String) throws {
        let lowered = script.lowercased()
        for entry in blockedConstructs where lowered.contains(entry.pattern.lowercased()) {
            throw AutomationError.commandNotPermitted(reason: entry.reason)
        }
        guard script.utf8.count <= 8_192 else {
            throw AutomationError.commandNotPermitted(reason: "the script is longer than 8 KB. Split the work into smaller steps.")
        }
    }

    // MARK: - Helpers

    /// Extracts the AppleScript error number from an osascript message.
    private static func errorCode(in message: String) -> Int {
        guard let range = message.range(of: "\\(-?[0-9]+\\)", options: .regularExpression) else { return 0 }
        let raw = message[range].dropFirst().dropLast()
        return Int(raw) ?? 0
    }

    /// Strips the osascript prefix so the message can be shown to the user.
    private static func humanReadable(_ message: String) -> String {
        message
            .replacingOccurrences(of: "execution error: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when an osascript failure was caused by a missing permission.
    private static func isPermissionFailure(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("-1743")
            || lowered.contains("-600")
            || lowered.contains("not allowed to send apple events")
            || lowered.contains("not authorized")
            || lowered.contains("not permitted")
    }

    /// Finds the first application named in a script, for error messages.
    private static func targetApplication(in script: String) -> String? {
        guard let range = script.range(of: "tell application \"[^\"]+\"", options: .regularExpression) else {
            return nil
        }
        let match = script[range]
        let quoted = match.split(separator: "\"")
        return quoted.count >= 2 ? String(quoted[1]) : nil
    }
}
