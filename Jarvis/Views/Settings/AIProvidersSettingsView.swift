//
//  AIProvidersSettingsView.swift
//  JARVIS
//
//  Provider credentials and model selection. Keys are written straight to
//  the keychain through APIKeyStore: they are never placed in
//  UserDefaults, a plist, the source tree, or a log line, and the only
//  place they are read back is the request builder.
//

import SwiftUI
import AppKit

/// API key and model configuration for every provider.
struct AIProvidersSettingsView: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var keyDrafts: [AIProviderID: String] = [:]
    @State private var modelDrafts: [AIProviderID: String] = [:]
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        @Bindable var settings = environment.settings

        return VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
            JarvisCard(title: "Active assistant", symbolName: "sparkles") {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                    Picker("Provider", selection: settings.binding(\.selectedProvider)) {
                        ForEach(AIProviderID.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 320)

                    HStack(spacing: JarvisTheme.Spacing.tight) {
                        StatusChip(
                            text: environment.apiKeys.hasKey(for: settings.selectedProvider)
                                ? "Key stored: \(environment.apiKeys.maskedKey(for: settings.selectedProvider) ?? "")"
                                : "No key stored",
                            symbolName: environment.apiKeys.hasKey(for: settings.selectedProvider) ? "checkmark" : "exclamationmark.triangle",
                            tint: environment.apiKeys.hasKey(for: settings.selectedProvider)
                                ? JarvisTheme.Palette.success
                                : JarvisTheme.Palette.warning
                        )
                        Text("Model \(settings.model(for: settings.selectedProvider))")
                            .font(JarvisTheme.Typography.caption(11))
                            .foregroundStyle(JarvisTheme.Palette.textSecondary)
                    }

                    Text("Keys are stored in the macOS keychain under the service bundle identifier. They are read only when a request is sent to the provider you selected, and they never appear in logs or in the source tree.")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(JarvisTheme.Typography.caption(11))
                            .foregroundStyle(statusIsError ? JarvisTheme.Palette.danger : JarvisTheme.Palette.success)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(AIProviderID.allCases) { provider in
                providerCard(provider)
            }
        }
        .onAppear {
            environment.apiKeys.refresh()
        }
    }

    // MARK: - Provider card

    private func providerCard(_ provider: AIProviderID) -> some View {
        let hasKey = environment.apiKeys.hasKey(for: provider)
        let currentModel = environment.settings.model(for: provider)

        return JarvisCard(
            title: provider.displayName,
            symbolName: provider == environment.settings.selectedProvider ? "checkmark.seal" : "key",
            isHighlighted: provider == environment.settings.selectedProvider
        ) {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                HStack(spacing: JarvisTheme.Spacing.tight) {
                    StatusChip(
                        text: hasKey ? "Key stored" : "No key",
                        symbolName: hasKey ? "lock.fill" : "lock.open",
                        tint: hasKey ? JarvisTheme.Palette.success : JarvisTheme.Palette.textTertiary
                    )
                    if let masked = environment.apiKeys.maskedKey(for: provider) {
                        Text(masked)
                            .font(JarvisTheme.Typography.mono(11))
                            .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if let console = provider.consoleURL {
                        Button("Open the key page") {
                            NSWorkspace.shared.open(console)
                        }
                        .buttonStyle(.jarvisSecondary)
                    }
                }

                HStack(spacing: JarvisTheme.Spacing.tight) {
                    SecureField(provider.keyPlaceholder, text: draftBinding(for: provider))
                        .jarvisField()

                    Button("Save key") {
                        saveKey(for: provider)
                    }
                    .buttonStyle(.jarvisPrimary)
                    .disabled(keyDrafts[provider, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasKey {
                        Button("Remove") {
                            removeKey(for: provider)
                        }
                        .buttonStyle(.jarvisDanger)
                    }
                }

                Divider().overlay(JarvisTheme.Palette.stroke)

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Model")

                    Picker("Model", selection: Binding(
                        get: { currentModel },
                        set: { environment.settings.setModel($0, for: provider) }
                    )) {
                        ForEach(provider.models) { model in
                            Text("\(model.displayName) (\(model.id))").tag(model.id)
                        }
                        if !provider.models.contains(where: { $0.id == currentModel }) {
                            Text("Custom: \(currentModel)").tag(currentModel)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 420)

                    HStack(spacing: JarvisTheme.Spacing.tight) {
                        TextField("Or type any model id", text: modelDraftBinding(for: provider))
                            .jarvisField()
                            .frame(maxWidth: 320)

                        Button("Use this model") {
                            let draft = modelDrafts[provider, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !draft.isEmpty else { return }
                            environment.settings.setModel(draft, for: provider)
                            modelDrafts[provider] = ""
                            report("Model for \(provider.displayName) set to \(draft).", isError: false)
                        }
                        .buttonStyle(.jarvisSecondary)
                        .disabled(modelDrafts[provider, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Text("The dropdown lists current models as a convenience. Anything you type here is used verbatim, so a model released after this build still works.")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Actions

    private func saveKey(for provider: AIProviderID) {
        let value = keyDrafts[provider, default: ""]
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let saved = environment.apiKeys.saveKey(value, for: provider)
        keyDrafts[provider] = ""
        if saved {
            report("Key saved for \(provider.displayName). It is stored in the keychain and masked everywhere it is displayed.", isError: false)
        } else {
            report(environment.apiKeys.lastErrorMessage ?? "The key could not be saved.", isError: true)
        }
    }

    private func removeKey(for provider: AIProviderID) {
        let removed = environment.apiKeys.removeKey(for: provider)
        if removed {
            report("Key removed for \(provider.displayName).", isError: false)
        } else {
            report(environment.apiKeys.lastErrorMessage ?? "The key could not be removed.", isError: true)
        }
    }

    private func report(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private func draftBinding(for provider: AIProviderID) -> Binding<String> {
        Binding(
            get: { keyDrafts[provider, default: ""] },
            set: { keyDrafts[provider] = $0 }
        )
    }

    private func modelDraftBinding(for provider: AIProviderID) -> Binding<String> {
        Binding(
            get: { modelDrafts[provider, default: ""] },
            set: { modelDrafts[provider] = $0 }
        )
    }
}

// MARK: - Tools

/// Enables or disables individual assistant tools.
struct AssistantToolsSettingsView: View {

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings

        return VStack(alignment: .leading, spacing: JarvisTheme.Spacing.loose) {
            JarvisCard(title: "Assistant tools", symbolName: "wrench.and.screwdriver") {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                    Text("Enabled tools are offered to the model with every request. Disabling a tool removes it from the prompt, so the assistant will say it cannot do that instead of guessing.")
                        .font(JarvisTheme.Typography.caption(11))
                        .foregroundStyle(JarvisTheme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: JarvisTheme.Spacing.tight) {
                        Button("Enable all") {
                            settings.enabledToolNames = AssistantToolCatalog.allNames
                            settings.persist()
                        }
                        .buttonStyle(.jarvisSecondary)

                        Button("Disable all") {
                            settings.enabledToolNames = []
                            settings.persist()
                        }
                        .buttonStyle(.jarvisSecondary)

                        StatusChip(
                            text: "\(settings.enabledToolNames.count) of \(AssistantToolCatalog.allNames.count) enabled",
                            tint: JarvisTheme.Palette.accent
                        )
                    }

                    Divider().overlay(JarvisTheme.Palette.stroke)

                    VStack(spacing: 6) {
                        ForEach(AssistantToolCatalog.allSchemas) { tool in
                            toolRow(tool)
                        }
                    }
                }
            }

            JarvisCard(title: "Always confirmed", symbolName: "hand.raised") {
                VStack(alignment: .leading, spacing: JarvisTheme.Spacing.tight) {
                    Text("These actions can never run silently, even when the tool above is enabled:")
                        .font(JarvisTheme.Typography.caption(11))
                        .foregroundStyle(JarvisTheme.Palette.textSecondary)
                    bullet("run_terminal_command, which is also limited to the command whitelist")
                    bullet("run_applescript, when Ask before running AppleScript is on in General")
                    bullet("Calendar and reminder writes, which need your EventKit permission first")
                }
            }
        }
    }

    private func toolRow(_ tool: AssistantToolSchema) -> some View {
        @Bindable var settings = environment.settings
        let isEnabled = settings.isToolEnabled(tool.name)

        return HStack(alignment: .top, spacing: JarvisTheme.Spacing.regular) {
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEnabled ? JarvisTheme.Palette.success : JarvisTheme.Palette.textTertiary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .font(JarvisTheme.Typography.mono(11))
                        .foregroundStyle(JarvisTheme.Palette.textPrimary)
                    if AssistantToolName.confirmationRequired.contains(tool.name) {
                        StatusChip(text: "Confirmation", tint: JarvisTheme.Palette.warning)
                    }
                }
                Text(tool.description)
                    .font(JarvisTheme.Typography.caption(10))
                    .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { settings.isToolEnabled(tool.name) },
                set: { settings.setTool(tool.name, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(JarvisTheme.Palette.accent)
        }
        .padding(JarvisTheme.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(JarvisTheme.Palette.canvas.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(JarvisTheme.Palette.stroke, lineWidth: 1)
        )
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(JarvisTheme.Palette.warning)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(JarvisTheme.Typography.caption(10))
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
