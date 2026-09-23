//
//  ProviderHTTP.swift
//  JARVIS
//
//  Shared HTTP plumbing for provider requests: request construction,
//  status validation, and error decoding. Error text is extracted from
//  the provider payload but API keys are never included anywhere.
//

import Foundation
import os

/// Helpers used by every provider implementation.
enum ProviderHTTP {

    /// Timeout for the initial connection and response headers.
    static let requestTimeout: TimeInterval = 90

    /// Idle timeout while streaming a response body.
    static let resourceTimeout: TimeInterval = 600

    /// Body size cap when reading an error response.
    private static let maximumErrorBodyBytes = 16_384

    /// Session shared by provider calls.
    ///
    /// Configured with generous timeouts so long generations are not cut off,
    /// and with connection reuse so back to back turns stay fast.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = true
        configuration.httpAdditionalHeaders = ["User-Agent": "JARVIS/1.0 (macOS)"]
        return URLSession(configuration: configuration)
    }()

    /// Builds a POST request with a JSON body.
    static func makeJSONRequest(
        url: URL,
        headers: [String: String],
        body: [String: Any]
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    /// Opens a streaming request and validates the response status.
    ///
    /// On a non success status the error body is read and mapped onto an
    /// `AIServiceError` so the chat panel can show something actionable.
    static func openStream(
        url: URL,
        headers: [String: String],
        body: [String: Any],
        provider: AIProviderID
    ) async throws -> URLSession.AsyncBytes {
        let request = try makeJSONRequest(url: url, headers: headers, body: body)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIServiceError.network("The provider returned a non HTTP response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = try await collectErrorBody(from: bytes)
                throw makeError(status: http.statusCode, body: body, provider: provider, headers: http)
            }
            return bytes
        } catch let error as AIServiceError {
            throw error
        } catch let error as URLError {
            throw mapTransportError(error)
        } catch {
            throw AIServiceError.network(error.localizedDescription)
        }
    }

    /// Performs a buffered POST request and returns the decoded JSON object.
    ///
    /// Used by providers whose streaming endpoint is not SSE based.
    static func postJSON(
        url: URL,
        headers: [String: String],
        body: [String: Any],
        provider: AIProviderID
    ) async throws -> [String: Any] {
        let request = try makeJSONRequest(url: url, headers: headers, body: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIServiceError.network("The provider returned a non HTTP response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw makeError(status: http.statusCode, body: data, provider: provider, headers: http)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIServiceError.decoding("The provider response was not a JSON object.")
            }
            return object
        } catch let error as AIServiceError {
            throw error
        } catch let error as URLError {
            throw mapTransportError(error)
        } catch let error as DecodingError {
            throw AIServiceError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Errors

    /// Maps an HTTP status and payload onto a typed error.
    static func makeError(
        status: Int,
        body: Data,
        provider: AIProviderID,
        headers: HTTPURLResponse?
    ) -> AIServiceError {
        let message = extractMessage(from: body)
        switch status {
        case 401, 403:
            return .invalidAPIKey(provider)
        case 402:
            return .serverError(status: status, message: message.isEmpty ? "Payment required by the provider." : message)
        case 404:
            return .serverError(
                status: status,
                message: message.isEmpty ? "The provider could not find the requested model. Check the model name in Settings." : message
            )
        case 413:
            return .serverError(status: status, message: message.isEmpty ? "The request was too large." : message)
        case 429:
            let retryAfter = headers?.value(forHTTPHeaderField: "retry-after").flatMap(Int.init)
            _ = retryAfter
            return .rateLimited(retryAfterSeconds: retryAfter)
        case 500...599:
            return .serverError(status: status, message: message.isEmpty ? "The provider had an internal error." : message)
        default:
            return .serverError(status: status, message: message.isEmpty ? "Unexpected provider response." : message)
        }
    }

    /// Maps transport failures onto typed errors.
    static func mapTransportError(_ error: URLError) -> AIServiceError {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .timedOut, .dnsLookupFailed, .secureConnectionFailed:
            return .network(error.localizedDescription)
        default:
            return .network(error.localizedDescription)
        }
    }

    /// Reads a bounded error body so a failure can be described to the user.
    private static func collectErrorBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var buffer = Data()
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= maximumErrorBodyBytes { break }
        }
        return buffer
    }

    /// Pulls a human readable message out of a provider error payload.
    ///
    /// Providers disagree on shape, so several known layouts are probed and a
    /// short excerpt is used as a fallback.
    static func extractMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let message = error["message"] as? String { return message }
                if let message = error["type"] as? String { return message }
            }
            if let error = object["error"] as? String { return error }
            if let message = object["message"] as? String { return message }
            if let detail = object["detail"] as? String { return detail }
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        let condensed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(condensed.prefix(300))
    }
}
