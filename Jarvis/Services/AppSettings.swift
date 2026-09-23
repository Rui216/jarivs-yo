//
//  AppSettings.swift
//  JARVIS
//
//  Non secret preferences. API keys are deliberately absent from this
//  type: they live in the keychain and are reached through APIKeyStore.
//  Anything stored here is ordinary preference data such as the user
//  name, the weather location, or the selected model.
//

import Foundation
import SwiftUI

/// User preferences backed by UserDefaults.
///
/// Mutations go through `assign` or `binding` so a change is always written
/// back to disk, while reads stay observable for SwiftUI.
@MainActor
@Observable
final class AppSettings {

    // MARK: - Keys

    private enum Key {
        static let userName = "settings.userName"
        static let temperatureUnit = "settings.temperatureUnit"
        static let weatherLocationName = "settings.weather.locationName"
        static let weatherLatitude = "settings.weather.latitude"
        static let weatherLongitude = "settings.weather.longitude"
        static let confirmAppleScript = "settings.confirmAppleScript"
        static let selectedProvider = "settings.ai.selectedProvider"
        static let modelSelections = "settings.ai.modelSelections"
        static let enabledTools = "settings.ai.enabledTools"
        static let focusPresetMinutes = "settings.focus.presetMinutes"
        static let showsCompletedTasks = "settings.tasks.showsCompleted"
        static let completedSetup = "settings.completedSetup"
    }

    private let defaults: UserDefaults

    // MARK: - Stored preferences

    /// Name the assistant uses in greetings.
    var userName: String
    /// Temperature unit for the weather widget.
    var temperatureUnit: TemperatureUnit
    /// Display name of the configured weather location.
    var weatherLocationName: String
    /// Latitude of the configured location, nil when unset.
    var weatherLatitude: Double?
    /// Longitude of the configured location, nil when unset.
    var weatherLongitude: Double?
    /// Whether AppleScript runs must be approved by the user first.
    var confirmAppleScript: Bool
    /// Provider that powers the assistant.
    var selectedProvider: AIProviderID
    /// Selected model per provider, keyed by the provider raw value.
    var modelSelections: [String: String]
    /// Tool names the assistant is allowed to use.
    var enabledToolNames: Set<String>
    /// Duration in minutes of the default focus timer preset.
    var focusPresetMinutes: Int
    /// Whether completed to-dos stay visible on the dashboard.
    var showsCompletedTasks: Bool
    /// Whether the first run setup has been acknowledged.
    var completedSetup: Bool

    // MARK: - Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedName = defaults.string(forKey: Key.userName) ?? ""
        self.userName = storedName.isEmpty ? NSFullUserName() : storedName

        self.temperatureUnit = defaults.string(forKey: Key.temperatureUnit)
            .flatMap(TemperatureUnit.init(rawValue:)) ?? .celsius

        self.weatherLocationName = defaults.string(forKey: Key.weatherLocationName) ?? ""
        let latitude = defaults.object(forKey: Key.weatherLatitude) as? Double
        let longitude = defaults.object(forKey: Key.weatherLongitude) as? Double
        self.weatherLatitude = latitude
        self.weatherLongitude = longitude

        self.confirmAppleScript = defaults.object(forKey: Key.confirmAppleScript) as? Bool ?? true

        self.selectedProvider = defaults.string(forKey: Key.selectedProvider)
            .flatMap(AIProviderID.init(rawValue:)) ?? .anthropic

        self.modelSelections = defaults.dictionary(forKey: Key.modelSelections) as? [String: String] ?? [:]

        if let storedTools = defaults.array(forKey: Key.enabledTools) as? [String], !storedTools.isEmpty {
            self.enabledToolNames = Set(storedTools)
        } else {
            self.enabledToolNames = AssistantToolCatalog.allNames
        }

        let storedPreset = defaults.integer(forKey: Key.focusPresetMinutes)
        self.focusPresetMinutes = storedPreset == 0 ? FocusPreset.short.minutes : storedPreset

        self.showsCompletedTasks = defaults.object(forKey: Key.showsCompletedTasks) as? Bool ?? false
        self.completedSetup = defaults.bool(forKey: Key.completedSetup)
    }

    // MARK: - Writing

    /// Writes every preference back to UserDefaults.
    func persist() {
        defaults.set(userName, forKey: Key.userName)
        defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit)
        defaults.set(weatherLocationName, forKey: Key.weatherLocationName)
        defaults.set(weatherLatitude, forKey: Key.weatherLatitude)
        defaults.set(weatherLongitude, forKey: Key.weatherLongitude)
        defaults.set(confirmAppleScript, forKey: Key.confirmAppleScript)
        defaults.set(selectedProvider.rawValue, forKey: Key.selectedProvider)
        defaults.set(modelSelections, forKey: Key.modelSelections)
        defaults.set(Array(enabledToolNames), forKey: Key.enabledTools)
        defaults.set(focusPresetMinutes, forKey: Key.focusPresetMinutes)
        defaults.set(showsCompletedTasks, forKey: Key.showsCompletedTasks)
        defaults.set(completedSetup, forKey: Key.completedSetup)
    }

    /// Assigns a value and persists it in one step.
    func assign<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>, _ value: Value) {
        self[keyPath: keyPath] = value
        persist()
    }

    /// Binding that persists on every change, for use in settings forms.
    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { newValue in
                self[keyPath: keyPath] = newValue
                self.persist()
            }
        )
    }

    // MARK: - Models

    /// Selected model for a provider, falling back to its default.
    func model(for provider: AIProviderID) -> String {
        let stored = modelSelections[provider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return provider.defaultModel
    }

    /// Stores the selected model for a provider.
    func setModel(_ model: String, for provider: AIProviderID) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            modelSelections.removeValue(forKey: provider.rawValue)
        } else {
            modelSelections[provider.rawValue] = trimmed
        }
        persist()
    }

    // MARK: - Tools

    /// True when the assistant may use a tool.
    func isToolEnabled(_ name: String) -> Bool {
        enabledToolNames.contains(name)
    }

    /// Enables or disables one tool.
    func setTool(_ name: String, enabled: Bool) {
        if enabled {
            enabledToolNames.insert(name)
        } else {
            enabledToolNames.remove(name)
        }
        persist()
    }

    /// Tool schemas for the enabled tools, in catalog order.
    var enabledToolSchemas: [AssistantToolSchema] {
        AssistantToolCatalog.schemas(for: enabledToolNames)
    }

    // MARK: - Weather

    /// True when a location has been configured for the weather widget.
    var hasWeatherLocation: Bool {
        weatherLatitude != nil && weatherLongitude != nil
    }

    /// Stores a resolved location.
    func setWeatherLocation(name: String, latitude: Double, longitude: Double) {
        weatherLocationName = name
        weatherLatitude = latitude
        weatherLongitude = longitude
        persist()
    }

    /// Clears the configured location.
    func clearWeatherLocation() {
        weatherLocationName = ""
        weatherLatitude = nil
        weatherLongitude = nil
        persist()
    }
}
