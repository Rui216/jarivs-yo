//
//  SSEStream.swift
//  JARVIS
//
//  Minimal server sent events reader shared by the streaming providers.
//  Anthropic, OpenAI, OpenRouter, Groq, and the Gemini SSE endpoint all
//  speak this format, so a single implementation covers every case.
//

import Foundation

/// One decoded server sent event.
struct ServerSentEvent: Sendable {
    /// Value of the `event:` field when present.
    var event: String?
    /// Joined `data:` payload, with the trailing sentinel stripped by callers.
    var data: String

    /// Sentinel payload used by OpenAI compatible endpoints to end a stream.
    var isDone: Bool { data.trimmingCharacters(in: .whitespaces) == "[DONE]" }
}

/// Turns a byte stream from `URLSession` into decoded server sent events.
enum SSEParser {

    /// Maximum size of a single event payload, guarding against a runaway stream.
    private static let maximumPayloadBytes = 1_048_576

    /// Decodes events until the underlying connection closes.
    ///
    /// The returned stream finishes when the source ends and fails when the
    /// transport fails. Cancelling the consuming task cancels the reader.
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let reader = Task {
                var dataLines: [String] = []
                var eventName: String?
                var payloadBytes = 0

                func flush() {
                    guard !dataLines.isEmpty else { return }
                    let payload = dataLines.joined(separator: "\n")
                    continuation.yield(ServerSentEvent(event: eventName, data: payload))
                    dataLines.removeAll(keepingCapacity: true)
                    eventName = nil
                    payloadBytes = 0
                }

                do {
                    for try await rawLine in bytes.lines {
                        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

                        if line.isEmpty {
                            flush()
                            continue
                        }
                        if line.hasPrefix(":") {
                            continue
                        }

                        guard let separator = line.firstIndex(of: ":") else {
                            continue
                        }
                        let field = String(line[line.startIndex..<separator])
                        var value = String(line[line.index(after: separator)...])
                        if value.hasPrefix(" ") { value.removeFirst() }

                        switch field {
                        case "event":
                            eventName = value
                        case "data":
                            payloadBytes += value.utf8.count
                            guard payloadBytes <= maximumPayloadBytes else {
                                throw AIServiceError.decoding("Stream event exceeded the size limit.")
                            }
                            dataLines.append(value)
                        default:
                            // id, retry, and unknown fields are not needed here.
                            break
                        }
                    }
                    flush()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                reader.cancel()
            }
        }
    }
}
