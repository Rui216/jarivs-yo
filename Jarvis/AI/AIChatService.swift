//
//  AIChatService.swift
//  JARVIS
//
//  The provider agnostic assistant loop. It streams one model turn,
//  runs any tools the model asks for, feeds the results back, and
//  repeats until the model answers without requesting another tool.
//  Switching providers changes nothing in this file.
//

import Foundation
import os

/// Inputs for one assistant run.
struct AssistantRunRequest: Sendable {
    /// Provider that answers the request.
    var providerID: AIProviderID
    /// Model identifier for that provider.
    var model: String
    /// API key resolved from the keychain by the caller.
    var apiKey: String
    /// System prompt built from `AssistantContext`.
    var systemPrompt: String
    /// Conversation so far, oldest first. Does not include the system prompt.
    var messages: [AIMessage]
    /// Tools offered to the model.
    var tools: [AssistantToolSchema]
}

/// Guardrails for the tool loop.
struct AssistantRunLimits: Sendable {
    /// Maximum model turns in a single request.
    var maxIterations: Int = 6
    /// Maximum tool executions across the whole request.
    var maxToolCalls: Int = 14
    /// Output token ceiling for each model turn.
    var maxOutputTokens: Int = 2_048
    /// Sampling temperature. Nil lets the provider use its own default.
    var temperature: Double? = 0.3

    /// Default guardrails used by the dashboard assistant.
    static let standard = AssistantRunLimits()
}

/// Result of a completed assistant run.
struct AssistantRunOutcome: Sendable {
    /// Text of the final answer.
    var finalText: String
    /// One line summaries of every action performed, in order.
    var actionSummaries: [String]
    /// Number of tool calls executed.
    var toolCallCount: Int
    /// Conversation including assistant tool calls and tool results, ready
    /// to be used as the history of the next request.
    var conversation: [AIMessage]
    /// How the model finished its last turn.
    var stopReason: AIStopReason
    /// True when the iteration or tool budget ran out before an answer.
    var didExhaustBudget: Bool
}

/// Events emitted while an assistant run progresses.
enum AssistantRunEvent: Sendable {
    /// A chunk of assistant text.
    case textDelta(String)
    /// A new model turn started.
    case iterationStarted(Int)
    /// A tool call is about to be executed.
    case toolStarted(AssistantToolCall)
    /// A tool call finished.
    case toolFinished(AssistantToolCall, AssistantToolResult)
    /// The run finished successfully.
    case completed(AssistantRunOutcome)
}

/// Runs the streaming tool loop against the selected provider.
struct AIChatService: Sendable {

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Assistant")

