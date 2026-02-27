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

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 450, height: 280)
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
            }

            Section("Display") {
                Picker("Temperature Units", selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        AppDelegate.setLaunchAtLogin(newValue)
                    }
                    .help("Automatically start HomeKit Automator when you log in.")
            }
        }
        .formStyle(.grouped)
        .padding()
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

                if socketPath != AppSettingsDefaults.socketPath {
                    Button("Reset to Default") {
                        socketPath = AppSettingsDefaults.socketPath
                    }
                    .font(.caption)
                }
            }

            Section("Logging") {
                Stepper("Log Retention: \(logRetentionDays) days",
                        value: $logRetentionDays,
                        in: 1...365)
                    .help("Number of days to keep execution log entries.")
            }

            Section("Helper Process") {
                Stepper("Max Restarts: \(maxHelperRestarts)",
                        value: $maxHelperRestarts,
                        in: 1...20)
                    .help("Maximum number of automatic restarts within a 15-minute window.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview("Settings") {
    SettingsView()
}
