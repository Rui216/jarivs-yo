//
//  GeminiProvider.swift
//  JARVIS
//
//  Google Gemini streaming provider. Gemini delivers complete function
//  calls rather than argument fragments, so each function call is
//  forwarded as a single tool call delta.
//

import Foundation
import os

/// Streams chat completions from the Gemini generative language API.
struct GeminiProvider: AIProvider {

    /// API version used for the streaming endpoint.
    private static let apiVersion = "v1beta"
    /// Default output cap when the caller does not specify one.
    private static let defaultMaxOutputTokens = 2_048

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Assistant")

    var descriptor: AIProviderDescriptor {
        AIProviderFactory.descriptor(for: .google)
    }

    func streamChat(
        request: AIChatRequest,
        apiKey: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = Self.streamURL(model: request.model) else {
                        throw AIServiceError.serverError(
                            status: 400,
                            message: "The Gemini model name is not valid. Check it in Settings."
                        )
                    }
                    let body = Self.makeBody(request: request)
                    let headers: [String: String] = [
                        "x-goog-api-key": apiKey,
                        "accept": "text/event-stream"
                    ]

                    let bytes = try await ProviderHTTP.openStream(
                        url: url,
                        headers: headers,
                        body: body,
                        provider: .google
                    )

                    var stopReason: AIStopReason = .unknown
                    var sawToolCall = false
                    var toolCallIndex = 0

                    for try await event in SSEParser.events(from: bytes) {
                        try Task.checkCancellation()
                        if event.isDone { break }
                        guard let payload = Self.decode(event.data) else { continue }

                        if let error = payload["error"] as? [String: Any] {
                            let message = error["message"] as? String ?? "Gemini reported an error."
                            let status = error["code"] as? Int ?? 500
                            throw ProviderHTTP.makeError(
                                status: status,
                                body: Data(message.utf8),
                                provider: .google,
                                headers: nil
                            )
                        }

                        if let usage = payload["usageMetadata"] as? [String: Any] {
                            let input = usage["promptTokenCount"] as? Int ?? 0
                            let output = usage["candidatesTokenCount"] as? Int ?? 0
                            continuation.yield(.usage(inputTokens: input, outputTokens: output))
                        }

                        guard let candidates = payload["candidates"] as? [[String: Any]],
                              let candidate = candidates.first else { continue }

                        if let finish = candidate["finishReason"] as? String {
                            stopReason = Self.mapFinishReason(finish)
                        }

                        guard let content = candidate["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]] else { continue }

                        for part in parts {
                            if let text = part["text"] as? String, !text.isEmpty {
                                continuation.yield(.text(text))
                            }

                            if let functionCall = part["functionCall"] as? [String: Any],
                               let name = functionCall["name"] as? String {
                                sawToolCall = true
                                let arguments = functionCall["args"] as? [String: Any] ?? [:]
                                let argumentsJSON = Self.encodeArguments(arguments)
                                continuation.yield(.toolCallDelta(
                                    index: toolCallIndex,
                                    id: "gemini-call-\(toolCallIndex)",
                                    name: name,
                                    argumentsFragment: argumentsJSON
                                ))
                                toolCallIndex += 1
                            }
                        }
                    }

                    let finalReason: AIStopReason = sawToolCall ? .toolUse : stopReason
                    continuation.yield(.completed(stopReason: finalReason))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIServiceError.cancelled)
                } catch let error as AIServiceError {
                    continuation.finish(throwing: error)
                } catch {
                    logger.error("Gemini stream failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: AIServiceError.network(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Wire format

    /// Builds the streaming endpoint for a model identifier.
    private static func streamURL(model: String) -> URL? {
        let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        return URL(string: "https://generativelanguage.googleapis.com/\(apiVersion)/models/\(encoded):streamGenerateContent?alt=sse")
    }

    /// Builds the request body for one turn.
    private static func makeBody(request: AIChatRequest) -> [String: Any] {
        var generationConfig: [String: Any] = [
            "maxOutputTokens": request.maxOutputTokens > 0 ? request.maxOutputTokens : defaultMaxOutputTokens
        ]
        if let temperature = request.temperature {
            generationConfig["temperature"] = temperature
        }

        var body: [String: Any] = [
            "contents": wireContents(request.messages),
            "generationConfig": generationConfig
        ]

        if !request.systemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": request.systemPrompt]]]
        }

        if !request.tools.isEmpty {
            body["tools"] = [[
                "functionDeclarations": request.tools.map { tool in
                    [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": sanitizeSchema(tool.parameters.jsonObject)
                    ]
                }
            ]]
        }

        return body
    }

    /// Converts conversation messages into Gemini contents.
    ///
    /// Gemini uses `model` for assistant turns, expects tool results as
    /// function responses inside a user turn, and wants a function response
    /// for every function call in the previous model turn.
    private static func wireContents(_ messages: [AIMessage]) -> [[String: Any]] {
        var contents: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .system:
                continue

            case .user:
                var parts: [[String: Any]] = []
                for block in message.content {
                    switch block {
                    case .text(let text):
                        parts.append(["text": text])
                    case .imageBase64(let mediaType, let base64):
                        parts.append(["inlineData": ["mimeType": mediaType, "data": base64]])
                    case .toolResult(_, let name, let content, let isError):
                        parts.append(functionResponsePart(name: name, content: content, isError: isError))
                    case .toolCall(_, _, _):
                        continue
                    }
                }
                guard !parts.isEmpty else { continue }
                contents.append(["role": "user", "parts": parts])

            case .assistant:
                var parts: [[String: Any]] = []
                let text = message.plainText
                if !text.isEmpty {
                    parts.append(["text": text])
                }
                for call in message.toolCalls {
                    parts.append([
                        "functionCall": [
                            "name": call.name,
                            "args": jsonObject(from: call.argumentsJSON)
                        ]
                    ])
                }
                guard !parts.isEmpty else { continue }
                contents.append(["role": "model", "parts": parts])

            case .tool:
                var parts: [[String: Any]] = []
                for block in message.content {
                    guard case .toolResult(_, let name, let content, let isError) = block else { continue }
                    parts.append(functionResponsePart(name: name, content: content, isError: isError))
                }
                guard !parts.isEmpty else { continue }
                contents.append(["role": "user", "parts": parts])
            }
        }

