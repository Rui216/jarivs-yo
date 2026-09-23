//
//  FileSearchService.swift
//  JARVIS
//
//  File system browsing for the Files screen and the assistant file
//  search tool. Spotlight is queried first because it is instant on a
//  normal Mac; a bounded directory walk is used as a fallback when the
//  index is unavailable. Reads never leave the user's own folders.
//

import Foundation
import os

/// One file found by a search.
struct FileSearchResult: Identifiable, Sendable, Equatable {
    /// Absolute path of the match.
    let path: String
    /// Size in bytes, zero for folders.
    let sizeBytes: Int64
    /// Last modification date.
    let modifiedAt: Date

    var id: String { path }

    /// File name without the directory part.
    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

/// One entry in a directory listing.
struct FileEntry: Identifiable, Sendable, Equatable {
    /// Location of the entry.
    let url: URL
    /// Whether the entry is a folder.
    let isDirectory: Bool
    /// Size in bytes.
    let sizeBytes: Int64
    /// Last modification date.
    let modifiedAt: Date

    var id: String { url.path }

    /// File name.
    var name: String { url.lastPathComponent }

    /// Formatted size for the list.
    var sizeDescription: String {
        isDirectory ? "Folder" : SystemMetrics.formatBytes(sizeBytes, style: .decimal)
    }
}

/// Searches and lists files inside the folders JARVIS may read.
@MainActor
final class FileSearchService {

    /// Largest number of entries a fallback walk inspects.
    private static let maximumWalkEntries = 20_000

    private let homeDirectory: URL
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Files")

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    // MARK: - Search

    /// Searches file names under the home folder.
    ///
    /// Throws `AutomationError.commandNotPermitted` when the query contains
    /// characters that would make the Spotlight predicate ambiguous.
    func search(query: String, limit: Int = 15) async throws -> [FileSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let sanitized = Self.sanitize(query: trimmed)
        guard !sanitized.isEmpty else {
            throw AutomationError.commandNotPermitted(reason: "the search text contained only unusable characters.")
        }

        let results = await spotlightSearch(query: sanitized, limit: limit)
        if !results.isEmpty {
            return results
        }
        return walkSearch(query: sanitized.lowercased(), limit: limit)
    }

    /// Runs `mdfind` scoped to the home folder.
    private func spotlightSearch(query: String, limit: Int) async -> [FileSearchResult] {
        let predicate = "kMDItemFSName == \"*\(query)*\"c"
        let result: ProcessExecutionResult
        do {
            result = try await ProcessExecutor.run(
                executable: URL(fileURLWithPath: "/usr/bin/mdfind"),
                arguments: ["-onlyin", homeDirectory.path, predicate],
                timeout: 15
            )
        } catch {
            logger.debug("Spotlight search unavailable, falling back to a directory walk")
            return []
        }

        guard result.exitCode == 0 else { return [] }
        let paths = result.trimmedOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .prefix(limit)

        return paths.compactMap { path in
            guard PathGuard.isAllowed(path) else { return nil }
            return Self.makeResult(path: path)
        }
    }

    /// Bounded directory walk used when Spotlight returns nothing.
    private func walkSearch(query: String, limit: Int) -> [FileSearchResult] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: homeDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [FileSearchResult] = []
        var inspected = 0

        for case let url as URL in enumerator {
            inspected += 1
            if inspected > Self.maximumWalkEntries { break }
            guard url.lastPathComponent.lowercased().contains(query) else { continue }
            guard let result = Self.makeResult(path: url.path) else { continue }
            results.append(result)
            if results.count >= limit { break }
        }
        return results
    }

    /// Reads metadata for one path.
    private static func makeResult(path: String) -> FileSearchResult? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileSearchResult(
            path: path,
            sizeBytes: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate ?? Date()
        )
    }

    /// Removes characters that would break the Spotlight predicate.
    static func sanitize(query: String) -> String {
        let banned: Set<Character> = ["\"", "\\", "\n", "\r", "\t", "*", "$", ";", "&", "|", "`"]
        return String(query.filter { !banned.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Browsing

    /// Lists a directory, folders first then files, each alphabetically.
    func listDirectory(at url: URL, showHidden: Bool = false) throws -> [FileEntry] {
        let validated = try PathGuard.validatedURL(for: url.path)
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]

        let contents = try FileManager.default.contentsOfDirectory(
            at: validated,
            includingPropertiesForKeys: keys,
            options: options
        )

        let entries = contents.compactMap { item -> FileEntry? in
            let values = try? item.resourceValues(forKeys: Set(keys))
            return FileEntry(
                url: item,
                isDirectory: values?.isDirectory ?? false,
                sizeBytes: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate ?? Date()
            )
        }

        return entries.sorted { left, right in
            if left.isDirectory != right.isDirectory {
                return left.isDirectory
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    /// Counts items and total size for a folder, bounded for speed.
    func folderSummary(for url: URL, maximumEntries: Int = 5_000) -> (items: Int, sizeBytes: Int64) {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return (0, 0)
        }

        var count = 0
        var size: Int64 = 0
        for case let item as URL in enumerator {
            count += 1
            if count > maximumEntries { break }
            if let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true {
                size += Int64(values.fileSize ?? 0)
            }
        }
        return (count, size)
    }

    /// True when a folder may be browsed.
    func canBrowse(_ url: URL) -> Bool {
        PathGuard.isAllowed(url.path)
    }
}
