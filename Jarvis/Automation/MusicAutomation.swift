//
//  MusicAutomation.swift
//  JARVIS
//
//  Playback control for Spotify and the Music app through Apple Events.
//

import Foundation
import os

/// Applications whose playback JARVIS can control.
enum MusicApplication: String, CaseIterable, Identifiable, Sendable {
    case spotify
    case music

    var id: String { rawValue }

    /// AppleScript application name.
    var applicationName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        }
    }

    /// Bundle identifier used to check installation.
    var bundleIdentifier: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    /// Resolves a loose application name from a tool call.
    static func from(name: String?) -> MusicApplication {
        guard let name = name?.lowercased(), !name.isEmpty else { return .spotify }
        return name.contains("music") ? .music : .spotify
    }
}

/// Playback actions the assistant may request.
enum MusicAction: String, CaseIterable, Identifiable, Sendable {
    case play
    case pause
    case playPause = "playpause"
    case next
    case previous
    case nowPlaying = "now_playing"

    var id: String { rawValue }

    /// Resolves a loose action name from a tool call.
    static func from(name: String?) -> MusicAction {
        guard let name = name?.lowercased(), !name.isEmpty else { return .nowPlaying }
        switch name {
        case "play": return .play
        case "pause": return .pause
        case "playpause", "toggle", "play_pause": return .playPause
        case "next", "next_track", "skip": return .next
        case "previous", "previous_track", "back": return .previous
        default: return .nowPlaying
        }
    }
}

/// Controls music playback through Apple Events.
@MainActor
final class MusicAutomation {

    /// Shared instance used by the automation bridge.
    static let shared = MusicAutomation()

    private let scripts = AppleScriptRunner.shared
    private let launcher = ApplicationLauncher.shared
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Automation")

    /// Performs a playback action and returns a short description.
    func perform(_ action: MusicAction, in application: MusicApplication) async throws -> String {
        guard launcher.isInstalled(bundleIdentifier: application.bundleIdentifier) else {
            throw AutomationError.applicationNotFound(application.applicationName)
        }

        let script: String
        switch action {
        case .play:
            script = "tell application \"\(application.applicationName)\" to play"
        case .pause:
            script = "tell application \"\(application.applicationName)\" to pause"
        case .playPause:
            script = "tell application \"\(application.applicationName)\" to playpause"
        case .next:
            script = "tell application \"\(application.applicationName)\" to next track"
        case .previous:
            script = "tell application \"\(application.applicationName)\" to previous track"
        case .nowPlaying:
            script = """
            tell application "\(application.applicationName)"
                if player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    return "Playing " & trackName & " by " & artistName
                else
                    return "Nothing is playing in \(application.applicationName)."
                end if
            end tell
            """
        }

        let output = try await scripts.run(script: script, timeout: 15)
        logger.debug("Music action \(action.rawValue, privacy: .public) completed in \(application.applicationName, privacy: .public)")

        switch action {
        case .nowPlaying:
            return output.isEmpty ? "Nothing is playing in \(application.applicationName)." : output
        case .play:
            return "Started playback in \(application.applicationName)."
        case .pause:
            return "Paused playback in \(application.applicationName)."
        case .playPause:
            return "Toggled playback in \(application.applicationName)."
        case .next:
            return "Skipped to the next track in \(application.applicationName)."
        case .previous:
            return "Went back to the previous track in \(application.applicationName)."
        }
    }
}
