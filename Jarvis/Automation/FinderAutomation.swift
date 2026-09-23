//
//  FinderAutomation.swift
//  JARVIS
//
//  Opens files and folders and reveals items in Finder. Every path goes
//  through PathGuard first, so automation can never reach outside the
//  user's own folders.
//

import Foundation
import AppKit
import os

/// A shortcut folder offered by the Files screen.
struct StandardFolder: Identifiable, Sendable, Equatable {
    /// Label shown in the list.
    let name: String
    /// Folder location.
    let url: URL

    var id: String { url.path }
}

/// Opens and reveals file system items.
@MainActor
final class FinderAutomation {

    /// Shared instance used by the automation bridge and the Files screen.
    static let shared = FinderAutomation()

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Automation")

    /// Opens a file, folder, or application with its default handler.
    @discardableResult
    func open(path: String) throws -> URL {
        let url = try PathGuard.validatedURL(for: path)
        guard NSWorkspace.shared.open(url) else {
            throw AutomationError.applicationLaunchFailed(
                url.lastPathComponent,
                reason: "no application on this Mac handles that file type."
            )
        }
        logger.debug("Opened item at \(url.lastPathComponent, privacy: .public)")
        return url
    }

    /// Reveals an item in a new Finder window, selecting it.
    @discardableResult
    func reveal(path: String) throws -> URL {
        let url = try PathGuard.validatedURL(for: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        logger.debug("Revealed item at \(url.lastPathComponent, privacy: .public)")
        return url
    }

    /// Opens a folder in Finder without selecting a child item.
    @discardableResult
    func openFolder(path: String) throws -> URL {
        let url = try PathGuard.validatedURL(for: path)
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDirectory else {
            throw AutomationError.pathNotFound("\(url.path) is not a folder.")
        }
        guard NSWorkspace.shared.open(url) else {
            throw AutomationError.applicationLaunchFailed(url.lastPathComponent, reason: "Finder did not accept the folder.")
        }
        return url
    }

    /// Standard folders offered by the Files screen and Quick Tools.
    ///
    /// Only folders that exist on this machine are returned.
    func standardFolders() -> [StandardFolder] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [StandardFolder] = [
            StandardFolder(name: "Home", url: home),
            StandardFolder(name: "Desktop", url: home.appendingPathComponent("Desktop")),
            StandardFolder(name: "Documents", url: home.appendingPathComponent("Documents")),
            StandardFolder(name: "Downloads", url: home.appendingPathComponent("Downloads")),
            StandardFolder(name: "Applications", url: URL(fileURLWithPath: "/Applications"))
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }
}