        return contents
    }

    private static func functionResponsePart(name: String, content: String, isError: Bool) -> [String: Any] {
        [
            "functionResponse": [
                "name": name,
                "response": [
                    "result": content,
                    "isError": isError
                ]
            ]
        ]
    }

    /// Removes JSON Schema keywords Gemini does not accept.
    private static func sanitizeSchema(_ schema: Any) -> Any {
        guard let dictionary = schema as? [String: Any] else { return schema }
        var cleaned: [String: Any] = [:]
        for (key, value) in dictionary {
            switch key {
            case "properties":
                if let properties = value as? [String: Any] {
                    cleaned[key] = properties.mapValues { sanitizeSchema($0) }
                }
            case "items":
                cleaned[key] = sanitizeSchema(value)
            case "additionalProperties", "$schema", "title", "default":
                continue
            default:
                cleaned[key] = value
            }
        }
        return cleaned
    }

    private static func decode(_ data: String) -> [String: Any]? {
        guard let raw = data.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    private static func jsonObject(from argumentsJSON: String) -> Any {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [String: Any]() }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
    }

    private static func encodeArguments(_ arguments: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func mapFinishReason(_ reason: String) -> AIStopReason {
        switch reason.uppercased() {
        case "STOP": return .endTurn
        case "MAX_TOKENS": return .maxTokens
        case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII":
            return .stopSequence
        default: return .unknown
        }
    }
}
