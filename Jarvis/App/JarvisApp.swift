//
//  JarvisApp.swift
//  JARVIS
//
//  Application entry point. Creates the SwiftData container, builds the
//  environment (services, stores, view models), and installs the window
//  shell. If the on disk store cannot be opened, the app falls back to
//  an in-memory store and shows the reason instead of refusing to launch.
//

import SwiftUI
import SwiftData
import os

@main
struct JarvisApp: App {

    /// Injected into every view.
    @State private var environment: AppEnvironment

    /// Non nil when the persistent store could not be opened.
    @State private var storeWarning: String?

    init() {
        let result = Self.makeContainer()
        self._environment = State(initialValue: AppEnvironment(modelContainer: result.container))
        self._storeWarning = State(initialValue: result.warning)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(storeWarning: storeWarning)
                .environment(environment)
                .frame(
                    minWidth: JarvisTheme.Layout.minimumWindowWidth,
                    minHeight: JarvisTheme.Layout.minimumWindowHeight
                )
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_460, height: 940)
        .commands {
            JarvisCommands(environment: environment)
        }
    }

    // MARK: - Container

    /// Builds the SwiftData container, falling back to memory on failure.
    private static func makeContainer() -> (container: ModelContainer, warning: String?) {
        let schema = Schema([
            TaskItem.self,
            HomeworkItem.self,
            NoteItem.self,
            CalendarEventItem.self,
            FocusSessionRecord.self,
            ChatMessageRecord.self,
            AppShortcut.self
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return (container, nil)
        } catch {
            Log.app.error("Persistent store unavailable: \(error.localizedDescription, privacy: .public)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
                return (
                    container,
                    "Local storage could not be opened, so this session runs in memory. Data will not be kept after quitting. Details: \(error.localizedDescription)"
                )
            }
            // A container is mandatory for the view tree; a fatal error here
            // means the schema itself is invalid, which is a programming bug.
            fatalError("The SwiftData schema could not be initialised: \(error)")
        }
    }
}
