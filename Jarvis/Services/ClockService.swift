//
//  ClockService.swift
//  JARVIS
//
//  A single ticking clock shared by the header and the large clock card,
//  so the interface has one timer instead of several.
//

import Foundation

/// Publishes the current time once per second.
@MainActor
@Observable
final class ClockService {

    /// Current time, updated on every tick.
    private(set) var now: Date = Date()

    /// True while the ticker is running.
    private(set) var isTicking = false

    private var tickTask: Task<Void, Never>?

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    /// Applies the current locale and starts ticking.
    func start() {
        guard !isTicking else { return }
        isTicking = true
        now = Date()

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.now = Date()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Stops the ticker.
    func stop() {
        tickTask?.cancel()
        tickTask = nil
        isTicking = false
    }

    /// Time with seconds, for example "09:41:07".
    var timeText: String {
        timeFormatter.string(from: now)
    }

    /// Time without seconds, for example "09:41".
    var shortTimeText: String {
        shortTimeFormatter.string(from: now)
    }

    /// Full date, for example "Saturday, 14 March 2026".
    var dateText: String {
        dateFormatter.string(from: now)
    }

    /// Hour of the day, used to pick the greeting.
    var hour: Int {
        Calendar.current.component(.hour, from: now)
    }

    /// Time aware greeting.
    var greeting: String {
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Working late"
        }
    }
}