    /// Starts a run and streams its events.
    ///
    /// The stream finishes after a `.completed` event, or throws an
    /// `AIServiceError` when the provider fails. Cancelling the consuming
    /// task cancels the provider request and any pending tool execution.
    func run(
        request: AssistantRunRequest,
        executor: any AssistantToolExecuting,
        limits: AssistantRunLimits = .standard
    ) -> AsyncThrowingStream<AssistantRunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let outcome = try await perform(
                        request: request,
                        executor: executor,
                        limits: limits,
                        emit: { continuation.yield($0) }
                    )
                    continuation.yield(.completed(outcome))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIServiceError.cancelled)
                } catch let error as AIServiceError {
                    continuation.finish(throwing: error)
                } catch {
                    logger.error("Assistant run failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: AIServiceError.network(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Loop

    private func perform(
        request: AssistantRunRequest,
        executor: any AssistantToolExecuting,
        limits: AssistantRunLimits,
        emit: @Sendable (AssistantRunEvent) -> Void
    ) async throws -> AssistantRunOutcome {
        guard !request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingAPIKey(request.providerID)
        }

        let provider = AIProviderFactory.makeProvider(for: request.providerID)
        let acceptedNames = Set(request.tools.map(\.name))

        var conversation = request.messages
        var actionSummaries: [String] = []
        var toolCallCount = 0
        var lastText = ""
        var stopReason: AIStopReason = .unknown
        var didExhaustBudget = false

        for iteration in 0..<max(1, limits.maxIterations) {
            try Task.checkCancellation()
            emit(.iterationStarted(iteration))

            let chatRequest = AIChatRequest(
                model: request.model,
                systemPrompt: request.systemPrompt,
                messages: conversation,
                tools: request.tools,
                maxOutputTokens: limits.maxOutputTokens,
                temperature: limits.temperature
            )

            var accumulator = ToolCallAccumulator()
            var turnText = ""
            stopReason = .unknown

            for try await event in provider.streamChat(request: chatRequest, apiKey: request.apiKey) {
                try Task.checkCancellation()
                switch event {
                case .text(let chunk):
                    turnText += chunk
                    emit(.textDelta(chunk))
                case .toolCallDelta(let index, let id, let name, let fragment):
                    accumulator.append(index: index, id: id, name: name, argumentsFragment: fragment)
                case .usage(_, _):
                    break
                case .completed(let reason):
                    stopReason = reason
                }
            }

            if !turnText.isEmpty {
                lastText = turnText
            }

            let requestedCalls = accumulator.calls

            // Refuse calls to tools that were not advertised to the model.
            let unknownCalls = requestedCalls.filter { !acceptedNames.contains($0.name) }
            let executableCalls = requestedCalls.filter { acceptedNames.contains($0.name) }

            var assistantBlocks: [AIContentBlock] = []
            if !turnText.isEmpty {
                assistantBlocks.append(.text(turnText))
            }
            for call in executableCalls {
                assistantBlocks.append(.toolCall(
                    id: call.id,
                    name: call.name,
                    argumentsJSON: call.argumentsJSON.isEmpty ? "{}" : call.argumentsJSON
                ))
            }
            if !assistantBlocks.isEmpty {
                conversation.append(AIMessage(role: .assistant, content: assistantBlocks))
            }

            if executableCalls.isEmpty && unknownCalls.isEmpty {
                return AssistantRunOutcome(
                    finalText: lastText,
                    actionSummaries: actionSummaries,
                    toolCallCount: toolCallCount,
                    conversation: conversation,
                    stopReason: stopReason == .unknown ? .endTurn : stopReason,
                    didExhaustBudget: false
                )
            }

            var resultBlocks: [AIContentBlock] = []

            for call in unknownCalls {
                resultBlocks.append(.toolResult(
                    toolCallID: call.id,
                    toolName: call.name,
                    content: "Unknown tool. Available tools: \(acceptedNames.sorted().joined(separator: ", ")).",
                    isError: true
                ))
            }

            for call in executableCalls {
                guard toolCallCount < limits.maxToolCalls else {
                    didExhaustBudget = true
                    resultBlocks.append(.toolResult(
                        toolCallID: call.id,
                        toolName: call.name,
                        content: "Tool budget for this request is exhausted. Answer the user with what you have.",
                        isError: true
                    ))
                    continue
                }

                emit(.toolStarted(call))
                let result = await executor.execute(AssistantToolCall(
                    id: call.id,
                    name: call.name,
                    argumentsJSON: call.argumentsJSON
                ))
                toolCallCount += 1
                actionSummaries.append(result.summary)
                emit(.toolFinished(call, result))
                resultBlocks.append(.toolResult(
                    toolCallID: call.id,
                    toolName: call.name,
                    content: result.content,
                    isError: result.isError
                ))
            }

            conversation.append(AIMessage(role: .tool, content: resultBlocks))

            if stopReason == .maxTokens {
                didExhaustBudget = true
                break
            }
        }

        didExhaustBudget = true
        return AssistantRunOutcome(
            finalText: lastText,
            actionSummaries: actionSummaries,
            toolCallCount: toolCallCount,
            conversation: conversation,
            stopReason: stopReason,
            didExhaustBudget: didExhaustBudget
        )
    }
}

extension AIMessage {
    /// Creates a tool result message for a single tool call.
    static func toolResult(
        toolCallID: String,
        toolName: String,
        content: String,
        isError: Bool
    ) -> AIMessage {
        AIMessage(role: .tool, content: [
            .toolResult(toolCallID: toolCallID, toolName: toolName, content: content, isError: isError)
        ])
    }
}
