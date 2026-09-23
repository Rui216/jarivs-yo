//
//  NoteItem.swift
//  JARVIS
//
//  Quick notes captured from the dashboard or by the assistant.
//  Persisted with SwiftData.
//

import Foundation
import SwiftData

/// A short free form note.
@Model
final class NoteItem {
    /// Note contents.
    var body: String
    /// Last modification timestamp.
    var updatedAt: Date
    /// Creation timestamp.
    var createdAt: Date
    /// Pinned notes appear first in the Quick Notes card.
    var isPinned: Bool

    /// Not persisted. First line of the note, used as a list title.
    var headline: String {
        let firstLine = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        return firstLine.isEmpty ? "Untitled note" : firstLine
    }

    init(
        body: String,
        updatedAt: Date = Date(),
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.body = body
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.isPinned = isPinned
    }
}
