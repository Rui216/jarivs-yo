//
//  BrowserAutomation.swift
//  JARVIS
//
//  Opens web addresses, either through the default browser with
//  NSWorkspace or through a specific browser with Apple Events. Chromium
//  family browsers and Safari support scripted tabs; asking for a new
//  window uses each browser's own scripting verb.
//

import Foundation
import AppKit
import os

/// Browsers JARVIS can drive through Apple Events.
enum BrowserTarget: String, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case chrome
    case safari
    case edge
    case brave
    case arc

    var id: String { rawValue }

    /// Name used in the tool parameter and in messages.
    var displayName: String {
        switch self {
        case .systemDefault: return "Default browser"
        case .chrome: return "Google Chrome"
        case .safari: return "Safari"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave Browser"
        case .arc: return "Arc"
        }
    }

    /// AppleScript application name, nil for the default browser.
    var scriptApplicationName: String? {
        switch self {
        case .systemDefault: return nil
        case .chrome: return "Google Chrome"
        case .safari: return "Safari"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave Browser"
        case .arc: return "Arc"
        }
    }

    /// Bundle identifier used to check whether the browser is installed.
    var bundleIdentifier: String? {
        switch self {
        case .systemDefault: return nil
        case .chrome: return "com.google.Chrome"
        case .safari: return "com.apple.Safari"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        case .arc: return "company.thebrowser.Browser"
        }
    }

    /// Resolves a loose name such as "chrome" or "safari" from a tool call.
    static func from(name: String?) -> BrowserTarget {
        guard let name = name?.lowercased(), !name.isEmpty else { return .systemDefault }
        if name.contains("chrome") { return .chrome }
        if name.contains("safari") { return .safari }
        if name.contains("edge") { return .edge }
        if name.contains("brave") { return .brave }
        if name.contains("arc") { return .arc }
        return .systemDefault
    }
}

/// Search engines offered by the web search tool.
enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google
    case duckduckgo
    case bing
    case youtube

    var id: String { rawValue }

    /// Friendly name for messages.
    var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .youtube: return "YouTube"
        }
    }

    /// Builds the query URL for this engine.
    func url(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let base: String
        switch self {
        case .google: base = "https://www.google.com/search?q="
        case .duckduckgo: base = "https://duckduckgo.com/?q="
        case .bing: base = "https://www.bing.com/search?q="
        case .youtube: base = "https://www.youtube.com/results?search_query="
        }
        return URL(string: base + encoded)
    }

    /// Resolves a loose engine name from a tool call.
    static func from(name: String?) -> SearchEngine {
        guard let name = name?.lowercased(), !name.isEmpty else { return .google }
        if name.contains("duck") { return .duckduckgo }
        if name.contains("bing") { return .bing }
        if name.contains("youtube") { return .youtube }
        return .google
    }
}

/// Opens addresses in browsers.
@MainActor
final class BrowserAutomation {

    /// Shared instance used by the automation bridge.
    static let shared = BrowserAutomation()

    private let scripts = AppleScriptRunner.shared
    private let launcher = ApplicationLauncher.shared
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Automation")

    // MARK: - Opening

