//
//  AppsView.swift
//  JARVIS
//
//  Manages the Quick Tools tiles: add, edit, reorder, enable, and remove.
//  The same tiles appear in the dashboard Quick Tools row.
//

import SwiftUI
import SwiftData

/// Quick Tools management screen.
struct AppsView: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \AppShortcut.sortOrder, order: .forward) private var shortcuts: [AppShortcut]

    @State private var editingShortcut: AppShortcut?
    @State private var isAddingShortcut = false
    @State private var statusMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: JarvisTheme.Spacing.regular)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
                header

                if let statusMessage {
                    Text(statusMessage)
                        .font(JarvisTheme.Typography.caption(11))
                        .foregroundStyle(JarvisTheme.Palette.textSecondary)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                    ForEach(shortcuts) { shortcut in
                        tile(shortcut)
                    }

                    addTile
                }
            }
            .padding(JarvisTheme.Layout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .sheet(item: $editingShortcut) { shortcut in
            ShortcutEditorSheet(shortcut: shortcut)
                .environment(environment)
        }
        .sheet(isPresented: $isAddingShortcut) {
            ShortcutEditorSheet(shortcut: nil)
                .environment(environment)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            Text("Apps and Quick Tools")
                .font(JarvisTheme.Typography.display(26))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Text("Tiles launch an application, open a website, or reveal a folder. Disabled tiles stay here but leave the dashboard.")
                .font(JarvisTheme.Typography.body(12))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
        }
    }

    // MARK: - Tiles

    private func tile(_ shortcut: AppShortcut) -> some View {
        let tint = Color(hex: UInt32(truncatingIfNeeded: shortcut.tintHex))

        return VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: shortcut.symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tint)
                }
                Spacer(minLength: 0)
                StatusChip(
                    text: shortcut.isEnabled ? shortcut.kind.displayName : "Hidden",
                    tint: shortcut.isEnabled ? JarvisTheme.Palette.textSecondary : JarvisTheme.Palette.textTertiary
                )
            }

            Text(shortcut.name)
                .font(JarvisTheme.Typography.headline(13))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
                .lineLimit(1)

            Text(shortcut.target)
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                Button("Open") {
                    Task {
                        statusMessage = await environment.quickTools.open(shortcut)
                            ?? "Opened \(shortcut.name)."
                    }
                }
                .buttonStyle(.jarvisSecondary)

                Button("Edit") {
                    editingShortcut = shortcut
                }
                .buttonStyle(.jarvisSecondary)
            }
        }
        .padding(JarvisTheme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard(elevated: shortcut.isEnabled, highlighted: false)
        .opacity(shortcut.isEnabled ? 1 : 0.6)
        .contextMenu {
            Button(shortcut.isEnabled ? "Hide from dashboard" : "Show on dashboard") {
                shortcut.isEnabled.toggle()
                try? environment.modelContainer.mainContext.save()
            }
            Button("Edit") { editingShortcut = shortcut }
            Divider()
            Button("Move left") { move(shortcut, by: -1) }
            Button("Move right") { move(shortcut, by: 1) }
            Divider()
            Button("Delete", role: .destructive) {
                environment.quickTools.delete(shortcut, in: environment.modelContainer.mainContext)
                statusMessage = "Removed \(shortcut.name)."
            }
        }
    }

    private var addTile: some View {
        Button {
            isAddingShortcut = true
        } label: {
            VStack(spacing: JarvisTheme.Spacing.tight) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.accent)
                Text("Add a tile")
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, JarvisTheme.Spacing.section)
            .background(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.card, style: .continuous)
                    .fill(JarvisTheme.Palette.accent.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.card, style: .continuous)
                    .strokeBorder(
                        JarvisTheme.Palette.accent.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func move(_ shortcut: AppShortcut, by offset: Int) {
        let ordered = shortcuts.sorted { $0.sortOrder < $1.sortOrder }
        guard let index = ordered.firstIndex(where: { $0.id == shortcut.id }) else { return }
        let target = index + offset
        guard target >= 0, target < ordered.count else { return }
        let other = ordered[target]
        let swappedOrder = shortcut.sortOrder
        shortcut.sortOrder = other.sortOrder
        other.sortOrder = swappedOrder
        try? environment.modelContainer.mainContext.save()
    }
}

