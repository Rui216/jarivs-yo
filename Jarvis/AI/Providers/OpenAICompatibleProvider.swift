//
//  OpenAICompatibleProvider.swift
//  JARVIS
//
//  Chat Completions implementation shared by OpenAI, OpenRouter, and
//  Groq. All three expose the same request shape and streaming format,
//  differing only in base URL, headers, and token limit parameter.
//

import Foundation
import os

/// Which token limit field the endpoint expects.
enum TokenLimitParameter: Sendable {
    /// `max_tokens`, used by the original Chat Completions schema.
    case maxTokens
    /// `max_completion_tokens`, used by newer OpenAI models and Groq.
    case maxCompletionTokens
}

/// Endpoint specific settings for an OpenAI compatible provider.
struct OpenAICompatibleConfiguration: Sendable {
    /// Base URL up to and including the API version, for example `https://api.openai.com/v1`.
    let baseURL: URL
    /// Provider identity used for descriptors and error mapping.
    let identity: AIProviderID
    /// Extra headers, for example OpenRouter attribution headers.
    let extraHeaders: [String: String]
    /// Token limit field this endpoint accepts.
    let tokenLimitParameter: TokenLimitParameter
    /// Whether `stream_options: { include_usage: true }` is accepted.
    let supportsStreamOptions: Bool
    /// Model prefixes that reject `temperature` and require `max_completion_tokens`.
    let reasoningModelPrefixes: [String]

    /// OpenAI platform endpoints.
    static let openAI = OpenAICompatibleConfiguration(
        baseURL: URL(string: "https://api.openai.com/v1")!,
        identity: .openai,
        extraHeaders: [:],
        tokenLimitParameter: .maxTokens,
        supportsStreamOptions: true,
        reasoningModelPrefixes: ["o1", "o3", "o4", "gpt-5"]
    )

    /// OpenRouter gateway, which proxies many vendors behind one key.
    static let openRouter = OpenAICompatibleConfiguration(
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        identity: .openrouter,
        extraHeaders: [
            "HTTP-Referer": "https://jarvis.local",
            "X-Title": "JARVIS"
        ],
        tokenLimitParameter: .maxTokens,
        supportsStreamOptions: true,
        reasoningModelPrefixes: []
    )

    /// Groq inference endpoints.
    static let groq = OpenAICompatibleConfiguration(
        baseURL: URL(string: "https://api.groq.com/openai/v1")!,
        identity: .groq,
        extraHeaders: [:],
        tokenLimitParameter: .maxCompletionTokens,
        supportsStreamOptions: false,
        reasoningModelPrefixes: []
    )
}

/// Streams chat completions from any OpenAI compatible endpoint.
struct OpenAICompatibleProvider: AIProvider {

    /// Endpoint settings for this instance.
    let configuration: OpenAICompatibleConfiguration

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Assistant")

    init(configuration: OpenAICompatibleConfiguration) {
        self.configuration = configuration
    }

    var descriptor: AIProviderDescriptor {
        AIProviderFactory.descriptor(for: configuration.identity)
    }

