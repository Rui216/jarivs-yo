//
//  ConfirmationOverlay.swift
//  JARVIS
//
//  The approval gate. When the assistant wants to run a terminal
//  command, or AppleScript when confirmations are enabled, this overlay
//  shows the exact text that will run and waits for an answer. The tool
//  call is suspended until the user decides.
//

import SwiftUI

/// Modal confirmation for automation the user must approve.
struct ConfirmationOverlay: View {

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let request = environment.confirmations.current {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .ignoresSafeArea()
                    .transition(.opacity)

                card(for: request)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            .animation(.easeOut(duration: 0.15), value: request.id)
        }
    }

    // MARK: - Card

    private func card(for request: AutomationConfirmationRequest) -> some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            HStack(spacing: JarvisTheme.Spacing.tight) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(JarvisTheme.Palette.warning.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: request.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(JarvisTheme.Palette.warning)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(request.title)
                        .font(JarvisTheme.Typography.title(15))
                        .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    Text("Waiting for your approval")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }
                Spacer(minLength: 0)
            }

            Text(request.detail)
                .font(JarvisTheme.Typography.body(12))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("EXACT INPUT")
                    .font(JarvisTheme.Typography.caption(9))
                    .tracking(1.0)
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                ScrollView {
                    Text(request.payload)
                        .font(JarvisTheme.Typography.mono(11))
                        .foregroundStyle(JarvisTheme.Palette.accentBright)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(JarvisTheme.Spacing.tight)
                }
                .frame(maxHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(JarvisTheme.Palette.canvas.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
                )
            }

            Text("Declining sends the refusal back to the assistant, which will not retry on its own. Unanswered requests are declined automatically after \(request.timeoutSeconds) seconds.")
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: JarvisTheme.Spacing.tight) {
                Spacer()
                Button("Decline") {
                    environment.confirmations.declineCurrent()
                }
                .buttonStyle(.jarvisDanger)
                .keyboardShortcut(.cancelAction)

                Button(request.confirmLabel) {
                    environment.confirmations.approveCurrent()
                }
                .buttonStyle(.jarvisPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(JarvisTheme.Spacing.loose)
        .frame(width: 460)
        .jarvisCard(elevated: true, highlighted: true, cornerRadius: JarvisTheme.Radius.card)
        .shadow(color: Color.black.opacity(0.5), radius: 30, y: 12)
    }
}
