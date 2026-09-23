//
//  AppShortcut.swift
//  JARVIS
//
//  Quick Tools entries. A shortcut points at an installed application,
//  a URL, or a folder. The default set matches the dashboard design:
//  Chrome, YouTube, Discord, Notion, ChatGPT, and a local folder.
//

import Foundation
import SwiftData

/// What a Quick Tools shortcut launches.
enum ShortcutKind: String, CaseIterable, Identifiable, Codable {
    /// An installed macOS application, targeted by name or bundle identifier.
    case application
    /// A web address opened in the default browser or a named browser.
    case url
    /// A folder revealed in Finder.
    case folder

    var id: String { rawValue }

    /// Human readable name used in the shortcut editor.
    var displayName: String {
        switch self {
        case .application: return "Application"
        case .url: return "Website"
        case .folder: return "Folder"
        }
    }

    /// Hint describing what the target field expects.
    var targetHint: String {
        switch self {
        case .application: return "Application name or bundle id, for example com.google.Chrome"
        case .url: return "Full address, for example https://www.youtube.com"
        case .folder: return "Absolute folder path, for example /Users/you/Desktop"
        }
    }
}

/// A Quick Tools tile on the dashboard.
@Model
final class AppShortcut {
    /// Label shown under the tile.
    var name: String
    /// SF Symbol drawn inside the tile.
    var symbolName: String
    /// Raw storage for `kind` so SwiftData only persists a string.
    var kindRaw: String
    /// Application name, bundle identifier, URL, or folder path.
    var target: String
    /// Tile tint stored as a 24 bit RGB integer.
    var tintHex: Int
    /// Ordering inside the Quick Tools row.
    var sortOrder: Int
    /// Disabled shortcuts stay in settings but leave the dashboard.
    var isEnabled: Bool

    /// Typed accessor for the stored kind.
    var kind: ShortcutKind {
        get { ShortcutKind(rawValue: kindRaw) ?? .url }
        set { kindRaw = newValue.rawValue }
    }

    init(
        name: String,
        symbolName: String,
        kind: ShortcutKind,
        target: String,
        tintHex: Int,
        sortOrder: Int,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.symbolName = symbolName
        self.kindRaw = kind.rawValue
        self.target = target
        self.tintHex = tintHex
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
    }
}

extension AppShortcut {
    /// The six tiles shown on the dashboard out of the box.
    static var defaultShortcuts: [AppShortcut] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            AppShortcut(
                name: "Chrome",
                symbolName: "globe",
                kind: .application,
                target: "com.google.Chrome",
                tintHex: 0x4285F4,
                sortOrder: 0
            ),
            AppShortcut(
                name: "YouTube",
                symbolName: "play.rectangle.fill",
                kind: .url,
                target: "https://www.youtube.com",
                tintHex: 0xFF0033,
                sortOrder: 1
            ),
            AppShortcut(
                name: "Discord",
                symbolName: "bubble.left.and.bubble.right.fill",
                kind: .application,
                target: "com.hnc.Discord",
                tintHex: 0x5865F2,
                sortOrder: 2
            ),
            AppShortcut(
                name: "Notion",
                symbolName: "square.text.square.fill",
                kind: .application,
                target: "notion.id",
                tintHex: 0xE9E9E9,
                sortOrder: 3
            ),
            AppShortcut(
                name: "ChatGPT",
                symbolName: "sparkles",
                kind: .url,
                target: "https://chatgpt.com",
                tintHex: 0x10A37F,
                sortOrder: 4
            ),
            AppShortcut(
                name: "Files",
                symbolName: "folder.fill",
                kind: .folder,
                target: "\(home)/Desktop",
                tintHex: 0x38D8EE,
                sortOrder: 5
            )
        ]
    }
}
