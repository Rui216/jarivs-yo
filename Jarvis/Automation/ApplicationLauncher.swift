//
//  ApplicationLauncher.swift
//  JARVIS
//
//  Launches applications and enumerates what is installed, using
//  NSWorkspace and the standard application directories. This is the
//  backing for the Quick Tools row and for the open_application tool.
//

import Foundation
import AppKit
import os

/// An application discovered on disk.
struct InstalledApplication: Identifiable, Hashable, Sendable {
    /// Bundle identifier, for example com.apple.Safari.
    let bundleIdentifier: String
    /// Display name, for example Safari.
    let name: String
    /// Location of the bundle.
    let url: URL

    var id: String { bundleIdentifier.isEmpty ? url.path : bundleIdentifier }
}

/// Finds and opens installed applications.
@MainActor
final class ApplicationLauncher {

    /// Shared instance used by the dashboard and the automation bridge.
    static let shared = ApplicationLauncher()

    /// How long a directory scan stays valid before it is repeated.
    private static let cacheLifetime: TimeInterval = 300

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Automation")
    private var cachedApplications: [InstalledApplication] = []
    private var cacheDate: Date?

    /// Directories scanned for applications, in priority order.
    private var searchDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications")
        ]
    }

    // MARK: - Discovery

    /// Installed applications, cached for five minutes.
    func installedApplications(forceRefresh: Bool = false) -> [InstalledApplication] {
        if !forceRefresh, let cacheDate, Date().timeIntervalSince(cacheDate) < Self.cacheLifetime {
            return cachedApplications
        }

        var seen = Set<String>()
        var found: [InstalledApplication] = []

        for directory in searchDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                guard let bundle = Bundle(url: entry) else { continue }
                let identifier = bundle.bundleIdentifier ?? ""
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? entry.deletingPathExtension().lastPathComponent

                let key = identifier.isEmpty ? entry.path.lowercased() : identifier
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                found.append(InstalledApplication(
                    bundleIdentifier: identifier,
                    name: name,
                    url: entry
                ))
            }
        }

        cachedApplications = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cacheDate = Date()
        logger.debug("Application scan found \(self.cachedApplications.count, privacy: .public) bundles")
        return cachedApplications
    }

    /// True when an application with the given bundle identifier is installed.
    func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Resolves a user supplied name or bundle identifier to an application.
    ///
    /// Matching order: exact bundle id, exact name, name prefix, then name
    /// substring. Ambiguity resolves to the shortest name, which is normally
    /// the canonical application.
    func findApplication(matching query: String) -> InstalledApplication? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed),
           let bundle = Bundle(url: directURL) {
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? directURL.deletingPathExtension().lastPathComponent
            return InstalledApplication(bundleIdentifier: trimmed, name: name, url: directURL)
        }

        let applications = installedApplications()
        let lowered = trimmed.lowercased()

        if let exact = applications.first(where: { $0.name.lowercased() == lowered }) {
            return exact
        }
        if let prefix = applications
            .filter({ $0.name.lowercased().hasPrefix(lowered) })
            .min(by: { $0.name.count < $1.name.count }) {
            return prefix
        }
        if let directURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.\(trimmed)"),
           let bundle = Bundle(url: directURL) {
            let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? directURL.deletingPathExtension().lastPathComponent
            return InstalledApplication(bundleIdentifier: "com.apple.\(trimmed)", name: name, url: directURL)
        }
        return applications
            .filter { $0.name.lowercased().contains(lowered) }
            .min(by: { $0.name.count < $1.name.count })
    }

    // MARK: - Launching

    /// Launches an application and returns what was opened.
    ///
    /// Throws `AutomationError.applicationNotFound` when nothing matches and
    /// `AutomationError.applicationLaunchFailed` when the launch is rejected.
    @discardableResult
    func launch(matching query: String) async throws -> InstalledApplication {
        guard let application = findApplication(matching: query) else {
            throw AutomationError.applicationNotFound(query)
        }
        try await launch(application)
        return application
    }

    /// Launches a specific application bundle.
    func launch(_ application: InstalledApplication) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false

        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: application.url,
                configuration: configuration
            )
            logger.debug("Launched \(application.bundleIdentifier, privacy: .public)")
        } catch {
            logger.error("Launch failed for \(application.bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw AutomationError.applicationLaunchFailed(
                application.name,
                reason: error.localizedDescription
            )
        }
    }
}
