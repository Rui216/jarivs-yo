//
//  QuickToolsRow.swift
//  JARVIS
//
//  Quick Tools: one tap shortcuts to Chrome, YouTube, Discord, Notion,
//  ChatGPT, a local folder, and anything else added in Settings.
//

import SwiftUI
import SwiftData

/// Row of shortcut tiles.
struct QuickToolsRow: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \AppShortcut.sortOrder, order: .forward) private var shortcuts: [AppShortcut]

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 10)]

    var body: some View {
        JarvisCard(title: "Quick Tools", symbolName: "bolt") {
            if enabledShortcuts.isEmpty {
                EmptyStateView(
                    symbolName: "bolt.slash",
                    title: "No shortcuts",
                    message: "Add tiles on the Apps screen."
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(enabledShortcuts) { shortcut in
                        tile(shortcut)
                    }
                }
            }

            if let message = environment.quickTools.lastErrorMessage {
                Text(message)
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } accessory: {
            Button {
                environment.appState.destination = .apps
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(JarvisTheme.Palette.textTertiary)
            .help("Edit Quick Tools")
        }
    }

    // MARK: - Tile

    private func tile(_ shortcut: AppShortcut) -> some View {
        let tint = Color(hex: UInt32(truncatingIfNeeded: shortcut.tintHex))

        return Button {
            Task {
                await environment.quickTools.open(shortcut)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: shortcut.symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tint)
                }
                .jarvisGlow(tint, radius: 10, opacity: 0.25)

                Text(shortcut.name)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, JarvisTheme.Spacing.regular)
            .background(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .fill(JarvisTheme.Palette.canvas.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                    .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(for: shortcut))
    }

    private func helpText(for shortcut: AppShortcut) -> String {
        switch shortcut.kind {
        case .application: return "Open \(shortcut.name)"
        case .url: return "Open \(shortcut.target)"
        case .folder: return "Reveal \(shortcut.target)"
        }
    }

    private var enabledShortcuts: [AppShortcut] {
        shortcuts.filter(\.isEnabled)
    }
}
