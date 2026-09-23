//
//  ChatMessageRecord.swift
//  JARVIS
//
//  Persisted transcript of the assistant conversation. Tool call
//  details live in the run time conversation buffer; only the visible
//  text and a one line action summary are stored so history survives
//  relaunches without replaying side effects.
//

import Foundation
import SwiftData

/// Who produced a chat message.
enum ChatRole: String, Codable {
    case user
    case assistant

    /// Label rendered above a bubble.
    var displayName: String {
        switch self {
        case .user: return "You"
        case .assistant: return "JARVIS"
        }
    }
}

/// A persisted chat message.
@Model
final class ChatMessageRecord {
    /// Raw storage for the role so SwiftData only persists a string.
    var roleRaw: String
    /// Visible text of the message.
    var text: String
    /// Creation timestamp.
    var createdAt: Date
    /// Optional summary of the automation performed while answering.
    var actionSummary: String
    /// Optional error text when the provider call failed.
    var errorText: String

    /// Typed accessor for the stored role.
    var role: ChatRole {
        get { ChatRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    /// Not persisted. True when the message carries a provider error.
    var isError: Bool { !errorText.isEmpty }

    init(
        role: ChatRole,
        text: String,
        createdAt: Date = Date(),
        actionSummary: String = "",
        errorText: String = ""
    ) {
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
        self.actionSummary = actionSummary
        self.errorText = errorText
    }
}
