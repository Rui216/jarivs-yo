//
//  QuickNotesCard.swift
//  JARVIS
//
//  Quick notes under the assistant: capture a line in one keystroke,
//  pin what matters, and open a note to edit it.
//

import SwiftUI
import SwiftData

/// Quick note capture and list.
struct QuickNotesCard: View {

    @Environment(AppEnvironment.self) private var environment

    @Query(
        sort: [
            SortDescriptor(\NoteItem.isPinned, order: .reverse),
            SortDescriptor(\NoteItem.updatedAt, order: .reverse)
        ]
    )
    private var notes: [NoteItem]

    @State private var draft = ""
    @State private var editingNote: NoteItem?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            header
            inputRow
            noteList
        }
        .padding(JarvisTheme.Spacing.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JarvisTheme.Palette.canvas.opacity(0.35))
        .sheet(item: $editingNote) { note in
            NoteEditorSheet(note: note)
                .environment(environment)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JarvisTheme.Palette.accent)
            Text("Quick Notes")
                .font(JarvisTheme.Typography.title(13))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
            Spacer(minLength: 0)
            Text("\(notes.count)")
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
        }
    }

    private var inputRow: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            TextField("New note", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .jarvisField(focused: inputFocused)
                .focused($inputFocused)
                .onSubmit(addNote)

            Button(action: addNote) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(JarvisTheme.Palette.canvas)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(JarvisTheme.accentGradient)
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var noteList: some View {
        if notes.isEmpty {
            Text("Notes you save here, or that the assistant saves for you, appear in this list.")
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        } else {
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(notes.prefix(20)) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    private func noteRow(_ note: NoteItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                environment.notes.togglePin(note)
            } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(note.isPinned ? JarvisTheme.Palette.accent : JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help(note.isPinned ? "Unpin" : "Pin to the top")

            VStack(alignment: .leading, spacing: 1) {
                Text(note.headline)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    .lineLimit(1)
                Text(JarvisTimeFormat.relative(from: note.updatedAt))
                    .font(JarvisTheme.Typography.caption(9))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }

            Spacer(minLength: 0)

            Button {
                editingNote = note
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Edit the note")

            Button {
                environment.notes.delete(note)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Delete the note")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(JarvisTheme.Palette.card.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func addNote() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        environment.notes.createNote(text: text)
        draft = ""
        inputFocused = true
    }
}

/// Editor sheet for a single note.
struct NoteEditorSheet: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    /// Note being edited.
    let note: NoteItem

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            HStack {
                Text("Note")
                    .font(JarvisTheme.Typography.title(16))
                    .foregroundStyle(JarvisTheme.Palette.textPrimary)
                Spacer()
                Text("Updated \(JarvisTimeFormat.relative(from: note.updatedAt))")
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
            }

            TextEditor(text: $text)
                .font(JarvisTheme.Typography.body(13))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(JarvisTheme.Spacing.tight)
                .frame(minHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                        .fill(JarvisTheme.Palette.canvas.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                        .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
                )

            HStack(spacing: JarvisTheme.Spacing.tight) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.jarvisSecondary)
                Spacer()
                Button("Save") {
                    environment.notes.update(note, text: text)
                    dismiss()
                }
                .buttonStyle(.jarvisPrimary)
            }
        }
        .padding(JarvisTheme.Spacing.loose)
        .frame(width: 460)
        .background(JarvisTheme.Palette.canvasElevated)
        .onAppear { text = note.body }
    }
}
