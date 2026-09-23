//
//  PathGuard.swift
//  JARVIS
//
//  One place that decides which locations on disk JARVIS may open,
//  reveal, or read through a whitelisted command. Keeping the rule in a
//  single type means the Finder automation and the command whitelist can
//  never disagree about what is allowed.
//

import Foundation

/// Validates file system paths used by automation.
enum PathGuard {

    /// Folders automation may touch. Everything else is refused.
    static let allowedRoots: [String] = [
        FileManager.default.homeDirectoryForCurrentUser.path,
        "/tmp",
        "/private/tmp",
        "/Applications",
        "/Volumes",
        "/Users"
    ]

    /// Expands a leading tilde to the user home folder.
    static func expand(_ path: String) -> String {
        (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    /// True when the standardised path sits inside an allowed root.
    static func isAllowed(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: expand(path)).standardizedFileURL.path
        return allowedRoots.contains { root in
            standardized == root || standardized.hasPrefix(root + "/")
        }
    }

    /// Validates that a path exists and is inside an allowed root.
    ///
    /// Throws `AutomationError.pathNotAllowed` or
    /// `AutomationError.pathNotFound` so the model and the user both get a
    /// specific reason.
    @discardableResult
    static func validatedURL(for path: String, mustExist: Bool = true) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AutomationError.pathNotFound(path)
        }

        guard isAllowed(trimmed) else {
            throw AutomationError.pathNotAllowed(expand(trimmed))
        }

        let url = URL(fileURLWithPath: expand(trimmed)).standardizedFileURL
        if mustExist, !FileManager.default.fileExists(atPath: url.path) {
            throw AutomationError.pathNotFound(url.path)
        }
        return url
    }

    /// Human readable list of the allowed roots, used in error messages.
    static var describedRoots: String {
        allowedRoots.joined(separator: ", ")
    }
}
