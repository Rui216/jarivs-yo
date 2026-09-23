//
//  FilesView.swift
//  JARVIS
//
//  Folder browser: shortcuts to the standard folders, a breadcrumb path,
//  a listing with sizes and dates, and a Spotlight backed search. Opening
//  or revealing an item uses the same guarded automation code paths as
//  the assistant.
//

import SwiftUI
import AppKit

/// File browser screen.
struct FilesView: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var currentFolder: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [FileEntry] = []
    @State private var searchText = ""
    @State private var searchResults: [FileSearchResult] = []
    @State private var showsHiddenFiles = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.loose) {
            folderRail
            listing
                .frame(maxWidth: .infinity)
        }
        .padding(JarvisTheme.Layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            load(folder: currentFolder)
        }
    }

    // MARK: - Rail

    private var folderRail: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            Text("Files")
                .font(JarvisTheme.Typography.display(24))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(FinderAutomation.shared.standardFolders()) { folder in
                    Button {
                        searchText = ""
                        searchResults = []
                        load(folder: folder.url)
                    } label: {
                        HStack(spacing: JarvisTheme.Spacing.tight) {
                            Image(systemName: "folder")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(JarvisTheme.Palette.accent)
                            Text(folder.name)
                                .font(JarvisTheme.Typography.body(12))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(JarvisTheme.Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Calendar.current.isDateInToday(Date()) && currentFolder.path == folder.url.path
                                      ? JarvisTheme.Palette.accent.opacity(0.14)
                                      : JarvisTheme.Palette.canvas.opacity(0.4))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(JarvisTheme.Spacing.regular)
            .jarvisCard()

            Toggle("Show hidden files", isOn: $showsHiddenFiles)
                .toggleStyle(.switch)
                .tint(JarvisTheme.Palette.accent)
                .font(JarvisTheme.Typography.caption(11))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
                .onChange(of: showsHiddenFiles) { _, _ in
                    load(folder: currentFolder)
                }

            Text("JARVIS only browses your home folder, /tmp, /Applications, and /Volumes. It never deletes or moves files.")
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(JarvisTheme.Spacing.regular)
                .jarvisCard()

            Spacer(minLength: 0)
        }
        .frame(width: 240)
    }

    // MARK: - Listing

    private var listing: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            toolbar
            breadcrumb

            if let errorMessage {
                Text(errorMessage)
                    .font(JarvisTheme.Typography.caption(11))
                    .foregroundStyle(JarvisTheme.Palette.danger)
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(searchText.isEmpty ? entries.map(\.url.path) : searchResults.map(\.path), id: \.self) { path in
                        row(for: path)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(JarvisTheme.Spacing.loose)
        .jarvisCard()
    }

    private var toolbar: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                TextField("Search the home folder", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(JarvisTheme.Typography.body(12))
                    .onSubmit(runSearch)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(JarvisTheme.Palette.canvas.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
            )

            Button("Search", action: runSearch)
                .buttonStyle(.jarvisSecondary)

            Button {
                load(folder: currentFolder)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.jarvisSecondary)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button {
                let parent = currentFolder.deletingLastPathComponent()
                if PathGuard.isAllowed(parent.path) {
                    load(folder: parent)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(JarvisTheme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Go to the parent folder")

            Text(currentFolder.path)
                .font(JarvisTheme.Typography.caption(11))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 0)

            Text("\(displayedCount) item(s)")
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
        }
    }

    private func row(for path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        return HStack(spacing: JarvisTheme.Spacing.regular) {
            Image(systemName: isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isDirectory ? JarvisTheme.Palette.accent : JarvisTheme.Palette.textSecondary)
                .frame(width: 20)

            Text(url.lastPathComponent)
                .font(JarvisTheme.Typography.body(12))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(isDirectory ? "Folder" : SystemMetrics.formatBytes(Int64(size), style: .decimal))
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .frame(width: 78, alignment: .trailing)

            Text(JarvisTimeFormat.shortDate(modified))
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .frame(width: 62, alignment: .trailing)

            HStack(spacing: 6) {
                Button {
                    if isDirectory {
                        load(folder: url)
                    } else {
                        do {
                            try FinderAutomation.shared.open(path: path)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Image(systemName: isDirectory ? "arrow.right.circle" : "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(JarvisTheme.Palette.accent)
                }
                .buttonStyle(.plain)
                .help(isDirectory ? "Open the folder" : "Open the file")

                Button {
                    do {
                        try FinderAutomation.shared.reveal(path: path)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
            .frame(width: 54)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(JarvisTheme.Palette.canvas.opacity(0.35))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isDirectory {
                load(folder: url)
            }
        }
    }

    // MARK: - Data

    private var displayedCount: Int {
        searchText.isEmpty ? entries.count : searchResults.count
    }

    private func load(folder: URL) {
        errorMessage = nil
        guard environment.fileSearch.canBrowse(folder) else {
            errorMessage = "That folder is outside the locations JARVIS may browse."
            return
        }
        do {
            entries = try environment.fileSearch.listDirectory(at: folder, showHidden: showsHiddenFiles)
            currentFolder = folder
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        Task {
            do {
                searchResults = try await environment.fileSearch.search(query: query, limit: 40)
                errorMessage = searchResults.isEmpty ? "No files matched \(query)." : nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
