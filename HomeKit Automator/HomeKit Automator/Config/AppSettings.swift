// AppSettings.swift
// Settings model backed by UserDefaults/@AppStorage for the HomeKit Automator app.

import SwiftUI

/// Temperature unit preference.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius = "celsius"
    case fahrenheit = "fahrenheit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .celsius: return "Celsius (°C)"
        case .fahrenheit: return "Fahrenheit (°F)"
        }
    }
}

/// Centralized access to all user-facing settings, backed by UserDefaults.
///
/// These keys are shared across the app. Default values are defined inline
/// so that `@AppStorage` bindings always have a fallback.
enum AppSettingsKeys {
    // General
    static let defaultHomeName = "defaultHomeName"
    static let temperatureUnit = "temperatureUnit"
    static let launchAtLogin = "launchAtLogin"

    // Advanced
    static let socketPath = "socketPath"
    static let logRetentionDays = "logRetentionDays"
    static let maxHelperRestarts = "maxHelperRestarts"
}

/// Default values for settings.
enum AppSettingsDefaults {
    static let defaultHomeName = ""
    static let temperatureUnit = TemperatureUnit.celsius.rawValue
    static let launchAtLogin = false
    static let socketPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("homekit-automator")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("homekitauto.sock").path
    }()
    static let logRetentionDays = 30
    static let maxHelperRestarts = 5
}
