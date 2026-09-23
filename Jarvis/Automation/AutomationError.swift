//
//  AutomationError.swift
//  JARVIS
//
//  Errors produced by the automation layer. Messages are written to be
//  shown to the user and, in most cases, returned to the model so it can
//  explain what went wrong.
//

import Foundation

/// Failures raised while performing system automation.
enum AutomationError: LocalizedError, Equatable {
    /// No installed application matched the requested name or bundle id.
    case applicationNotFound(String)
    /// The application exists but launching it failed.
    case applicationLaunchFailed(String, reason: String)
    /// AppleScript source did not compile.
    case scriptCompilationFailed(String)
    /// AppleScript ran but reported an error.
    case scriptExecutionFailed(code: Int, message: String)
    /// osascript could not be launched or exited abnormally.
    case scriptRunnerFailed(detail: String)
    /// A file or folder path does not exist.
    case pathNotFound(String)
    /// The path exists but is outside the folders JARVIS may touch.
    case pathNotAllowed(String)
    /// Automation permission was denied by the user or by system policy.
    case automationPermissionDenied(target: String)
    /// The requested browser is not installed or not scriptable.
    case unsupportedBrowser(String)
    /// The web address could not be parsed.
    case invalidURL(String)
    /// The command is not on the whitelist, or contains shell metacharacters.
    case commandNotPermitted(reason: String)
    /// The command ran and returned a non zero exit status.
    case commandFailed(exitCode: Int32, output: String)
    /// The command exceeded its time limit.
    case commandTimedOut(seconds: Int)
    /// Calendar access has not been granted.
    case calendarAccessDenied
    /// Reminders access has not been granted.
    case remindersAccessDenied
    /// EventKit reported a failure.
    case calendarOperationFailed(String)
    /// The user declined the confirmation prompt.
    case userDenied(String)

    var errorDescription: String? {
        switch self {
        case .applicationNotFound(let name):
            return "No installed application matched \(name)."
        case .applicationLaunchFailed(let name, let reason):
            return "Could not launch \(name): \(reason)"
        case .scriptCompilationFailed(let message):
            return "The AppleScript could not be compiled: \(message)"
        case .scriptExecutionFailed(let code, let message):
            return "AppleScript failed with error \(code): \(message)"
        case .scriptRunnerFailed(let detail):
            return "osascript could not run: \(detail)"
        case .pathNotFound(let path):
            return "No file or folder exists at \(path)."
        case .pathNotAllowed(let path):
            return "JARVIS is not allowed to open \(path). It is outside your home folder, /tmp, /Applications, and /Volumes."
        case .automationPermissionDenied(let target):
            return "macOS blocked automation of \(target). Grant access in System Settings, Privacy and Security, Automation."
        case .unsupportedBrowser(let name):
            return "\(name) is either not installed or does not support scripted tabs."
        case .invalidURL(let value):
            return "\(value) is not a valid web address."
        case .commandNotPermitted(let reason):
            return "Command refused: \(reason)"
        case .commandFailed(let exitCode, let output):
            return "The command exited with status \(exitCode). \(output)"
        case .commandTimedOut(let seconds):
            return "The command exceeded the \(seconds) second time limit and was stopped."
        case .calendarAccessDenied:
            return "Calendar access has not been granted. Enable it in Settings, Permissions."
        case .remindersAccessDenied:
            return "Reminders access has not been granted. Enable it in Settings, Permissions."
        case .calendarOperationFailed(let message):
            return "Calendar operation failed: \(message)"
        case .userDenied(let what):
            return "The user declined to run \(what)."
        }
    }

    /// Optional recovery hint shown under the error in the chat transcript.
    var recoverySuggestion: String? {
        switch self {
        case .automationPermissionDenied:
            return "Open System Settings, Privacy and Security, Automation, and enable JARVIS for the target application."
        case .calendarAccessDenied, .remindersAccessDenied:
            return "Open Settings, Permissions in JARVIS and use the Request Access button."
        case .commandNotPermitted:
            return "Only read only commands from the whitelist can run. See Settings, Permissions for the full list."
        case .pathNotAllowed:
            return "Move the item into your home folder, or open it manually."
        default:
            return nil
        }
    }

    /// True when the failure is caused by a missing permission.
    var isPermissionFailure: Bool {
        switch self {
        case .automationPermissionDenied, .calendarAccessDenied, .remindersAccessDenied:
            return true
        default:
            return false
        }
    }
}
