//
//  APIKeyStore.swift
//  JARVIS
//
//  Observable facade over the keychain for provider credentials. The
//  settings screen binds to this type; the chat service asks it for the
//  active provider key at request time so a freshly saved key is used
//  immediately without a restart.
//

import Foundation
import Observation
import os

/// Reads and writes provider API keys in the keychain, and publishes
/// masked previews for display in Settings.
@MainActor
@Observable
final class APIKeyStore {

    /// Provider identifiers that currently have a key stored, and the
    /// masked preview shown in the settings list.
    private(set) var maskedKeys: [AIProviderID: String] = [:]

    /// Last error encountered while talking to the keychain, surfaced in the UI.
    private(set) var lastErrorMessage: String?

    private let keychain: KeychainStore
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "APIKeys")

    init(keychain: KeychainStore = .shared) {
        self.keychain = keychain
        refresh()
    }

    // MARK: - Queries

    /// True when at least one provider has a stored key.
    var hasAnyKey: Bool { !maskedKeys.isEmpty }

    /// Masked preview for a provider, or nil when no key is stored.
    func maskedKey(for provider: AIProviderID) -> String? {
        maskedKeys[provider]
    }

    /// True when the provider has a stored key.
    func hasKey(for provider: AIProviderID) -> Bool {
        maskedKeys[provider] != nil
    }

    /// Full secret for a provider. Used only when building a network request.
    ///
    /// The value is never logged, persisted elsewhere, or included in errors.
    func secret(for provider: AIProviderID) -> String? {
        do {
            let value = try keychain.string(for: provider.keychainAccount)
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("Keychain read failed for \(provider.keychainAccount, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Mutations

    /// Stores or replaces the API key for a provider.
    @discardableResult
    func saveKey(_ rawValue: String, for provider: AIProviderID) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        do {
            try keychain.setString(value, for: provider.keychainAccount)
            lastErrorMessage = nil
            refresh()
            return true
        } catch {
            logger.error("Keychain write failed for \(provider.keychainAccount, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Deletes the stored key for a provider.
    @discardableResult
    func removeKey(for provider: AIProviderID) -> Bool {
        do {
            try keychain.delete(key: provider.keychainAccount)
            lastErrorMessage = nil
            refresh()
            return true
        } catch {
            logger.error("Keychain delete failed for \(provider.keychainAccount, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Reloads the masked previews from the keychain.
    func refresh() {
        var updated: [AIProviderID: String] = [:]
        for provider in AIProviderID.allCases {
            do {
                if let secret = try keychain.string(for: provider.keychainAccount),
                   !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updated[provider] = Self.mask(secret)
                }
            } catch {
                logger.error("Keychain lookup failed for \(provider.keychainAccount, privacy: .public)")
                lastErrorMessage = error.localizedDescription
            }
        }
        maskedKeys = updated
    }

    // MARK: - Masking

    /// Builds a preview that shows only the first and last few characters.
    ///
    /// Short values are fully masked so a brief key is never reconstructed
    /// from the preview.
    static func mask(_ secret: String) -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return String(repeating: "*", count: max(4, trimmed.count)) }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)...\(suffix)"
    }
}
