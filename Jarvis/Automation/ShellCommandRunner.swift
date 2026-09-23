//
//  ShellCommandRunner.swift
//  JARVIS
//
//  Executes whitelisted commands. Commands never pass through a shell,
//  the binary path must match the whitelist exactly, and arguments are
//  validated before the user is asked to confirm. Nothing here decides
//  whether a command is allowed to run: that decision is always the
//  user's, made in the confirmation dialog.
//

import Foundation
import os

/// Validates and runs read only command line tools.
@MainActor
final class ShellCommandRunner {

    /// Shared instance used by the automation bridge.
    static let shared = ShellCommandRunner()

    /// Default time limit for a whitelisted command.
    static let defaultTimeout: TimeInterval = 25

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Automation")

    /// Validates a command line against the whitelist.
    ///
    /// Throws `AutomationError.commandNotPermitted` or
    /// `AutomationError.pathNotAllowed` when the command cannot run.
    func validate(_ command: String) throws -> ValidatedCommand {
        try CommandWhitelist.validate(command)
    }

    /// Runs a validated command and returns its result.
    ///
    /// Never throws for a non zero exit status: the caller decides how to
    /// present partial output. Throws only on launch failure or timeout.
    func run(
        _ command: ValidatedCommand,
        timeout: TimeInterval = ShellCommandRunner.defaultTimeout
    ) async throws -> ProcessExecutionResult {
        // Logging the binary and argument count keeps commands out of logs
        // while still making failures diagnosable.
        logger.debug("Running whitelisted command \(command.binaryName, privacy: .public) with \(command.arguments.count, privacy: .public) argument(s)")

        let result = try await ProcessExecutor.run(
            executable: command.executableURL,
            arguments: command.arguments,
            timeout: timeout,
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser,
            environment: Self.minimalEnvironment
        )

        if result.didTimeOut {
            throw AutomationError.commandTimedOut(seconds: Int(timeout))
        }
        return result
    }

    /// Environment handed to whitelisted commands: no inherited secrets,
    /// a minimal PATH, and the user home folder.
    private static var minimalEnvironment: [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "HOME": home,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8"
        ]
    }

    /// Describes a result for the model, trimming and bounding the output.
    static func describe(_ result: ProcessExecutionResult, command: ValidatedCommand, maximumCharacters: Int = 4_000) -> String {
        var lines: [String] = []
        lines.append("Command: \(command.displayCommand)")
        lines.append("Exit status: \(result.exitCode)")

        let output = result.combinedOutput
        if output.isEmpty {
            lines.append("Output: none")
        } else {
            let clipped = output.count > maximumCharacters
                ? String(output.prefix(maximumCharacters)) + "\n[output truncated]"
                : output
            lines.append("Output:\n\(clipped)")
        }
        return lines.joined(separator: "\n")
    }
}
