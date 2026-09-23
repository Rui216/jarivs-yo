//
//  DashboardView.swift
//  JARVIS
//
//  The home screen: header, clock, schedule, homework reminders, to-do
//  list, mini calendar, focus timer, Quick Tools, and the system status
//  widget, arranged in two columns that reflow with the window width.
//

import SwiftUI

/// Home screen of the application.
struct DashboardView: View {

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
                DashboardHeader()

                HStack(alignment: .top, spacing: JarvisTheme.Spacing.loose) {
                    VStack(spacing: JarvisTheme.Spacing.loose) {
                        ClockCard()

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: JarvisTheme.Spacing.loose) {
                                HomeworkRemindersCard()
                                MiniCalendarCard()
                            }
                            VStack(spacing: JarvisTheme.Spacing.loose) {
                                HomeworkRemindersCard()
                                MiniCalendarCard()
                            }
                        }

                        FocusTimerCard()
                        QuickToolsRow()
                        SystemStatusCard()
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: JarvisTheme.Spacing.loose) {
                        UpNextCard()
                        TodoCard()
                    }
                    .frame(minWidth: 288, idealWidth: 340, maxWidth: 380, alignment: .top)
                }
            }
            .padding(JarvisTheme.Layout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .task {
            await environment.refreshAll()
        }
    }
}
