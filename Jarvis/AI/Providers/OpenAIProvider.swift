//
//  OpenAIProvider.swift
//  JARVIS
//
//  OpenAI is served by the shared Chat Completions implementation with
//  OpenAI specific endpoint settings.
//

import Foundation

/// Streams chat completions from the OpenAI platform API.
struct OpenAIProvider: AIProvider {

    private let implementation = OpenAICompatibleProvider(configuration: .openAI)

    var descriptor: AIProviderDescriptor {
        AIProviderFactory.descriptor(for: .openai)
    }

    func streamChat(
        request: AIChatRequest,
        apiKey: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        implementation.streamChat(request: request, apiKey: apiKey)
    }
}
