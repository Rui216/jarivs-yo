//
//  QuickToolsService.swift
//  JARVIS
//
//  Runs the Quick Tools tiles: launching an application, opening a
//  website, or revealing a folder. The same code path serves the
//  dashboard and the Apps screen, and it is also what the assistant uses
//  when it is asked to open one of these shortcuts.
//

import Foundation
import SwiftData

/// Opens Quick Tools shortcuts.
@MainActor
@Observable
final class QuickToolsService {

    /// Last failure, surfaced as a banner on the dashboard.
    private(set) var lastErrorMessage: String?

    /// Name of the shortcut that was opened most recently.
    private(set) var lastOpenedName: String?

    private let launcher = ApplicationLauncher.shared
    private let browser = BrowserAutomation.shared
    private let finder = FinderAutomation.shared

    /// Opens a shortcut, returning nil on success or a message on failure.
    @discardableResult
    func open(_ shortcut: AppShortcut) async -> String? {
        lastErrorMessage = nil
        do {
            switch shortcut.kind {
            case .application:
                let application = try await launcher.launch(matching: shortcut.target)
                lastOpenedName = application.name

            case .url:
                let url = try BrowserAutomation.normalizedURL(from: shortcut.target)
                guard browser.openInDefaultBrowser(url) else {
                    throw AutomationError.applicationLaunchFailed(
                        shortcut.name,
                        reason: "the default browser did not accept the address."
                    )
                }
                lastOpenedName = shortcut.name

            case .folder:
                let url = try finder.openFolder(path: shortcut.target)
                lastOpenedName = url.lastPathComponent
            }
            return nil
        } catch let error as AutomationError {
            lastErrorMessage = error.localizedDescription
            return error.localizedDescription
        } catch {
            lastErrorMessage = error.localizedDescription
            return error.localizedDescription
        }
    }

    /// Inserts the default tiles the first time the app runs.
    ///
    /// Existing rows are left untouched so a user who edited or removed a
    /// tile does not get it back on the next launch.
    func seedDefaultsIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<AppShortcut>())) ?? 0
        guard count == 0 else { return }
        for shortcut in AppShortcut.defaultShortcuts {
            context.insert(shortcut)
        }
        do {
            try context.save()
        } catch {
            Log.services.error("Seeding Quick Tools failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Creates a new shortcut at the end of the list.
    @discardableResult
    func createShortcut(
        in context: ModelContext,
        name: String,
        symbolName: String,
        kind: ShortcutKind,
        target: String,
        tintHex: Int = 0x38D8EE
    ) -> AppShortcut {
        let order = (try? context.fetchCount(FetchDescriptor<AppShortcut>())) ?? 0
        let shortcut = AppShortcut(
            name: name,
            symbolName: symbolName,
            kind: kind,
            target: target,
            tintHex: tintHex,
            sortOrder: order
        )
        context.insert(shortcut)
        try? context.save()
        return shortcut
    }

    /// Deletes a shortcut.
    func delete(_ shortcut: AppShortcut, in context: ModelContext) {
        context.delete(shortcut)
        try? context.save()
    }
}
