// AccessibilityIDs.swift
// Centralized accessibility identifiers for UI testing.
// Keep in sync with HomeKit_AutomatorUITests when adding new IDs.

import Foundation

/// Namespace for accessibility identifiers used in XCUITests.
/// Organized by view to avoid conflicts.
enum AccessibilityID {

    // MARK: - ContentView (Main Automations Window)
    enum Content {
        static let sidebar = "content.sidebar"
        static let createButton = "content.createButton"
        static let refreshButton = "content.refreshButton"
        static let emptyCreateButton = "content.emptyCreateButton"
        static let detailPlaceholder = "content.detailPlaceholder"
    }

    // MARK: - AutomationDetailView
    enum Detail {
        static let enableToggle = "detail.enableToggle"
        static let runNowButton = "detail.runNowButton"
        static let deleteButton = "detail.deleteButton"
        static let errorMessage = "detail.errorMessage"
        static let successRate = "detail.successRate"
    }

    // MARK: - DashboardView
    enum Dashboard {
        static let title = "dashboard.title"
        static let refreshButton = "dashboard.refreshButton"
        static let searchField = "dashboard.searchField"
        static let automationList = "dashboard.automationList"
        static let emptyState = "dashboard.emptyState"
        static let errorBar = "dashboard.errorBar"
    }

    // MARK: - HistoryView
    enum History {
        static let title = "history.title"
        static let refreshButton = "history.refreshButton"
        static let searchField = "history.searchField"
        static let statusFilter = "history.statusFilter"
        static let startDatePicker = "history.startDate"
        static let endDatePicker = "history.endDate"
        static let sortButton = "history.sortButton"
        static let summaryBar = "history.summaryBar"
        static let entryList = "history.entryList"
        static let emptyState = "history.emptyState"
    }

    // MARK: - CreateAutomationView
    enum Create {
        static let title = "create.title"
        static let cancelButton = "create.cancelButton"
        static let promptEditor = "create.promptEditor"
        static let createButton = "create.createButton"
        static let errorMessage = "create.errorMessage"
        static let llmDisabledNotice = "create.llmDisabledNotice"
    }

    // MARK: - DebugView
    enum Debug {
        static let title = "debug.title"
        static let refreshButton = "debug.refreshButton"
        static let helperStatus = "debug.helperStatus"
        static let socketPath = "debug.socketPath"
        static let socketExists = "debug.socketExists"
        static let automationCount = "debug.automationCount"
        static let logCount = "debug.logCount"
        static let testSocketButton = "debug.testSocketButton"
        static let openConfigButton = "debug.openConfigButton"
        static let copyDiagnosticsButton = "debug.copyDiagnosticsButton"
        static let resetTokenButton = "debug.resetTokenButton"
    }

    // MARK: - SettingsView
    enum Settings {
        static let tabView = "settings.tabView"

        // General tab
        static let homeNameField = "settings.homeName"
        static let temperaturePicker = "settings.temperatureUnit"
        static let launchAtLoginToggle = "settings.launchAtLogin"

        // LLM tab
        static let llmEnabledToggle = "settings.llmEnabled"
        static let llmProviderPicker = "settings.llmProvider"
        static let llmAPIKeyField = "settings.llmAPIKey"
        static let llmModelField = "settings.llmModel"
        static let llmEndpointField = "settings.llmEndpoint"
        static let llmTimeoutStepper = "settings.llmTimeout"
        static let llmResetDefaultsButton = "settings.llmResetDefaults"
        static let llmTestConnectionButton = "settings.llmTestConnection"
        static let llmTestResult = "settings.llmTestResult"
        static let llmShowKeyToggle = "settings.llmShowKey"

        // Advanced tab
        static let socketPathField = "settings.socketPath"
        static let logRetentionStepper = "settings.logRetention"
        static let maxRestartsStepper = "settings.maxRestarts"
    }

    // MARK: - AutomationListItem
    enum ListItem {
        static func row(_ id: String) -> String { "listItem.row.\(id)" }
        static func toggle(_ id: String) -> String { "listItem.toggle.\(id)" }
        static func deleteButton(_ id: String) -> String { "listItem.delete.\(id)" }
    }
}