// MARK: - Editor

/// Creates or edits a Quick Tools tile.
struct ShortcutEditorSheet: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    /// Tile being edited, nil when creating a new one.
    let shortcut: AppShortcut?

    @State private var name = ""
    @State private var symbolName = "star"
    @State private var kind: ShortcutKind = .application
    @State private var target = ""
    @State private var tintHex = 0x38D8EE
    @State private var errorMessage: String?

    private static let symbolChoices = [
        "star", "globe", "play.rectangle.fill", "bubble.left.and.bubble.right.fill",
        "square.text.square.fill", "sparkles", "folder.fill", "terminal.fill",
        "envelope.fill", "music.note", "cart.fill", "book.fill", "doc.text.fill", "camera.fill"
    ]

    /// Preset tile colors.
    private struct TintChoice: Identifiable {
        let name: String
        let hex: Int

        var id: Int { hex }
    }

    private static let tintChoices: [TintChoice] = [
        TintChoice(name: "Cyan", hex: 0x38D8EE),
        TintChoice(name: "Blue", hex: 0x4285F4),
        TintChoice(name: "Violet", hex: 0x9B8CFF),
        TintChoice(name: "Green", hex: 0x3DDC97),
        TintChoice(name: "Amber", hex: 0xF5B94B),
        TintChoice(name: "Red", hex: 0xFF6B6B),
        TintChoice(name: "Slate", hex: 0x93A9CC)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            Text(shortcut == nil ? "Add a Quick Tool" : "Edit Quick Tool")
                .font(JarvisTheme.Typography.display(20))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)

            TextField("Name shown on the tile", text: $name)
                .jarvisField()

            Picker("Type", selection: $kind) {
                ForEach(ShortcutKind.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            TextField(kind.targetHint, text: $target)
                .jarvisField()

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Icon")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 7), spacing: 6) {
                    ForEach(Self.symbolChoices, id: \.self) { symbol in
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(symbolName == symbol ? JarvisTheme.Palette.canvas : JarvisTheme.Palette.textSecondary)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(symbolName == symbol
                                              ? AnyShapeStyle(JarvisTheme.accentGradient)
                                              : AnyShapeStyle(JarvisTheme.Palette.canvas.opacity(0.5)))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Color")
                HStack(spacing: 8) {
                    ForEach(Self.tintChoices) { choice in
                        Button {
                            tintHex = choice.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: UInt32(choice.hex)))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().strokeBorder(
                                        tintHex == choice.hex ? JarvisTheme.Palette.textPrimary : Color.clear,
                                        lineWidth: 2
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(choice.name)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.danger)
            }

            HStack(spacing: JarvisTheme.Spacing.tight) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.jarvisSecondary)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.jarvisPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(JarvisTheme.Spacing.section)
        .frame(width: 520)
        .background(JarvisTheme.canvasGradient)
        .onAppear(perform: load)
    }

    private func load() {
        guard let shortcut else { return }
        name = shortcut.name
        symbolName = shortcut.symbolName
        kind = shortcut.kind
        target = shortcut.target
        tintHex = shortcut.tintHex
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedTarget.isEmpty else { return }

        if let shortcut {
            shortcut.name = trimmedName
            shortcut.symbolName = symbolName
            shortcut.kind = kind
            shortcut.target = trimmedTarget
            shortcut.tintHex = tintHex
        } else {
            environment.quickTools.createShortcut(
                in: environment.modelContainer.mainContext,
                name: trimmedName,
                symbolName: symbolName,
                kind: kind,
                target: trimmedTarget,
                tintHex: tintHex
            )
        }

        try? environment.modelContainer.mainContext.save()
        dismiss()
    }
}
