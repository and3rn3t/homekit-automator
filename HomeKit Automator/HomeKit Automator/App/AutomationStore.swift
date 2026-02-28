// AutomationStore.swift
// Observable store that wraps the on-disk automation registry and log for use in SwiftUI views.
//
// Reads from / writes to the same JSON files as the CLI:
//   ~/Library/Application Support/homekit-automator/automations.json
//   ~/Library/Application Support/homekit-automator/logs/automation-log.json

import Foundation

/// Provides reactive access to the automation registry and execution log.
///
/// All mutations persist to disk atomically so the CLI and GUI always share
/// the same source of truth.
@Observable
@MainActor
final class AutomationStore {

    // MARK: - Published State

    /// All registered automations loaded from disk.
    private(set) var automations: [RegisteredAutomation] = []

    /// Execution log entries loaded from disk.
    private(set) var logEntries: [AutomationLogEntry] = []

    /// Error message from the most recent operation, if any.
    private(set) var lastError: String?

    // MARK: - File Paths

    let configDir: URL  // Make public for debugging

    private var registryPath: URL {
        configDir.appendingPathComponent("automations.json")
    }

    private var logPath: URL {
        configDir.appendingPathComponent("logs").appendingPathComponent("automation-log.json")
    }

    // MARK: - Init

    init(configDir: URL? = nil) {
        // Use Application Support directory to match the CLI's AutomationRegistry
        // (via SocketConstants.appSupportDir). Previously this defaulted to
        // ~/.config/homekit-automator/ which was a different directory.
        self.configDir = configDir ?? {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else {
                // Practically unreachable on macOS, but provide a safe fallback
                return FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config")
                    .appendingPathComponent("homekit-automator")
            }
            return appSupport.appendingPathComponent("homekit-automator")
        }()
        reload()
    }

    // MARK: - Load

    /// Reloads automations and log entries from disk.
    func reload() {
        loadAutomations()
        loadLog()
    }

    private func loadAutomations() {
        guard FileManager.default.fileExists(atPath: registryPath.path) else {
            automations = []
            return
        }
        do {
            let data = try Data(contentsOf: registryPath)
            automations = try JSONDecoder().decode([RegisteredAutomation].self, from: data)
            lastError = nil
        } catch {
            lastError = "Failed to load automations: \(error.localizedDescription)"
            automations = []
        }
    }

    private func loadLog() {
        guard FileManager.default.fileExists(atPath: logPath.path) else {
            logEntries = []
            return
        }
        do {
            let data = try Data(contentsOf: logPath)
            logEntries = try JSONDecoder().decode([AutomationLogEntry].self, from: data)
            lastError = nil
        } catch {
            lastError = "Failed to load log: \(error.localizedDescription)"
            logEntries = []
        }
    }

    // MARK: - CRUD

    /// Toggles the enabled state of an automation and saves to disk.
    func toggleEnabled(_ automationId: String) {
        guard let index = automations.firstIndex(where: { $0.id == automationId }) else { return }
        automations[index].enabled.toggle()
        persistAutomations()
    }

    /// Deletes an automation by ID and saves to disk.
    func delete(_ automationId: String) {
        automations.removeAll { $0.id == automationId }
        persistAutomations()
    }

    // MARK: - Persistence

    private func persistAutomations() {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(automations)
            try data.write(to: registryPath, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Failed to save automations: \(error.localizedDescription)"
        }
    }

    // MARK: - Queries

    /// Returns log entries for a specific automation.
    func logEntries(for automationId: String) -> [AutomationLogEntry] {
        logEntries.filter { $0.automationId == automationId }
    }

    /// Returns the overall success rate for a specific automation as a percentage (0–100).
    func successRate(for automationId: String) -> Double {
        let entries = logEntries(for: automationId)
        guard !entries.isEmpty else { return 100.0 }
        let totalActions = entries.reduce(0) { $0 + $1.actionsExecuted }
        let totalSucceeded = entries.reduce(0) { $0 + $1.succeeded }
        guard totalActions > 0 else { return 100.0 }
        return Double(totalSucceeded) / Double(totalActions) * 100.0
    }
}
