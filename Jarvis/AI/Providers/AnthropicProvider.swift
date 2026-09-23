//
//  AnthropicProvider.swift
//  JARVIS
//
//  Claude Messages API streaming provider. Translates the provider
//  agnostic message model into Anthropic content blocks and decodes the
//  event stream back into text deltas and tool call fragments.
//

import Foundation
import os

/// Streams chat completions from the Anthropic Messages API.
struct AnthropicProvider: AIProvider {

    /// API version header required by Anthropic.
    private static let apiVersion = "2023-06-01"
    /// Messages endpoint.
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Assistant")

    var descriptor: AIProviderDescriptor {
        AIProviderFactory.descriptor(for: .anthropic)
    }

    func streamChat(
        request: AIChatRequest,
        apiKey: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try Self.makeBody(request: request)
                    let headers: [String: String] = [
                        "x-api-key": apiKey,
                        "anthropic-version": Self.apiVersion,
                        "accept": "text/event-stream"
                    ]
                    let bytes = try await ProviderHTTP.openStream(
                        url: Self.endpoint,
                        headers: headers,
                        body: body,
                        provider: .anthropic
                    )

                    var stopReason: AIStopReason = .unknown
                    var sawToolCall = false

                    for try await event in SSEParser.events(from: bytes) {
                        try Task.checkCancellation()
                        guard let payload = Self.decode(event.data) else { continue }

                        if let type = payload["type"] as? String {
                            switch type {
                            case "content_block_start":
                                let index = payload["index"] as? Int ?? 0
                                if let block = payload["content_block"] as? [String: Any],
                                   (block["type"] as? String) == "tool_use" {
                                    sawToolCall = true
                                    continuation.yield(.toolCallDelta(
                                        index: index,
                                        id: block["id"] as? String,
                                        name: block["name"] as? String,
                                        argumentsFragment: ""
                                    ))
                                }

                            case "content_block_delta":
                                let index = payload["index"] as? Int ?? 0
                                guard let delta = payload["delta"] as? [String: Any],
                                      let deltaType = delta["type"] as? String else { continue }
                                if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                                    continuation.yield(.text(text))
                                } else if deltaType == "input_json_delta",
                                          let fragment = delta["partial_json"] as? String {
                                    continuation.yield(.toolCallDelta(
                                        index: index,
                                        id: nil,
                                        name: nil,
                                        argumentsFragment: fragment
                                    ))
                                }

                            case "message_delta":
                                if let delta = payload["delta"] as? [String: Any],
                                   let reason = delta["stop_reason"] as? String {
                                    stopReason = AIStopReason.fromWire(reason)
                                }
                                if let usage = payload["usage"] as? [String: Any],
                                   let output = usage["output_tokens"] as? Int {
                                    continuation.yield(.usage(inputTokens: 0, outputTokens: output))
                                }

                            case "message_start":
                                if let message = payload["message"] as? [String: Any],
                                   let usage = message["usage"] as? [String: Any],
                                   let input = usage["input_tokens"] as? Int {
                                    continuation.yield(.usage(inputTokens: input, outputTokens: 0))
                                }

                            case "error":
                                let message = (payload["error"] as? [String: Any])?["message"] as? String
                                throw Self.mapStreamError(message: message)

                            case "message_stop":
                                break

                            default:
                                break
                            }
                        }
                    }

                    let finalReason: AIStopReason = sawToolCall && stopReason == .endTurn ? .toolUse : stopReason
                    continuation.yield(.completed(stopReason: finalReason))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIServiceError.cancelled)
                } catch let error as AIServiceError {
                    continuation.finish(throwing: error)
                } catch {
                    logger.error("Anthropic stream failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: AIServiceError.network(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Wire format

    /// Builds the request body for one turn.
    private static func makeBody(request: AIChatRequest) throws -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxOutputTokens,
            "stream": true,
            "system": request.systemPrompt,
            "messages": wireMessages(request.messages)
        ]
        if let temperature = request.temperature {
            body["temperature"] = temperature
        }
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.parameters.jsonObject
                ]
            }
        }
        return body
    }

    /// Converts conversation messages into Anthropic format.
    ///
    /// Anthropic requires alternating user and assistant turns, so tool
    /// results become user turns and consecutive same role messages are
    /// merged before they are sent.
    private static func wireMessages(_ messages: [AIMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        func append(role: String, blocks: [[String: Any]]) {
            guard !blocks.isEmpty else { return }
            if var last = result.last, (last["role"] as? String) == role,
               var existing = last["content"] as? [[String: Any]] {
                existing.append(contentsOf: blocks)
                last["content"] = existing
                result[result.count - 1] = last
            } else {
                result.append(["role": role, "content": blocks])
            }
        }

        for message in messages {
            switch message.role {
            case .system:
                // The system prompt is sent as a top level field.
                continue

            case .user:
                let blocks = message.content.compactMap { block -> [String: Any]? in
                    switch block {
                    case .text(let text):
                        return ["type": "text", "text": text]
                    case .imageBase64(let mediaType, let base64):
                        return [
                            "type": "image",
                            "source": ["type": "base64", "media_type": mediaType, "data": base64]
                        ]
                    case .toolResult(let id, _, let content, _):
                        return toolResultBlock(id: id, content: content)
                    case .toolCall(_, _, _):
                        return nil
                    }
                }
                append(role: "user", blocks: blocks)

            case .assistant:
                var blocks: [[String: Any]] = []
                let text = message.plainText
                if !text.isEmpty {
                    blocks.append(["type": "text", "text": text])
                }
                for call in message.toolCalls {
                    blocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": Self.jsonObject(from: call.argumentsJSON)
                    ])
                }
                append(role: "assistant", blocks: blocks)

            case .tool:
                let blocks = message.content.compactMap { block -> [String: Any]? in
                    guard case .toolResult(let id, _, let content, _) = block else { return nil }
                    return toolResultBlock(id: id, content: content)
                }
                append(role: "user", blocks: blocks)
            }
        }

        return result
    }

    private static func toolResultBlock(id: String, content: String) -> [String: Any] {
        [
            "type": "tool_result",
            "tool_use_id": id,
            "content": content
        ]
    }

    /// Decodes a JSON object from a stream payload, ignoring keep alive frames.
    private static func decode(_ data: String) -> [String: Any]? {
        guard let raw = data.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    /// Parses a tool call argument string, falling back to an empty object.
    private static func jsonObject(from argumentsJSON: String) -> Any {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [String: Any]() }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
    }

    /// Maps an in stream error event onto a typed error.
    private static func mapStreamError(message: String?) -> AIServiceError {
        guard let message else {
            return .serverError(status: 500, message: "The provider reported an error during the stream.")
        }
        let lowered = message.lowercased()
        if lowered.contains("credit") || lowered.contains("quota") {
            return .rateLimited(retryAfterSeconds: nil)
        }
        if lowered.contains("authentication") || lowered.contains("api key") || lowered.contains("permission") {
            return .invalidAPIKey(.anthropic)
        }
        return .serverError(status: 500, message: message)
    }
}
