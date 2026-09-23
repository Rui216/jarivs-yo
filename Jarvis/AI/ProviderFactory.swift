//
//  ProviderFactory.swift
//  JARVIS
//
//  Single place that maps a provider identifier onto an implementation.
//  Adding a provider means adding a case to `AIProviderID`, a model list,
//  and an implementation, with no changes to the chat loop.
//

import Foundation

/// Creates provider implementations.
enum AIProviderFactory {

    /// Returns a provider implementation for the given identifier.
    static func makeProvider(for id: AIProviderID) -> any AIProvider {
        switch id {
        case .anthropic:
            return AnthropicProvider()
        case .openai:
            return OpenAIProvider()
        case .google:
            return GeminiProvider()
        case .openrouter:
            return OpenAICompatibleProvider(
                configuration: .openRouter,
                identity: .openrouter
            )
        case .groq:
            return OpenAICompatibleProvider(
                configuration: .groq,
                identity: .groq
            )
        }
    }

    /// Describes a provider without instantiating it.
    static func descriptor(for id: AIProviderID) -> AIProviderDescriptor {
        AIProviderDescriptor(
            id: id,
            displayName: id.displayName,
            defaultModel: id.defaultModel,
            models: id.models,
            consoleURL: id.consoleURL,
            keyPlaceholder: id.keyPlaceholder
        )
    }
}
