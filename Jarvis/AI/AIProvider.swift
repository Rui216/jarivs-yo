//
//  AIProvider.swift
//  JARVIS
//
//  Provider identity, model catalog, and the protocol every chat
//  provider implements. The chat loop only ever talks to `AIProvider`,
//  so adding a provider means adding one file, not touching the UI.
//

import Foundation

// MARK: - Provider identity

/// The chat providers JARVIS can talk to.
enum AIProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic
    case openai
    case google
    case openrouter
    case groq

    var id: String { rawValue }

    /// Display name used in lists and menus.
    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI"
        case .google: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        case .groq: return "Groq"
        }
    }

    /// Short name used in compact chips.
    var shortName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "OpenAI"
        case .google: return "Gemini"
        case .openrouter: return "OpenRouter"
        case .groq: return "Groq"
        }
    }

    /// Keychain account name for this provider's API key.
    ///
    /// Keys are stored in the keychain only. Never in UserDefaults, a
    /// plist, the source tree, or a log line.
    var keychainAccount: String { "provider.\(rawValue).apiKey" }

    /// Where the user creates or manages an API key.
    var consoleURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .google: return URL(string: "https://aistudio.google.com/app/apikey")
        case .openrouter: return URL(string: "https://openrouter.ai/keys")
        case .groq: return URL(string: "https://console.groq.com/keys")
        }
    }

    /// Placeholder text shown in the key entry field.
    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-proj-..."
        case .google: return "AIza..."
        case .openrouter: return "sk-or-v1-..."
        case .groq: return "gsk_..."
        }
    }

    /// Models offered in the settings dropdown.
    ///
    /// The list is a convenience only: the settings screen accepts a custom
    /// model identifier so a newly released model can be used before this
    /// list is updated.
    var models: [AIModelDescriptor] {
        switch self {
        case .anthropic:
            return [
                AIModelDescriptor(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5"),
                AIModelDescriptor(id: "claude-opus-4-1", displayName: "Claude Opus 4.1"),
                AIModelDescriptor(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
                AIModelDescriptor(id: "claude-3-7-sonnet-latest", displayName: "Claude 3.7 Sonnet"),
                AIModelDescriptor(id: "claude-3-5-haiku-latest", displayName: "Claude 3.5 Haiku")
            ]
        case .openai:
            return [
                AIModelDescriptor(id: "gpt-5", displayName: "GPT-5"),
                AIModelDescriptor(id: "gpt-5-mini", displayName: "GPT-5 mini"),
                AIModelDescriptor(id: "gpt-4.1", displayName: "GPT-4.1"),
                AIModelDescriptor(id: "gpt-4o", displayName: "GPT-4o"),
                AIModelDescriptor(id: "gpt-4o-mini", displayName: "GPT-4o mini"),
                AIModelDescriptor(id: "o4-mini", displayName: "o4-mini (reasoning)")
            ]
        case .google:
            return [
                AIModelDescriptor(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
                AIModelDescriptor(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
                AIModelDescriptor(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash")
            ]
        case .openrouter:
            return [
                AIModelDescriptor(id: "anthropic/claude-sonnet-4.5", displayName: "Claude Sonnet 4.5"),
                AIModelDescriptor(id: "openai/gpt-5", displayName: "GPT-5"),
                AIModelDescriptor(id: "google/gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
                AIModelDescriptor(id: "meta-llama/llama-3.3-70b-instruct", displayName: "Llama 3.3 70B"),
                AIModelDescriptor(id: "deepseek/deepseek-chat", displayName: "DeepSeek Chat")
            ]
        case .groq:
            return [
                AIModelDescriptor(id: "llama-3.3-70b-versatile", displayName: "Llama 3.3 70B Versatile"),
                AIModelDescriptor(id: "llama-3.1-8b-instant", displayName: "Llama 3.1 8B Instant"),
                AIModelDescriptor(id: "openai/gpt-oss-120b", displayName: "GPT OSS 120B"),
                AIModelDescriptor(id: "moonshotai/kimi-k2-instruct", displayName: "Kimi K2 Instruct")
            ]
        }
    }

    /// Model selected when the user has not chosen one yet.
    var defaultModel: String { models.first?.id ?? "" }

    /// Whether the provider supports tool calling through its API.
    var supportsToolCalling: Bool {
        // Every provider in the catalog exposes function calling.
        true
    }
}

/// One selectable model for a provider.
struct AIModelDescriptor: Identifiable, Hashable, Sendable {
    /// Model identifier sent to the provider API.
    let id: String
    /// Friendly label shown in the dropdown.
    let displayName: String
}

// MARK: - Errors

/// Errors surfaced by the provider layer.
enum AIServiceError: LocalizedError, Equatable {
    /// No API key is stored for the selected provider.
    case missingAPIKey(AIProviderID)
    /// The provider rejected the credentials.
    case invalidAPIKey(AIProviderID)
    /// The provider throttled the request.
    case rateLimited(retryAfterSeconds: Int?)
    /// The provider returned a server error.
    case serverError(status: Int, message: String)
    /// The request could not reach the provider.
    case network(String)
    /// The response could not be decoded.
    case decoding(String)
    /// The user cancelled the request.
    case cancelled
    /// The model returned no usable content.
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Add an API key for \(provider.displayName) in Settings, AI Providers."
        case .invalidAPIKey(let provider):
            return "\(provider.displayName) rejected the stored API key. Check it in Settings, AI Providers."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "The provider is rate limiting requests. Try again in about \(retryAfter) seconds."
            }
            return "The provider is rate limiting requests. Try again shortly."
        case .serverError(let status, let message):
            return "Provider error \(status): \(message)"
        case .network(let description):
            return "Network problem: \(description)"
        case .decoding(let description):
            return "Could not read the provider response: \(description)"
        case .cancelled:
            return "Request cancelled."
        case .emptyResponse:
            return "The model returned an empty response."
        }
    }

    /// True when retrying the same request could succeed.
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .network, .serverError:
            return true
        default:
            return false
        }
    }
}

// MARK: - Provider protocol

/// Everything the UI needs to describe a provider without knowing its API.
struct AIProviderDescriptor: Sendable {
    let id: AIProviderID
    let displayName: String
    let defaultModel: String
    let models: [AIModelDescriptor]
    let consoleURL: URL?
    let keyPlaceholder: String
}

/// A chat provider. Implementations translate between the provider
/// agnostic message model and their own wire format, and never touch
/// keychain storage directly: the API key is passed in per request.
protocol AIProvider: Sendable {
    /// Provider this instance implements.
    var descriptor: AIProviderDescriptor { get }

    /// Streams one assistant turn.
    ///
    /// The returned stream emits text and tool call fragments as they
    /// arrive, then finishes. Throwing `AIServiceError` is expected for
    /// provider failures; transport errors are wrapped before they surface.
    func streamChat(
        request: AIChatRequest,
        apiKey: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error>
}

extension AIProvider {
    /// Convenience access to the provider identity.
    var id: AIProviderID { descriptor.id }
}
