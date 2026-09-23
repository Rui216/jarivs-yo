//
//  NoteService.swift
//  JARVIS
//
//  Quick notes: the small capture area on the dashboard and the notes
//  screen share these operations.
//

import Foundation
import SwiftData

/// Creates, edits, and pins quick notes.
@MainActor
final class NoteService {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Writing

    /// Creates a note and returns it.
    @discardableResult
    func createNote(text: String) -> NoteItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = NoteItem(body: trimmed)
        context.insert(note)
        save()
        return note
    }

    /// Replaces the body of a note and updates its timestamp.
    func update(_ note: NoteItem, text: String) {
        note.body = text
        note.updatedAt = Date()
        save()
    }

    /// Pins or unpins a note.
    func togglePin(_ note: NoteItem) {
        note.isPinned.toggle()
        save()
    }

    /// Deletes a note.
    func delete(_ note: NoteItem) {
        context.delete(note)
        save()
    }

    // MARK: - Reading

    /// Notes ordered with pinned items first, then most recently updated.
    func recentNotes(limit: Int = 6) -> [NoteItem] {
        var descriptor = FetchDescriptor<NoteItem>(
            sortBy: [
                SortDescriptor(\.isPinned, order: .reverse),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Total note count for the notes screen header.
    func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<NoteItem>())) ?? 0
    }

    // MARK: - Internals

    private func save() {
        do {
            try context.save()
        } catch {
            Log.services.error("Note save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
