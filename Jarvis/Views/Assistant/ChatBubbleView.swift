//
//  ChatBubbleView.swift
//  JARVIS
//
//  One message in the assistant transcript, including the automation
//  chips that record what was done while answering.
//

import SwiftUI

/// Renders a single chat message.
struct ChatBubbleView: View {

    /// Message to render.
    let bubble: ChatViewModel.Bubble

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            body(for: bubble)
            if !bubble.actionSummaries.isEmpty {
                actionChips
            }
            if !bubble.footnote.isEmpty {
                Text(bubble.footnote)
                    .font(JarvisTheme.Typography.caption(9))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: bubble.role == .assistant ? "sparkles" : "person.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(bubble.role.tint)

            Text(bubble.role.displayName)
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(bubble.role.tint)

            Text(JarvisTimeFormat.shortTime(bubble.timestamp))
                .font(JarvisTheme.Typography.caption(9))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)

            if bubble.isStreaming {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            }
        }
    }

    @ViewBuilder
    private func body(for bubble: ChatViewModel.Bubble) -> some View {
        let isError = !bubble.errorText.isEmpty

        VStack(alignment: .leading, spacing: 4) {
            if bubble.text.isEmpty, bubble.isStreaming {
                Text("...")
                    .font(JarvisTheme.Typography.body(13))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            } else {
                Text(bubble.text)
                    .font(JarvisTheme.Typography.body(13))
                    .foregroundStyle(isError
                                     ? JarvisTheme.Palette.danger
                                     : JarvisTheme.Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, JarvisTheme.Spacing.regular)
        .padding(.vertical, JarvisTheme.Spacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .fill(isError
                      ? JarvisTheme.Palette.danger.opacity(0.1)
                      : bubble.role == .assistant
                        ? JarvisTheme.Palette.card.opacity(0.85)
                        : JarvisTheme.Palette.accent.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .strokeBorder(
                    isError
                        ? JarvisTheme.Palette.danger.opacity(0.35)
                        : bubble.role == .assistant
                            ? JarvisTheme.Palette.stroke
                            : JarvisTheme.Palette.accent.opacity(0.3),
                    lineWidth: 1
                )
        )
    }

    private var actionChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(bubble.actionSummaries.indices, id: \.self) { index in
                let summary = bubble.actionSummaries[index]
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(JarvisTheme.Palette.accent)
                    Text(summary)
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(JarvisTheme.Palette.accent.opacity(0.07))
                )
            }
        }
    }
}
