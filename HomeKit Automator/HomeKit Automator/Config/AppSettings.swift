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

/// LLM provider options.
enum LLMProvider: String, CaseIterable, Identifiable {
    case openai = "openai"
    case claude = "claude"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI (GPT-4)"
        case .claude: return "Anthropic Claude"
        case .custom: return "Custom Endpoint"
        }
    }
    
    var defaultEndpoint: String {
        switch self {
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .claude: return "https://api.anthropic.com/v1/messages"
        case .custom: return ""
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o"
        case .claude: return "claude-sonnet-4-20250514"
        case .custom: return ""
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
    
    // LLM Integration
    static let llmProvider = "llmProvider"
    static let llmAPIKey = "llmAPIKey"
    static let llmModel = "llmModel"
    static let llmEndpoint = "llmEndpoint"
    static let llmTimeout = "llmTimeout"
    static let llmEnabled = "llmEnabled"
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
    
    // LLM defaults
    static let llmProvider = LLMProvider.openai.rawValue
    static let llmAPIKey = ""
    static let llmModel = ""  // Empty means use provider default
    static let llmEndpoint = ""  // Empty means use provider default
    static let llmTimeout = 30
    static let llmEnabled = false
}
