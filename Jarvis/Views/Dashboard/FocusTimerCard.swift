//
//  FocusTimerCard.swift
//  JARVIS
//
//  Focus timer with 25, 50, and 90 minute presets, a start or pause
//  action, a reset, and today's focused time.
//

import SwiftUI

/// Focus timer with preset durations.
struct FocusTimerCard: View {

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let timer = environment.focusTimer

        JarvisCard(title: "Focus Timer", symbolName: "timer") {
            VStack(spacing: JarvisTheme.Spacing.regular) {
                presetRow

                ZStack {
                    RingProgress(progress: timer.progress, lineWidth: 10)
                        .frame(width: 138, height: 138)

                    VStack(spacing: 2) {
                        Text(timer.remainingText)
                            .font(JarvisTheme.Typography.display(30))
                            .monospacedDigit()
                            .foregroundStyle(JarvisTheme.Palette.textPrimary)
                        Text(timer.isRunning ? "In progress" : (timer.isPaused ? "Paused" : "Ready"))
                            .font(JarvisTheme.Typography.caption(10))
                            .foregroundStyle(timer.isRunning ? JarvisTheme.Palette.accent : JarvisTheme.Palette.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: JarvisTheme.Spacing.tight) {
                    Button(timer.isRunning ? "Pause" : "Start") {
                        timer.toggle()
                    }
                    .buttonStyle(.jarvisPrimary)

                    Button("Reset") {
                        timer.reset()
                    }
                    .buttonStyle(.jarvisSecondary)
                }

                Text(timer.todaySummary)
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(FocusPreset.allCases) { preset in
                let isSelected = environment.focusTimer.preset == preset
                Button {
                    environment.focusTimer.select(preset)
                    environment.settings.assign(\.focusPresetMinutes, preset.minutes)
                } label: {
                    Text(preset.displayName)
                        .font(JarvisTheme.Typography.caption(11))
                        .foregroundStyle(isSelected ? JarvisTheme.Palette.canvas : JarvisTheme.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected
                                      ? AnyShapeStyle(JarvisTheme.accentGradient)
                                      : AnyShapeStyle(JarvisTheme.Palette.canvas.opacity(0.55)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: isSelected ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
