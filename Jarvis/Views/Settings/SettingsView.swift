//
//  SettingsView.swift
//  JARVIS
//
//  Settings container: general preferences, provider keys, permissions,
//  assistant tools, Quick Tools, and application information.
//

import SwiftUI

/// Settings screen with tabbed sections.
struct SettingsView: View {

    @Environment(AppEnvironment.self) private var environment

    /// Sections of the settings screen.
    private enum Tab: String, CaseIterable, Identifiable {
        case general
        case providers
        case permissions
        case tools
        case quickTools
        case about

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .general: return "General"
            case .providers: return "AI Providers"
            case .permissions: return "Permissions"
            case .tools: return "Assistant Tools"
            case .quickTools: return "Quick Tools"
            case .about: return "About"
            }
        }

        var symbolName: String {
            switch self {
            case .general: return "gearshape"
            case .providers: return "key"
            case .permissions: return "lock.shield"
            case .tools: return "wrench.and.screwdriver"
            case .quickTools: return "bolt"
            case .about: return "info.circle"
            }
        }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
            Text("Settings")
                .font(JarvisTheme.Typography.display(26))
                .foregroundStyle(JarvisTheme.Palette.textPrimary)

            HStack(spacing: 6) {
                ForEach(Tab.allCases) { option in
                    Button {
                        tab = option
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.symbolName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(option.displayName)
                                .font(JarvisTheme.Typography.caption(11))
                        }
                        .foregroundStyle(tab == option ? JarvisTheme.Palette.canvas : JarvisTheme.Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(tab == option
                                      ? AnyShapeStyle(JarvisTheme.accentGradient)
                                      : AnyShapeStyle(JarvisTheme.Palette.canvas.opacity(0.5)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    tab == option ? Color.clear : JarvisTheme.Palette.stroke,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
                    switch tab {
                    case .general:
                        GeneralSettingsSection()
                    case .providers:
                        AIProvidersSettingsView()
                    case .permissions:
                        PermissionsSettingsView()
                    case .tools:
                        AssistantToolsSettingsView()
                    case .quickTools:
                        QuickToolsSettingsSection()
                    case .about:
                        AboutSettingsSection()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, JarvisTheme.Spacing.section)
            }
        }
        .padding(JarvisTheme.Layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - General

/// Name, units, weather location, and interface preferences.
struct GeneralSettingsSection: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var locationQuery = ""
    @State private var locationStatus: String?
    @State private var isResolvingLocation = false

    var body: some View {
        @Bindable var settings = environment.settings
        @Bindable var appState = environment.appState

        return VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
            JarvisCard(title: "Profile", symbolName: "person") {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
                    SectionLabel(text: "Name used in greetings")
                    TextField("Name", text: settings.binding(\.userName))
                        .jarvisField()
                    Text("The assistant addresses you by this name and it appears in the dashboard greeting.")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }
            }

            JarvisCard(title: "Weather", symbolName: "cloud.sun") {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                    Picker("Temperature unit", selection: settings.binding(\.temperatureUnit)) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit == .celsius ? "Celsius" : "Fahrenheit").tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)

                    HStack(spacing: JarvisTheme.Spacing.tight) {
                        TextField("City name", text: $locationQuery)
                            .jarvisField()
                            .onSubmit { resolveLocationByName() }

                        Button(isResolvingLocation ? "Looking up..." : "Set location") {
                            resolveLocationByName()
                        }
                        .buttonStyle(.jarvisSecondary)
                        .disabled(isResolvingLocation || locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Use my current location") {
                            resolveLocationByIP()
                        }
                        .buttonStyle(.jarvisSecondary)
                        .disabled(isResolvingLocation)
                    }

                    HStack(spacing: 6) {
                        StatusChip(
                            text: settings.hasWeatherLocation ? settings.weatherLocationName : "No location set",
                            symbolName: settings.hasWeatherLocation ? "mappin" : "mappin.slash",
                            tint: settings.hasWeatherLocation ? JarvisTheme.Palette.success : JarvisTheme.Palette.warning
                        )
                        if settings.hasWeatherLocation {
                            Button("Clear") {
                                settings.clearWeatherLocation()
                                locationStatus = "Weather location cleared."
                            }
                            .buttonStyle(.plain)
                            .font(JarvisTheme.Typography.caption(10))
                            .foregroundStyle(JarvisTheme.Palette.danger)
                        }
                    }

                    Text("Weather comes from Open-Meteo and needs no account. The current location option sends your public address to ipapi.co once, which is the only way to find your city without asking you to type it.")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let locationStatus {
                        Text(locationStatus)
                            .font(JarvisTheme.Typography.caption(10))
                            .foregroundStyle(JarvisTheme.Palette.textSecondary)
                    }
                }
            }

            JarvisCard(title: "Interface", symbolName: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                    Picker("Assistant panel", selection: $appState.isAssistantVisible) {
                        Text("Shown").tag(true)
                        Text("Hidden").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    Picker("Default focus preset", selection: settings.binding(\.focusPresetMinutes)) {
                        ForEach(FocusPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset.minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)

                    Toggle("Keep completed to-dos on the dashboard", isOn: settings.binding(\.showsCompletedTasks))
                        .toggleStyle(.switch)
                        .tint(JarvisTheme.Palette.accent)

                    Toggle("Ask before running AppleScript", isOn: settings.binding(\.confirmAppleScript))
                        .toggleStyle(.switch)
                        .tint(JarvisTheme.Palette.accent)

                    Text("Terminal commands always require your approval, regardless of this setting.")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }
            }
        }
    }

    private func resolveLocationByName() {
        let query = locationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isResolvingLocation = true
        locationStatus = nil

        Task {
            defer { isResolvingLocation = false }
            do {
                guard let place = try await environment.weather.geocode(place: query) else {
                    locationStatus = "No match for \(query)."
                    return
                }
                environment.settings.setWeatherLocation(
                    name: place.name,
                    latitude: place.latitude,
                    longitude: place.longitude
                )
                await environment.weather.refresh(settings: environment.settings, force: true)
                locationStatus = "Weather location set to \(place.name)."
            } catch {
                locationStatus = error.localizedDescription
            }
        }
    }

    private func resolveLocationByIP() {
        isResolvingLocation = true
        locationStatus = nil

        Task {
            defer { isResolvingLocation = false }
            do {
                guard let place = try await environment.weather.resolveLocationFromIP() else {
                    locationStatus = "The location service did not return a city."
                    return
                }
                environment.settings.setWeatherLocation(
                    name: place.name,
                    latitude: place.latitude,
                    longitude: place.longitude
                )
                await environment.weather.refresh(settings: environment.settings, force: true)
                locationStatus = "Weather location set to \(place.name)."
            } catch {
                locationStatus = error.localizedDescription
            }
        }
    }
}

// MARK: - About

/// Version information and data locations.
struct AboutSettingsSection: View {

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        JarvisCard(title: "About JARVIS", symbolName: "info.circle") {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
                infoRow("Version", appVersion)
                infoRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                infoRow("Data", "Stored locally with SwiftData in Application Support")
                infoRow("Secrets", "API keys are held in the macOS keychain")
                infoRow("Weather", "Open-Meteo, no account required")
                infoRow("Assistant", "\(environment.settings.selectedProvider.displayName), model \(environment.settings.model(for: environment.settings.selectedProvider))")

                Divider().overlay(JarvisTheme.Palette.stroke).padding(.vertical, 4)

                Text("JARVIS never deletes files, never changes system settings, and never runs a terminal command without showing you the exact command first.")
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.regular) {
            Text(label)
                .font(JarvisTheme.Typography.caption(11))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(JarvisTheme.Typography.body(12))
                .foregroundStyle(JarvisTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
