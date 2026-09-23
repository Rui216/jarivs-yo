//
//  FocusSessionRecord.swift
//  JARVIS
//
//  Completed and aborted focus timer sessions, used for the daily
//  productivity readout on the dashboard.
//

import Foundation
import SwiftData

/// A single focus timer run.
@Model
final class FocusSessionRecord {
    /// When the session started.
    var startedAt: Date
    /// Planned duration in minutes.
    var plannedMinutes: Int
    /// Seconds actually spent focusing.
    var elapsedSeconds: Int
    /// Whether the session ran to completion.
    var wasCompleted: Bool

    /// Not persisted. Elapsed time expressed in whole minutes.
    var elapsedMinutes: Int {
        elapsedSeconds / 60
    }

    init(
        startedAt: Date = Date(),
        plannedMinutes: Int,
        elapsedSeconds: Int,
        wasCompleted: Bool
    ) {
        self.startedAt = startedAt
        self.plannedMinutes = plannedMinutes
        self.elapsedSeconds = elapsedSeconds
        self.wasCompleted = wasCompleted
    }
}

/// The focus timer presets offered on the dashboard.
enum FocusPreset: Int, CaseIterable, Identifiable {
    case short = 25
    case standard = 50
    case deep = 90

    var id: Int { rawValue }

    /// Duration in minutes.
    var minutes: Int { rawValue }

    /// Label shown on the preset button.
    var displayName: String { "\(rawValue) min" }
}
