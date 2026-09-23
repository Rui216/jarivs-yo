//
//  AutomationConfirmation.swift
//  JARVIS
//
//  Presents the confirmation dialog that stands between the assistant
//  and any action the user must approve, most importantly terminal
//  commands. The assistant's tool execution suspends on an await until
//  the user answers, so no command can ever run silently.
//

import Foundation
import Observation

/// Describes one approval request shown to the user.
struct AutomationConfirmationRequest: Identifiable, Equatable, Sendable {
    /// Unique identifier used to resolve the request.
    let id: UUID
    /// Short title, for example "Run a terminal command".
    let title: String
    /// Longer explanation of what will happen.
    let detail: String
    /// The exact command or script that will run.
    let payload: String
    /// Label on the confirm button.
    let confirmLabel: String
    /// SF Symbol shown in the dialog.
    let symbolName: String
    /// Seconds before the request is declined automatically.
    let timeoutSeconds: Int

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        payload: String,
        confirmLabel: String = "Run command",
        symbolName: String = "terminal",
        timeoutSeconds: Int = 120
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.payload = payload
        self.confirmLabel = confirmLabel
        self.symbolName = symbolName
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Queues confirmation requests and resolves them when the user answers.
@MainActor
@Observable
final class AutomationConfirmationCenter {

    /// Request currently shown, if any.
    private(set) var current: AutomationConfirmationRequest?

    private var queue: [AutomationConfirmationRequest] = []
    private var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    /// True when a dialog should be presented.
    var isPresenting: Bool { current != nil }

    /// Asks the user to approve an action and waits for the answer.
    ///
    /// Requests are queued and shown one at a time. A request that is not
    /// answered within its timeout is declined automatically.
    func requestApproval(_ request: AutomationConfirmationRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            continuations[request.id] = continuation
            queue.append(request)
            presentNextIfIdle()

            let timeout = Task { [weak self] in
                let nanoseconds = UInt64(max(5, request.timeoutSeconds)) * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.resolve(id: request.id, approved: false)
                }
            }
            timeoutTasks[request.id] = timeout
        }
    }

    /// Approves the visible request.
    func approveCurrent() {
        guard let current else { return }
        resolve(id: current.id, approved: true)
    }

    /// Declines the visible request.
    func declineCurrent() {
        guard let current else { return }
        resolve(id: current.id, approved: false)
    }

    // MARK: - Internals

    private func presentNextIfIdle() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
    }

    private func resolve(id: UUID, approved: Bool) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        timeoutTasks.removeValue(forKey: id)?.cancel()

        if current?.id == id {
            current = nil
        } else {
            queue.removeAll { $0.id == id }
        }

        continuation.resume(returning: approved)
        presentNextIfIdle()
    }
}
