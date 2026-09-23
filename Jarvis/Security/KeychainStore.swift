//
//  KeychainStore.swift
//  JARVIS
//
//  Thin wrapper around the Security framework for storing short secrets.
//  API keys live here and only here: never in UserDefaults, never in a
//  plist, never in the source tree, and never in a log line.
//

import Foundation
import Security
import os

/// Errors surfaced by `KeychainStore`.
enum KeychainError: LocalizedError {
    /// The Security framework returned an unexpected status code.
    case unexpectedStatus(OSStatus)
    /// The stored payload could not be converted to or from UTF-8 text.
    case dataConversionFailed
    /// The caller passed an empty key name.
    case emptyKey
    /// Access was denied, usually because the process is sandboxed without
    /// the required keychain entitlement.
    case accessDenied(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain returned status \(status): \(message)"
        case .dataConversionFailed:
            return "Keychain payload could not be converted to text."
        case .emptyKey:
            return "A keychain entry name is required."
        case .accessDenied(let status):
            return "Keychain access was denied (status \(status)). Check the app signature and entitlements."
        }
    }
}

/// Stores and retrieves secret strings in the macOS keychain.
///
/// Entries are generic passwords scoped to a service identifier, which keeps
/// them separate from anything else the user has saved. Nothing in this type
/// logs a secret value.
struct KeychainStore {

    /// Shared instance used by the application, keyed by the app bundle id.
    static let shared = KeychainStore(
        service: Bundle.main.bundleIdentifier ?? "com.jarvis.desktop"
    )

    /// Service attribute written to every item this store creates.
    let service: String

    /// Optional access group. Left nil for a standard per app keychain item.
    let accessGroup: String?

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Keychain")

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Public API

    /// Saves a secret, replacing any existing value for the same key.
    func setString(_ value: String, for key: String) throws {
        guard !key.isEmpty else { throw KeychainError.emptyKey }
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataConversionFailed }

        var query = baseQuery(for: key)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            // An updated secret is still a secret: no value is logged here.
            logger.debug("Updated keychain entry for \(key, privacy: .public)")
            return
        case errSecItemNotFound:
            break
        case errSecMissingEntitlement, errSecAuthFailed:
            throw KeychainError.accessDenied(updateStatus)
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        query.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            logger.debug("Created keychain entry for \(key, privacy: .public)")
        case errSecMissingEntitlement, errSecAuthFailed:
            throw KeychainError.accessDenied(addStatus)
        default:
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// Reads a secret, returning nil when it has not been stored yet.
    func string(for key: String) throws -> String? {
        guard !key.isEmpty else { throw KeychainError.emptyKey }

        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.dataConversionFailed }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        case errSecMissingEntitlement, errSecAuthFailed:
            throw KeychainError.accessDenied(status)
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Deletes a stored secret. Deleting a missing entry is not an error.
    func delete(key: String) throws {
        guard !key.isEmpty else { throw KeychainError.emptyKey }
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            logger.debug("Removed keychain entry for \(key, privacy: .public)")
        case errSecMissingEntitlement, errSecAuthFailed:
            throw KeychainError.accessDenied(status)
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Reports whether a value exists without reading it into memory.
    func containsValue(for key: String) -> Bool {
        guard !key.isEmpty else { return false }
        var query = baseQuery(for: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Lists the account names stored under this service.
    func storedKeys() throws -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        switch status {
        case errSecSuccess:
            let entries = items as? [[String: Any]] ?? []
            return entries.compactMap { $0[kSecAttrAccount as String] as? String }
        case errSecItemNotFound:
            return []
        case errSecMissingEntitlement, errSecAuthFailed:
            throw KeychainError.accessDenied(status)
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Internals

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
