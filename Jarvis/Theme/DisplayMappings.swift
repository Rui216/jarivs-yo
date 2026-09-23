//
//  DisplayMappings.swift
//  JARVIS
//
//  Maps model level enumerations onto colors and symbols. Model files
//  stay free of SwiftUI imports; all presentation decisions live here
//  and in the views that consume them.
//

import SwiftUI

// MARK: - Tasks

extension TaskPriority {
    /// Color used for the priority marker.
    var tint: Color {
        switch self {
        case .low: return JarvisTheme.Palette.info
        case .normal: return JarvisTheme.Palette.accent
        case .high: return JarvisTheme.Palette.danger
        }
    }

    /// SF Symbol used for the priority marker.
    var symbolName: String {
        switch self {
        case .low: return "arrow.down"
        case .normal: return "minus"
        case .high: return "arrow.up"
        }
    }
}

// MARK: - System metrics

extension ProcessorLoadLevel {
    /// Color used for the processor readout.
    var tint: Color {
        switch self {
        case .idle: return JarvisTheme.Palette.success
        case .moderate: return JarvisTheme.Palette.warning
        case .heavy: return JarvisTheme.Palette.danger
        }
    }
}

// MARK: - Weather

extension WeatherCondition {
    /// Accent color used for the weather glyph.
    var tint: Color {
        switch self {
        case .clear, .mostlyClear: return JarvisTheme.Palette.warning
        case .partlyCloudy: return JarvisTheme.Palette.accent
        case .overcast, .fog, .unknown: return JarvisTheme.Palette.textSecondary
        case .drizzle, .rain: return JarvisTheme.Palette.info
        case .snow: return JarvisTheme.Palette.accentBright
        case .thunderstorm: return JarvisTheme.Palette.violet
        }
    }
}

// MARK: - Shortcuts

extension ShortcutKind {
    /// SF Symbol shown in the shortcut editor for this kind.
    var symbolName: String {
        switch self {
        case .application: return "app.fill"
        case .url: return "link"
        case .folder: return "folder.fill"
        }
    }
}

// MARK: - Chat

extension ChatRole {
    /// Accent color for the message bubble role label.
    var tint: Color {
        switch self {
        case .user: return JarvisTheme.Palette.info
        case .assistant: return JarvisTheme.Palette.accent
        }
    }
}

/// How the assistant is currently behaving in the chat panel.
enum AssistantActivity: Equatable {
    case idle
    case listening
    case thinking
    case working(String)

    /// Caption rendered under the chat header.
    var label: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .working(let detail): return detail
        }
    }

    /// Color of the activity dot.
    var tint: Color {
        switch self {
        case .idle: return JarvisTheme.Palette.textTertiary
        case .listening: return JarvisTheme.Palette.danger
        case .thinking: return JarvisTheme.Palette.warning
        case .working: return JarvisTheme.Palette.accent
        }
    }

    /// True while a request is in flight.
    var isBusy: Bool {
        switch self {
        case .idle, .listening: return false
        case .thinking, .working: return true
        }
    }
}
