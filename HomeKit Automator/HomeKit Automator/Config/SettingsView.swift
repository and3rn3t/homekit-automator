// SettingsView.swift
// Settings panel with General and Advanced tabs, backed by @AppStorage bindings.

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            LLMSettingsTab()
                .tabItem {
                    Label("LLM", systemImage: "brain")
                }

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 550, height: 400)
        .accessibilityIdentifier(AccessibilityID.Settings.tabView)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage(AppSettingsKeys.defaultHomeName)
    private var defaultHomeName: String = AppSettingsDefaults.defaultHomeName

    @AppStorage(AppSettingsKeys.temperatureUnit)
    private var temperatureUnit: String = AppSettingsDefaults.temperatureUnit

    @AppStorage(AppSettingsKeys.launchAtLogin)
    private var launchAtLogin: Bool = AppSettingsDefaults.launchAtLogin

    var body: some View {
        Form {
            Section("Home") {
                TextField("Default Home Name", text: $defaultHomeName, prompt: Text("My Home"))
                    .help("The default home used when commands don't specify one.")
                    .accessibilityIdentifier(AccessibilityID.Settings.homeNameField)
            }

            Section("Display") {
                Picker("Temperature Units", selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(AccessibilityID.Settings.temperaturePicker)
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        AppDelegate.setLaunchAtLogin(newValue)
                    }
                    .help("Automatically start HomeKit Automator when you log in.")
                    .accessibilityIdentifier(AccessibilityID.Settings.launchAtLoginToggle)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - LLM Tab

struct LLMSettingsTab: View {
    @AppStorage(AppSettingsKeys.llmEnabled)
    private var llmEnabled: Bool = AppSettingsDefaults.llmEnabled

    @AppStorage(AppSettingsKeys.llmProvider)
    private var llmProvider: String = AppSettingsDefaults.llmProvider

    /// API key stored in Keychain (not UserDefaults) for security.
    /// Loaded on appear and persisted on change via KeychainHelper.
    @State private var llmAPIKey: String =
        KeychainHelper.read(forKey: AppSettingsKeys.llmAPIKey) ?? ""

    @AppStorage(AppSettingsKeys.llmModel)
    private var llmModel: String = AppSettingsDefaults.llmModel

    @AppStorage(AppSettingsKeys.llmEndpoint)
    private var llmEndpoint: String = AppSettingsDefaults.llmEndpoint

    @AppStorage(AppSettingsKeys.llmTimeout)
    private var llmTimeout: Int = AppSettingsDefaults.llmTimeout

    @State private var isTestingConnection = false
    @State private var testResult: String?
    @State private var showAPIKey = false

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: llmProvider) ?? .openai
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Natural Language Automation Creation", isOn: $llmEnabled)
                    .help("Allow creating automations using natural language descriptions")
                    .accessibilityIdentifier(AccessibilityID.Settings.llmEnabledToggle)

                if !llmEnabled {
                    Text("Enable this to use AI-powered automation creation from natural language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if llmEnabled {
                Section("Provider") {
                    Picker("LLM Provider", selection: $llmProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.Settings.llmProviderPicker)
                    .onChange(of: llmProvider) { _, newValue in
                        // Update defaults when provider changes
                        if let provider = LLMProvider(rawValue: newValue) {
                            if llmModel.isEmpty {
                                llmModel = provider.defaultModel
                            }
                            if llmEndpoint.isEmpty {
                                llmEndpoint = provider.defaultEndpoint
                            }
                        }
                    }

                    Text(providerHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Authentication") {
                    HStack {
                        if showAPIKey {
                            TextField(
                                "API Key", text: $llmAPIKey, prompt: Text("Enter your API key"))
                        } else {
                            SecureField(
                                "API Key", text: $llmAPIKey, prompt: Text("Enter your API key"))
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .help(showAPIKey ? "Hide API key" : "Show API key")
                        .accessibilityIdentifier(AccessibilityID.Settings.llmShowKeyToggle)
                    }

                    if llmAPIKey.isEmpty {
                        Text("⚠️ API key is required for LLM features to work")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Link("Get API Key →", destination: apiKeyURL)
                        .font(.caption)
                }
                .onChange(of: llmAPIKey) { _, newValue in
                    // Persist API key to Keychain (secure) instead of UserDefaults
                    if newValue.isEmpty {
                        KeychainHelper.delete(forKey: AppSettingsKeys.llmAPIKey)
                    } else {
                        do {
                            try KeychainHelper.save(newValue, forKey: AppSettingsKeys.llmAPIKey)
                        } catch {
                            print("[Settings] WARNING: Failed to save API key to Keychain: \(error.localizedDescription)")
                            testResult = "⚠️ Could not save API key to Keychain. It may not persist across restarts."
                        }
                    }
                }

                Section("Configuration") {
                    TextField("Model", text: $llmModel, prompt: Text(selectedProvider.defaultModel))
                        .help("Leave empty to use provider default")
                        .accessibilityIdentifier(AccessibilityID.Settings.llmModelField)

                    TextField(
                        "Endpoint", text: $llmEndpoint,
                        prompt: Text(selectedProvider.defaultEndpoint)
                    )
                    .help("Leave empty to use provider default")
                    .accessibilityIdentifier(AccessibilityID.Settings.llmEndpointField)

                    Stepper(
                        "Timeout: \(llmTimeout) seconds", value: $llmTimeout, in: 10...120, step: 5
                    )
                    .help("Maximum time to wait for LLM response")
                    .accessibilityIdentifier(AccessibilityID.Settings.llmTimeoutStepper)

                    HStack {
                        Button("Reset to Defaults") {
                            llmModel = ""
                            llmEndpoint = ""
                            llmTimeout = AppSettingsDefaults.llmTimeout
                        }
                        .font(.caption)
                        .accessibilityIdentifier(AccessibilityID.Settings.llmResetDefaultsButton)

                        Spacer()

                        Button(action: testConnection) {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Testing...")
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(llmAPIKey.isEmpty || isTestingConnection)
                        .accessibilityIdentifier(AccessibilityID.Settings.llmTestConnectionButton)
                    }

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("✓") ? .green : .red)
                            .accessibilityIdentifier(AccessibilityID.Settings.llmTestResult)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var providerHelpText: String {
        switch selectedProvider {
        case .openai:
            return "GPT-4 provides excellent automation parsing with reliable JSON output."
        case .claude:
            return "Claude 3 offers strong natural language understanding for complex automations."
        case .custom:
            return "Use a custom LLM endpoint (must be OpenAI-compatible API format)."
        }
    }

    private var apiKeyURL: URL {
        let urlString: String
        switch selectedProvider {
        case .openai:
            urlString = "https://platform.openai.com/api-keys"
        case .claude:
            urlString = "https://console.anthropic.com/settings/keys"
        case .custom:
            urlString = "https://example.com"
        }
        // These are hardcoded valid URLs, but guard against unexpected failures
        return URL(string: urlString) ?? URL(string: "https://example.com")!
    }

    private func testConnection() {
        Task {
            isTestingConnection = true
            testResult = nil
            defer { isTestingConnection = false }

            do {
                guard let service = LLMService() else {
                    testResult = "✗ Configuration invalid"
                    return
                }

                // Simple test prompt
                let definition = try await service.parseAutomation(
                    from: "Turn on the test light",
                    deviceContext: nil
                )

                if !definition.name.isEmpty && !definition.actions.isEmpty {
                    testResult = "✓ Connection successful!"
                } else {
                    testResult = "✗ Response invalid (missing required fields)"
                }
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @AppStorage(AppSettingsKeys.socketPath)
    private var socketPath: String = AppSettingsDefaults.socketPath

    @AppStorage(AppSettingsKeys.logRetentionDays)
    private var logRetentionDays: Int = AppSettingsDefaults.logRetentionDays

    @AppStorage(AppSettingsKeys.maxHelperRestarts)
    private var maxHelperRestarts: Int = AppSettingsDefaults.maxHelperRestarts

    var body: some View {
        Form {
            Section("Communication") {
                TextField("Socket Path", text: $socketPath)
                    .help("Unix domain socket path for communicating with the HomeKitHelper.")
                    .accessibilityIdentifier(AccessibilityID.Settings.socketPathField)

                if socketPath != AppSettingsDefaults.socketPath {
                    Button("Reset to Default") {
                        socketPath = AppSettingsDefaults.socketPath
                    }
                    .font(.caption)
                }
            }

            Section("Logging") {
                Stepper(
                    "Log Retention: \(logRetentionDays) days",
                    value: $logRetentionDays,
                    in: 1...365
                )
                .help("Number of days to keep execution log entries.")
                .accessibilityIdentifier(AccessibilityID.Settings.logRetentionStepper)
            }

            Section("Helper Process") {
                Stepper(
                    "Max Restarts: \(maxHelperRestarts)",
                    value: $maxHelperRestarts,
                    in: 1...20
                )
                .help("Maximum number of automatic restarts within a 15-minute window.")
                .accessibilityIdentifier(AccessibilityID.Settings.maxRestartsStepper)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview("Settings") {
    SettingsView()
}