    /// Normalizes a user supplied address into a URL.
    ///
    /// Bare hosts are upgraded to https, and anything that is not a web or
    /// mail address is refused before it reaches the browser.
    static func normalizedURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AutomationError.invalidURL(rawValue) }

        let candidate: String
        if trimmed.contains("://") || trimmed.hasPrefix("mailto:") {
            candidate = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            candidate = "https://" + trimmed
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            candidate = "https://www.google.com/search?q=" + encoded
        }

        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased() else {
            throw AutomationError.invalidURL(rawValue)
        }
        let allowedSchemes: Set<String> = ["http", "https", "mailto"]
        guard allowedSchemes.contains(scheme) else {
            throw AutomationError.invalidURL(rawValue)
        }
        return url
    }

    /// Opens a URL in the default browser.
    @discardableResult
    func openInDefaultBrowser(_ url: URL) -> Bool {
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            logger.error("Default browser refused \(url.host ?? "address", privacy: .public)")
        }
        return opened
    }

    /// Opens a URL in the requested browser, in a new tab or a new window.
    ///
    /// Chromium browsers and Safari are driven with Apple Events, which is the
    /// only way to place the address in a specific tab or window. Arc does not
    /// publish a scripting dictionary, so it is handed the address through
    /// NSWorkspace instead, which needs no Automation permission at all.
    func open(url: URL, in target: BrowserTarget, newWindow: Bool = false) async throws {
        guard let applicationName = target.scriptApplicationName else {
            guard openInDefaultBrowser(url) else {
                throw AutomationError.applicationLaunchFailed("the default browser", reason: "the system did not accept the address.")
            }
            return
        }

        if let bundle = target.bundleIdentifier, !launcher.isInstalled(bundleIdentifier: bundle) {
            throw AutomationError.unsupportedBrowser(target.displayName)
        }

        if target == .arc {
            try openWithApplication(url: url, bundleIdentifier: target.bundleIdentifier)
            return
        }

        let script = Self.tabScript(url: url, applicationName: applicationName, newWindow: newWindow, target: target)
        _ = try await scripts.run(script: script, timeout: 20)
    }

    /// Opens a URL with a specific application bundle, without Apple Events.
    ///
    /// Used for browsers that do not publish a scripting dictionary.
    private func openWithApplication(url: URL, bundleIdentifier: String?) throws {
        guard let bundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw AutomationError.unsupportedBrowser(bundleIdentifier ?? "the requested browser")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Captured locally so the completion handler never touches the main
        // actor isolated instance.
        let logger = self.logger

        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { application, error in
            if let error {
                logger.error("Opening the address failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("Opened an address in \(application?.bundleIdentifier ?? bundleIdentifier, privacy: .public)")
            }
        }
    }

    /// Runs a web search in the default browser.
    func search(_ query: String, engine: SearchEngine) async throws {
        guard let url = engine.url(for: query) else {
            throw AutomationError.invalidURL(query)
        }
        guard openInDefaultBrowser(url) else {
            throw AutomationError.applicationLaunchFailed(engine.displayName, reason: "the system did not accept the search address.")
        }
    }

    // MARK: - Scripts

    /// Builds the AppleScript that opens a tab or window for one browser.
    private static func tabScript(
        url: URL,
        applicationName: String,
        newWindow: Bool,
        target: BrowserTarget
    ) -> String {
        let escaped = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch target {
        case .systemDefault:
            return "open location \"\(escaped)\""

        case .safari:
            if newWindow {
                return """
                tell application "Safari"
                    activate
                    make new document with properties {URL:"\(escaped)"}
                end tell
                """
            }
            // Prefer a tab in the existing window, and fall back to a document
            // when the installed Safari build does not script tabs.
            return """
            tell application "Safari"
                activate
                if (count of windows) = 0 then
                    make new document
                end if
                try
                    tell front window
                        set current tab to (make new tab with properties {URL:"\(escaped)"})
                    end tell
                on error
                    make new document with properties {URL:"\(escaped)"}
                end try
            end tell
            """

        case .chrome, .edge, .brave:
            if newWindow {
                return """
                tell application "\(applicationName)"
                    activate
                    set newWindow to make new window
                    set URL of active tab of newWindow to "\(escaped)"
                end tell
                """
            }
            // Chromium browsers accept the standard open location handler and
            // scripted tabs. The fallback covers a window that never appeared.
            return """
            tell application "\(applicationName)"
                activate
                if (count of windows) = 0 then
                    make new window
                end if
                try
                    tell front window
                        make new tab with properties {URL:"\(escaped)"}
                        set active tab index to (count of tabs)
                    end tell
                on error
                    make new window
                    set URL of active tab of front window to "\(escaped)"
                end try
            end tell
            """

        case .arc:
            // Arc is handled through NSWorkspace; this branch exists so the
            // switch stays exhaustive if a script is ever requested for it.
            return """
            tell application "\(applicationName)"
                activate
                open location "\(escaped)"
            end tell
            """
        }
    }
}
