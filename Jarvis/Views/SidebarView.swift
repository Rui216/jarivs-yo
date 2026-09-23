//
//  SidebarView.swift
//  JARVIS
//
//  Left navigation rail: the JARVIS mark, the seven destinations, and a
//  compact status footer. Icons only when collapsed, icon plus label
//  otherwise.
//

import SwiftUI
import AppKit

/// Left navigation rail.
struct SidebarView: View {

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var appState = environment.appState

        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
            brand

            VStack(spacing: 6) {
                ForEach(SidebarDestination.allCases) { destination in
                    SidebarItem(
                        destination: destination,
                        isSelected: appState.destination == destination,
                        isCollapsed: appState.isSidebarCollapsed
                    ) {
                        appState.destination = destination
                    }
                }
            }

            Spacer(minLength: JarvisTheme.Spacing.regular)

            if !appState.isSidebarCollapsed {
                sidebarFooter
            }

            collapseButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, JarvisTheme.Spacing.loose)
        .frame(width: appState.isSidebarCollapsed
               ? JarvisTheme.Layout.sidebarCollapsedWidth
               : JarvisTheme.Layout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(JarvisTheme.Palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(JarvisTheme.Palette.stroke)
                .frame(width: 1)
        }
    }

    // MARK: - Sections

    private var brand: some View {
        HStack(spacing: JarvisTheme.Spacing.tight) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(JarvisTheme.accentGradient)
                    .frame(width: 32, height: 32)
                    .jarvisGlow(radius: 12, opacity: 0.45)
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JarvisTheme.Palette.canvas)
            }

            if !environment.appState.isSidebarCollapsed {
                VStack(alignment: .leading, spacing: 0) {
                    Text("JARVIS")
                        .font(JarvisTheme.Typography.title(16))
                        .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    Text("Personal dashboard")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
            StatusDot(
                color: environment.monitor.metrics.processorLevel.tint,
                size: 7
            )
            Text(systemLine)
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text(assistantLine)
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(
                    environment.apiKeys.hasKey(for: environment.settings.selectedProvider)
                        ? JarvisTheme.Palette.textTertiary
                        : JarvisTheme.Palette.warning
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .fill(JarvisTheme.Palette.canvas.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control, style: .continuous)
                .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
        )
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                environment.appState.isSidebarCollapsed.toggle()
            }
        } label: {
            HStack(spacing: JarvisTheme.Spacing.tight) {
                Image(systemName: environment.appState.isSidebarCollapsed
                      ? "chevron.right.circle"
                      : "chevron.left.circle")
                    .font(.system(size: 13, weight: .semibold))
                if !environment.appState.isSidebarCollapsed {
                    Text("Collapse")
                        .font(JarvisTheme.Typography.caption(11))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(JarvisTheme.Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Collapse or expand the sidebar")
    }

    // MARK: - Text

    private var systemLine: String {
        let metrics = environment.monitor.metrics
        let cpu = Int((metrics.processorUsage * 100).rounded())
        let memory = Int((metrics.memoryFraction * 100).rounded())
        return "System \(cpu)% CPU, \(memory)% memory"
    }

    private var assistantLine: String {
        let provider = environment.settings.selectedProvider
        if environment.apiKeys.hasKey(for: provider) {
            return "\(provider.shortName) connected"
        }
        return "No API key for \(provider.shortName)"
    }
}

/// One row in the sidebar.
private struct SidebarItem: View {
    let destination: SidebarDestination
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: destination.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                if !isCollapsed {
                    Text(destination.displayName)
                        .font(JarvisTheme.Typography.headline(13))
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isSelected ? JarvisTheme.Palette.canvas : JarvisTheme.Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.sidebarItem, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(JarvisTheme.accentGradient) : AnyShapeStyle(Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.sidebarItem, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : JarvisTheme.Palette.stroke.opacity(0.7),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(destination.summary)
    }
}
