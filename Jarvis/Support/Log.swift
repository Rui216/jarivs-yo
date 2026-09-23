//
//  Log.swift
//  JARVIS
//
//  Unified logging categories. Rules for this file and for every call
//  site: never log API keys, tokens, message bodies, or file contents.
//  Use `Log.redacted` when a value must appear in a diagnostic line.
//

import Foundation
import os

/// Shared loggers, one per subsystem area.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jarvis.desktop"

    /// Application lifecycle, windows, and menus.
    static let app = Logger(subsystem: subsystem, category: "App")
    /// Dashboard data services such as tasks, notes, and homework.
    static let services = Logger(subsystem: subsystem, category: "Services")
    /// Machine statistics, weather, and other polling services.
    static let monitor = Logger(subsystem: subsystem, category: "Monitor")
    /// Application launching, Apple Events, and shell execution.
    static let automation = Logger(subsystem: subsystem, category: "Automation")
    /// Provider requests, streaming, and tool loops.
    static let assistant = Logger(subsystem: subsystem, category: "Assistant")
    /// Keychain reads and writes, always without secret values.
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")
    /// Calendar and reminders access.
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")
    /// Speech recognition and audio capture.
    static let speech = Logger(subsystem: subsystem, category: "Speech")
    /// File system browsing.
    static let files = Logger(subsystem: subsystem, category: "Files")

    /// Describes a secret without revealing it, for diagnostic lines only.
    static func redacted(_ secret: String?) -> String {
        guard let secret, !secret.isEmpty else { return "<unset>" }
        return "<redacted:\(secret.count) chars>"
    }
}
