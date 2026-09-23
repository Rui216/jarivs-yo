//
//  ContentView.swift
//  JARVIS
//
//  Window shell: sidebar on the left, the selected screen in the middle,
//  and the assistant column on the right. A confirmation sheet and the
//  first run setup are presented from here so no screen has to duplicate
//  that wiring.
//

import SwiftUI
import AppKit

/// Root view of the application.
struct ContentView: View {

    /// Non nil when local storage fell back to memory.
    let storeWarning: String?

    @Environment(AppEnvironment.self) private var environment
    @State private var showsSetup = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()

            ZStack {
                JarvisTheme.canvasGradient
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsAssistantColumn {
                        Divider()
                            .overlay(JarvisTheme.Palette.stroke)
                        AssistantColumn()
                            .frame(width: JarvisTheme.Layout.assistantColumnWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .background(JarvisTheme.Palette.canvas)
        .overlay(alignment: .top) {
            if let storeWarning {
                StorageWarningBanner(message: storeWarning)
            }
        }
        .overlay {
            ConfirmationOverlay()
        }
        .sheet(isPresented: $showsSetup) {
            SetupSheet(isPresented: $showsSetup)
                .environment(environment)
        }
        .onAppear {
            environment.start()
            if !environment.settings.completedSetup {
                showsSetup = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            environment.stop()
        }
        .animation(.easeInOut(duration: 0.18), value: showsAssistantColumn)
    }

    // MARK: - Detail

    /// The screen selected in the sidebar.
    @ViewBuilder
    private var detail: some View {
        switch environment.appState.destination {
        case .home:
            DashboardView()
        case .tasks:
            TasksView()
        case .calendar:
            CalendarScreenView()
        case .homework:
            HomeworkView()
        case .files:
            FilesView()
        case .apps:
            AppsView()
        case .settings:
            SettingsView()
        }
    }

    /// The assistant stays available everywhere except Settings, where the
    /// forms need the full width.
    private var showsAssistantColumn: Bool {
        environment.appState.isAssistantVisible && environment.appState.destination != .settings
    }
}

// MARK: - Supporting views

/// Banner shown when the persistent store is unavailable.
private struct StorageWarningBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(JarvisTheme.Palette.warning)
            Text(message)
                .font(JarvisTheme.Typography.caption(11))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JarvisTheme.Spacing.regular)
        .padding(.vertical, JarvisTheme.Spacing.tight)
        .background(JarvisTheme.Palette.warning.opacity(0.14))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JarvisTheme.Palette.warning.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.horizontal, JarvisTheme.Spacing.loose)
        .padding(.top, JarvisTheme.Spacing.tight)
    }
}
