//
//  JarvisCommands.swift
//  JARVIS
//
//  Menu bar additions: navigation shortcuts, assistant panel toggle, and
//  refresh commands. Keeping them here means the shell views do not have
//  to know about menu wiring.
//

import SwiftUI

/// Menu bar commands for the application.
struct JarvisCommands: Commands {

    /// Environment providing navigation and data services.
    let environment: AppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                environment.appState.destination = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Navigate") {
            ForEach(SidebarDestination.allCases) { destination in
                Button(destination.displayName) {
                    environment.appState.destination = destination
                }
                .keyboardShortcut(KeyEquivalent(destination.shortcutKey), modifiers: .command)
            }
        }

        CommandMenu("Assistant") {
            Button("Toggle Assistant Panel") {
                environment.appState.isAssistantVisible.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Clear Conversation") {
                environment.chat.clearConversation()
            }

            Divider()

            Button("Check Automation Permission") {
                Task {
                    await environment.probeAutomationPermission()
                }
            }
        }

        CommandMenu("Dashboard") {
            Button("Refresh Calendar and Weather") {
                Task {
                    await environment.refreshAll()
                }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button(environment.focusTimer.isRunning ? "Pause Focus Timer" : "Start Focus Timer") {
                environment.focusTimer.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }
}