    func streamChat(
        request: AIChatRequest,
        apiKey: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try makeBody(request: request)
                    var headers: [String: String] = [
                        "Authorization": "Bearer \(apiKey)",
                        "accept": "text/event-stream"
                    ]
                    for (key, value) in configuration.extraHeaders {
                        headers[key] = value
                    }

                    let bytes = try await ProviderHTTP.openStream(
                        url: chatCompletionsURL,
                        headers: headers,
                        body: body,
                        provider: configuration.identity
                    )

                    var stopReason: AIStopReason = .unknown
                    var sawToolCall = false

                    for try await event in SSEParser.events(from: bytes) {
                        try Task.checkCancellation()
                        if event.isDone { break }
                        guard let payload = decode(event.data) else { continue }

                        if let error = payload["error"] as? [String: Any] {
                            let message = error["message"] as? String
                            throw ProviderHTTP.makeError(
                                status: 500,
                                body: Data((message ?? "").utf8),
                                provider: configuration.identity,
                                headers: nil
                            )
                        }

                        if let usage = payload["usage"] as? [String: Any],
                           let input = usage["prompt_tokens"] as? Int,
                           let output = usage["completion_tokens"] as? Int {
                            continuation.yield(.usage(inputTokens: input, outputTokens: output))
                        }

                        guard let choices = payload["choices"] as? [[String: Any]],
                              let choice = choices.first else { continue }

                        if let finish = choice["finish_reason"] as? String {
                            stopReason = AIStopReason.fromWire(finish)
                        }

                        guard let delta = choice["delta"] as? [String: Any] else { continue }

                        if let text = delta["content"] as? String, !text.isEmpty {
                            continuation.yield(.text(text))
                        }

                        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for call in toolCalls {
                                let index = call["index"] as? Int ?? 0
                                let id = call["id"] as? String
                                let function = call["function"] as? [String: Any]
                                let name = function?["name"] as? String
                                let fragment = function?["arguments"] as? String ?? ""
                                if name != nil || !fragment.isEmpty {
                                    sawToolCall = sawToolCall || (name != nil)
                                    continuation.yield(.toolCallDelta(
                                        index: index,
                                        id: id,
                                        name: name,
                                        argumentsFragment: fragment
                                    ))
                                }
                            }
                        }
                    }

                    let finalReason: AIStopReason = sawToolCall && stopReason != .maxTokens ? .toolUse : stopReason
                    continuation.yield(.completed(stopReason: finalReason))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIServiceError.cancelled)
                } catch let error as AIServiceError {
                    continuation.finish(throwing: error)
                } catch {
                    logger.error("Chat completions stream failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: AIServiceError.network(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Wire format

    private var chatCompletionsURL: URL {
        configuration.baseURL.appendingPathComponent("chat/completions")
    }

    /// Builds the request body for one turn.
    private func makeBody(request: AIChatRequest) throws -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "messages": wireMessages(request.messages, systemPrompt: request.systemPrompt)
        ]

        let isReasoningModel = configuration.reasoningModelPrefixes.contains { prefix in
            request.model.lowercased().hasPrefix(prefix)
        }

        let tokenField = (isReasoningModel || configuration.tokenLimitParameter == .maxCompletionTokens)
            ? "max_completion_tokens"
            : "max_tokens"
        body[tokenField] = request.maxOutputTokens

        if configuration.supportsStreamOptions {
            body["stream_options"] = ["include_usage": true]
        }

        // Reasoning models reject a custom temperature value.
        if let temperature = request.temperature, !isReasoningModel {
            body["temperature"] = temperature
        }

        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters.jsonObject
                    ]
                ]
            }
            body["tool_choice"] = "auto"
        }

        return body
    }

    /// Converts conversation messages into Chat Completions format.
    private func wireMessages(_ messages: [AIMessage], systemPrompt: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if !systemPrompt.isEmpty {
            result.append(["role": "system", "content": systemPrompt])
        }

        for message in messages {
            switch message.role {
            case .system:
                let text = message.plainText
                if !text.isEmpty {
                    result.append(["role": "system", "content": text])
                }

            case .user:
                let text = message.plainText
                guard !text.isEmpty else { continue }
                result.append(["role": "user", "content": text])

            case .assistant:
                var entry: [String: Any] = ["role": "assistant"]
                let text = message.plainText
                entry["content"] = text.isEmpty ? NSNull() : text
                let calls = message.toolCalls
                if !calls.isEmpty {
                    entry["tool_calls"] = calls.map { call -> [String: Any] in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": [
                                "name": call.name,
                                "arguments": call.argumentsJSON.isEmpty ? "{}" : call.argumentsJSON
                            ]
                        ]
                    }
                }
                result.append(entry)

            case .tool:
                for block in message.content {
                    guard case .toolResult(let id, let name, let content, _) = block else { continue }
                    result.append([
                        "role": "tool",
                        "tool_call_id": id,
                        "name": name,
                        "content": content
                    ])
                }
            }
        }

        return result
    }

    private func decode(_ data: String) -> [String: Any]? {
        guard let raw = data.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }
}
