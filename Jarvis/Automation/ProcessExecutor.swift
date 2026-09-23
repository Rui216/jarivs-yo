//
//  ProcessExecutor.swift
//  JARVIS
//
//  Runs a child process with concurrent output capture and a hard
//  deadline. Both the AppleScript runner and the whitelisted shell
//  runner are built on this, so every external call in the app has the
//  same cancellation and cleanup behaviour.
//

import Foundation
import Darwin
import os

/// Outcome of a finished child process.
struct ProcessExecutionResult: Sendable {
    /// Process exit status. -1 when the process had to be killed.
    var exitCode: Int32
    /// Captured standard output.
    var standardOutput: String
    /// Captured standard error.
    var standardError: String
    /// True when the deadline was reached and the process was stopped.
    var didTimeOut: Bool
    /// Wall clock duration of the call.
    var duration: TimeInterval

    /// Output with trailing whitespace removed.
    var trimmedOutput: String {
        standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Combined output used when reporting failures.
    var combinedOutput: String {
        let error = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = trimmedOutput
        if error.isEmpty { return output }
        if output.isEmpty { return error }
        return "\(output)\n\(error)"
    }
}

/// Executes child processes.
enum ProcessExecutor {

    private static let logger = Logger(subsystem: "com.jarvis.desktop", category: "Automation")

    /// Maximum captured output per stream, guarding against runaway commands.
    private static let maximumCapturedBytes = 262_144

    /// Runs an executable and waits for it to finish or time out.
    ///
    /// Nothing is passed through a shell, so arguments containing spaces or
    /// quotes are delivered verbatim.
    static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessExecutionResult {
        let started = Date()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        if let environment {
            process.environment = environment
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch \(executable.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw AutomationError.scriptRunnerFailed(detail: error.localizedDescription)
        }

        async let outputData = readAll(from: outputPipe.fileHandleForReading)
        async let errorData = readAll(from: errorPipe.fileHandleForReading)

        var didTimeOut = false
        let deadline = Date().addingTimeInterval(max(1, timeout))

        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                break
            }
            if Date() >= deadline {
                didTimeOut = true
                process.terminate()

                let killDeadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < killDeadline {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if process.isRunning {
            // Give the kernel a moment to reap a just killed process.
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        let outData = (try? await outputData) ?? Data()
        let errData = (try? await errorData) ?? Data()

        let exitCode: Int32 = process.isRunning ? -1 : process.terminationStatus
        let duration = Date().timeIntervalSince(started)

        return ProcessExecutionResult(
            exitCode: exitCode,
            standardOutput: String(data: outData, encoding: .utf8) ?? "",
            standardError: String(data: errData, encoding: .utf8) ?? "",
            didTimeOut: didTimeOut,
            duration: duration
        )
    }

    /// Reads a pipe to end, capped so a chatty process cannot exhaust memory.
    private static func readAll(from handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var buffer = Data()
                while true {
                    let chunk = (try? handle.read(upToCount: 8_192)) ?? nil
                    guard let chunk, !chunk.isEmpty else { break }
                    if buffer.count < maximumCapturedBytes {
                        buffer.append(chunk)
                    }
                }
                continuation.resume(returning: buffer)
            }
        }
    }
}
