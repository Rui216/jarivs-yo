//
//  FocusTimerService.swift
//  JARVIS
//
//  Drives the dashboard focus timer: 25, 50, and 90 minute presets with
//  start, pause, and reset. Completed and abandoned sessions are recorded
//  so the dashboard can report how much focused time the day holds.
//

import Foundation
import SwiftData
import os

/// Focus timer state machine.
@MainActor
@Observable
final class FocusTimerService {

    /// Preset currently selected.
    private(set) var preset: FocusPreset

    /// Seconds left in the current run.
    private(set) var remainingSeconds: Int

    /// True while the timer is counting down.
    private(set) var isRunning = false

    /// Number of sessions completed today.
    private(set) var completedToday = 0

    /// Seconds of focused time recorded today, including the current run.
    private(set) var focusedSecondsToday = 0

    private let context: ModelContext
    private var tickTask: Task<Void, Never>?
    private var sessionStartedAt: Date?
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Services")

    init(context: ModelContext, defaultPreset: FocusPreset = .short) {
        self.context = context
        self.preset = defaultPreset
        self.remainingSeconds = defaultPreset.minutes * 60
        refreshTodayTotals()
    }

    // MARK: - Derived state

    /// Fraction of the current preset that has elapsed, 0 to 1.
    var progress: Double {
        let total = Double(max(1, preset.minutes * 60))
        return min(max(1 - Double(remainingSeconds) / total, 0), 1)
    }

    /// Clock string for the remaining time.
    var remainingText: String {
        JarvisTimeFormat.clock(seconds: remainingSeconds)
    }

    /// True when the timer has been started and paused at least once.
    var isPaused: Bool {
        !isRunning && remainingSeconds < preset.minutes * 60
    }

    /// Human readable summary of today's focused time.
    var todaySummary: String {
        let minutes = focusedSecondsToday / 60
        if minutes == 0 { return "No focus sessions yet today" }
        return "\(minutes) min focused today, \(completedToday) session(s) finished"
    }

    // MARK: - Control

    /// Selects a preset, resetting any run in progress.
    func select(_ preset: FocusPreset) {
        cancelRun()
        self.preset = preset
        remainingSeconds = preset.minutes * 60
    }

    /// Starts or pauses the countdown.
    func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    /// Starts or resumes the countdown.
    func start() {
        guard !isRunning else { return }
        if sessionStartedAt == nil {
            sessionStartedAt = Date()
        }
        isRunning = true

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isRunning else { return }
                self.tick()
            }
        }
    }

    /// Pauses the countdown, banking the time focused so far.
    ///
    /// Each pause closes the current segment, so resuming later starts a
    /// new one and a reset can never record the same minutes twice.
    func pause() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        closeCurrentSegment(completed: false)
        refreshTodayTotals()
    }

    /// Resets the timer to the selected preset.
    func reset() {
        cancelRun()
        remainingSeconds = preset.minutes * 60
        sessionStartedAt = nil
        refreshTodayTotals()
    }

    // MARK: - Internals

    /// Advances the countdown by one second, finishing the session at zero.
    private func tick() {
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        if remainingSeconds == 0 {
            finishRun()
        }
    }

    private func finishRun() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        closeCurrentSegment(completed: true)
        sessionStartedAt = nil
        remainingSeconds = preset.minutes * 60
        refreshTodayTotals()
    }

    private func cancelRun() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        closeCurrentSegment(completed: false)
        sessionStartedAt = nil
        refreshTodayTotals()
    }

    /// Writes a session record for the segment that just ended.
    ///
    /// Segments shorter than a minute are dropped unless the timer ran to
    /// completion, so a quick start and stop does not litter the history.
    private func closeCurrentSegment(completed: Bool) {
        guard let startedAt = sessionStartedAt else { return }
        let elapsed = completed ? preset.minutes * 60 : Int(Date().timeIntervalSince(startedAt))
        sessionStartedAt = nil

        guard elapsed >= 60 || completed else { return }

        let record = FocusSessionRecord(
            startedAt: startedAt,
            plannedMinutes: preset.minutes,
            elapsedSeconds: elapsed,
            wasCompleted: completed
        )
        context.insert(record)
        do {
            try context.save()
        } catch {
            logger.error("Focus session save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Recomputes today's totals from stored sessions.
    func refreshTodayTotals() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<FocusSessionRecord>(
            predicate: #Predicate { $0.startedAt >= startOfDay },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        completedToday = sessions.filter(\.wasCompleted).count
        focusedSecondsToday = sessions.reduce(0) { $0 + $1.elapsedSeconds }
    }
}
