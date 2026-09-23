//
//  AIMessage.swift
//  JARVIS
//
//  Provider agnostic request and stream types. Each provider maps these
//  onto its own wire format, which keeps the chat loop and the tool loop
//  identical no matter which model is selected.
//

import Foundation

// MARK: - Messages

/// Role of a message in a conversation.
enum AIRole: String, Sendable, Codable {
    case system
    case user
    case assistant
    /// A tool result being returned to the model.
    case tool
}

/// One block of content inside a message.
enum AIContentBlock: Sendable, Equatable {
    /// Plain text.
    case text(String)
    /// An image encoded as base64, reserved for future vision input.
    case imageBase64(mediaType: String, base64: String)
    /// A request from the model to run a tool.
    case toolCall(id: String, name: String, argumentsJSON: String)
    /// The result of running a tool.
    case toolResult(toolCallID: String, toolName: String, content: String, isError: Bool)

    /// Text payload when this block is text, otherwise nil.
    var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

/// A single conversation message.
struct AIMessage: Sendable, Equatable, Identifiable {
    /// Identifier used for list rendering in the chat panel.
    let id: UUID
    /// Conversation role.
    var role: AIRole
    /// Ordered content blocks.
    var content: [AIContentBlock]

    init(id: UUID = UUID(), role: AIRole, content: [AIContentBlock]) {
        self.id = id
        self.role = role
        self.content = content
    }

    /// Creates a plain text message.
    static func text(_ role: AIRole, _ text: String) -> AIMessage {
        AIMessage(role: role, content: [.text(text)])
    }

    /// Concatenated text of every text block.
    var plainText: String {
        content.compactMap(\.textValue).joined()
    }

    /// Tool calls contained in this message.
    var toolCalls: [(id: String, name: String, argumentsJSON: String)] {
        content.compactMap { block in
            if case .toolCall(let id, let name, let arguments) = block {
                return (id, name, arguments)
            }
            return nil
        }
    }
}

// MARK: - Tools

/// Schema value used to describe tool parameters as JSON Schema.
///
/// A small typed enum keeps tool definitions free of `Any` and safe to
/// pass across concurrency domains.
indirect enum SchemaValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case array([SchemaValue])
    case object([String: SchemaValue])

    /// Foundation compatible representation for JSON serialization.
    var jsonObject: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .integer(let value): return value
        case .boolean(let value): return value
        case .array(let values): return values.map(\.jsonObject)
        case .object(let dictionary): return dictionary.mapValues(\.jsonObject)
        }
    }
}

/// A tool the assistant may call, described with JSON Schema parameters.
struct AssistantToolSchema: Sendable, Identifiable, Equatable {
    /// Function name sent to the provider.
    let name: String
    /// Description that tells the model when to use the tool.
    let description: String
    /// JSON Schema object describing the parameters.
    let parameters: SchemaValue

    var id: String { name }

    /// Serializes the parameters object for providers that expect a string.
    func parametersJSONString() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: parameters.jsonObject, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw AIServiceError.decoding("Tool schema could not be encoded.")
        }
        return text
    }
}

// MARK: - Requests

/// One assistant turn request.
struct AIChatRequest: Sendable {
    /// Model identifier.
    var model: String
    /// System prompt describing persona, environment, and safety rules.
    var systemPrompt: String
    /// Conversation so far, oldest first.
    var messages: [AIMessage]
    /// Tools offered to the model.
    var tools: [AssistantToolSchema]
    /// Maximum tokens to generate in this turn.
    var maxOutputTokens: Int
    /// Sampling temperature. Omitted for models that reject custom values.
    var temperature: Double?
}

// MARK: - Stream events

/// Why the model stopped generating.
enum AIStopReason: String, Sendable {
    case endTurn
    case toolUse
    case maxTokens
    case stopSequence
    case unknown

    /// Maps provider specific stop reasons onto this enum.
    static func fromWire(_ raw: String?) -> AIStopReason {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return .unknown }
        switch raw {
        case "end_turn", "stop", "stop_sequence_end", "complete": return .endTurn
        case "tool_use", "tool_calls", "function_call": return .toolUse
        case "max_tokens", "length", "max_output_tokens": return .maxTokens
        case "stop_sequence": return .stopSequence
        default: return .unknown
        }
    }
}

/// Incremental events emitted while a turn streams in.
enum AIStreamEvent: Sendable {
    /// A chunk of assistant text.
    case text(String)
    /// A fragment of a tool call. `index` groups fragments of the same call.
    case toolCallDelta(index: Int, id: String?, name: String?, argumentsFragment: String)
    /// Token accounting when the provider reports it.
    case usage(inputTokens: Int, outputTokens: Int)
    /// Terminal event for the turn.
    case completed(stopReason: AIStopReason)
}

/// Accumulates streamed tool call fragments into complete calls.
struct ToolCallAccumulator: Sendable {
    /// A tool call being assembled.
    struct Partial: Sendable {
        var id: String
        var name: String
        var argumentsJSON: String
    }

    private var partials: [Int: Partial] = [:]
    private var order: [Int] = []

    /// Adds a fragment, creating the entry on first sight.
    mutating func append(index: Int, id: String?, name: String?, argumentsFragment: String) {
        if partials[index] == nil {
            partials[index] = Partial(
                id: id ?? "tool-\(index)",
                name: name ?? "",
                argumentsJSON: ""
            )
            order.append(index)
        }
        if let id, !id.isEmpty { partials[index]?.id = id }
        if let name, !name.isEmpty { partials[index]?.name = name }
        partials[index]?.argumentsJSON += argumentsFragment
    }

    /// True when at least one tool call is in flight.
    var isEmpty: Bool { order.isEmpty }

    /// Complete calls in the order they were started.
    var calls: [Partial] {
        order.compactMap { partials[$0] }.filter { !$0.name.isEmpty }
    }
}
