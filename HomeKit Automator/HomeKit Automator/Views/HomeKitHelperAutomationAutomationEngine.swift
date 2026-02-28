// AutomationEngine.swift
// Core automation execution engine. Manages automation lifecycle and execution.

import Foundation

/// Main automation execution engine.
actor AutomationEngine {
    
    // MARK: - Properties
    
    private let homeKitManager: HomeKitManager
    private let registry: AutomationRegistry
    private let logger = HelperLogger.shared
    
    private var logFile: URL
    private var logEntries: [AutomationLogEntry] = []
    
    // MARK: - Init
    
    init(homeKitManager: HomeKitManager) {
        self.homeKitManager = homeKitManager
        self.registry = AutomationRegistry()
        
        // Set up log file
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupport.appendingPathComponent("homekit-automator/logs")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        self.logFile = logDir.appendingPathComponent("automation-log.json")
        
        // Load existing log
        if let data = try? Data(contentsOf: logFile),
           let entries = try? JSONDecoder().decode([AutomationLogEntry].self, from: data) {
            self.logEntries = entries
        }
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        await logger.log("Automation engine starting", level: .info)
        
        // Load automations
        do {
            let automations = try await registry.load()
            await logger.log("Loaded \(automations.count) automations", level: .info)
            
            // TODO: Schedule enabled automations
            // For MVP, only manual triggers are supported
        } catch {
            await logger.logError(error)
        }
    }
    
    func stop() async {
        await logger.log("Automation engine stopping", level: .info)
        
        // TODO: Cancel scheduled timers
        
        // Save log
        do {
            try await saveLog()
        } catch {
            await logger.logError(error)
        }
    }
    
    // MARK: - Automation Management
    
    /// Creates a new automation from JSON definition.
    func createAutomation(from jsonString: String) async throws -> CreateAutomationResponse {
        await logger.log("Creating automation from JSON", level: .debug)
        
        // Parse JSON
        guard let data = jsonString.data(using: .utf8) else {
            throw AutomationEngineError.invalidJSON
        }
        
        let definition = try JSONDecoder().decode(AutomationDefinition.self, from: data)
        
        // Validate
        try await validateDefinition(definition)
        
        // Create registered automation
        let registered = RegisteredAutomation(
            id: UUID().uuidString,
            name: definition.name,
            description: definition.description,
            trigger: definition.trigger,
            conditions: definition.conditions,
            actions: definition.actions,
            enabled: definition.enabled ?? true,
            shortcutName: definition.name,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            lastRun: nil
        )
        
        // Add to registry
        try await registry.add(registered)
        
        await logger.log("Created automation: \(registered.name) (\(registered.id))", level: .info)
        
        return CreateAutomationResponse(
            success: true,
            automationId: registered.id,
            message: "Automation created successfully"
        )
    }
    
    /// Lists all automations.
    func listAutomations() async throws -> [RegisteredAutomation] {
        return await registry.getAll()
    }
    
    /// Gets a specific automation.
    func getAutomation(id: String) async throws -> RegisteredAutomation {
        return try await registry.get(id: id)
    }
    
    /// Enables an automation.
    func enableAutomation(id: String) async throws {
        try await registry.enable(id: id)
        // TODO: Schedule if it's a timer-based trigger
    }
    
    /// Disables an automation.
    func disableAutomation(id: String) async throws {
        try await registry.disable(id: id)
        // TODO: Unschedule if it's a timer-based trigger
    }
    
    /// Deletes an automation.
    func deleteAutomation(id: String) async throws {
        // TODO: Unschedule if it's a timer-based trigger
        try await registry.delete(id: id)
    }
    
    // MARK: - Execution
    
    /// Manually triggers an automation.
    func triggerAutomation(id: String) async throws {
        let automation = try await registry.get(id: id)
        
        await logger.log("Manually triggering automation: \(automation.name)", level: .info)
        
        await executeAutomation(automation)
    }
    
    /// Executes an automation's actions.
    private func executeAutomation(_ automation: RegisteredAutomation) async {
        let startTime = Date()
        let timestamp = ISO8601DateFormatter().string(from: startTime)
        
        await logger.log("Executing automation: \(automation.name)", level: .info)
        
        var succeeded = 0
        var failed = 0
        var errors: [String] = []
        
        // Execute each action
        for (index, action) in automation.actions.enumerated() {
            // Delay if specified
            if action.delaySeconds > 0 {
                await logger.log("Delaying \(action.delaySeconds)s before action \(index + 1)", level: .debug)
                try? await Task.sleep(for: .seconds(TimeInterval(action.delaySeconds)))
            }
            
            do {
                try await executeAction(action)
                succeeded += 1
                await logger.log("Action \(index + 1) succeeded", level: .debug)
            } catch {
                failed += 1
                let errorMsg = "Action \(index + 1) failed: \(error.localizedDescription)"
                errors.append(errorMsg)
                await logger.log(errorMsg, level: .error)
            }
        }
        
        // Update last run
        do {
            try await registry.updateLastRun(id: automation.id, timestamp: timestamp)
        } catch {
            await logger.logError(error)
        }
        
        // Log execution
        let logEntry = AutomationLogEntry(
            automationId: automation.id,
            automationName: automation.name,
            timestamp: timestamp,
            actionsExecuted: automation.actions.count,
            succeeded: succeeded,
            failed: failed,
            errors: errors.isEmpty ? nil : errors
        )
        
        logEntries.append(logEntry)
        
        // Save log to disk
        try? await saveLog()
        
        let duration = Date().timeIntervalSince(startTime)
        await logger.log("Automation completed in \(String(format: "%.2f", duration))s: \(succeeded) succeeded, \(failed) failed", level: .info)
    }
    
    /// Executes a single action.
    private func executeAction(_ action: AutomationAction) async throws {
        await logger.log("Executing action: \(action.deviceName) - \(action.characteristic)", level: .debug)
        
        // For MVP, we only support device control actions
        // Scene actions would be handled differently
        
        if let _ = action.sceneUuid, let sceneName = action.sceneName {
            // Scene activation
            try await homeKitManager.activateScene(name: sceneName)
        } else {
            // Device characteristic write
            guard !action.deviceUuid.isEmpty else {
                throw AutomationEngineError.invalidAction("Device UUID is empty")
            }
            
            try await homeKitManager.setCharacteristic(
                deviceUUID: action.deviceUuid,
                characteristic: action.characteristic,
                value: action.value.rawValue
            )
        }
    }
    
    // MARK: - Validation
    
    private func validateDefinition(_ definition: AutomationDefinition) async throws {
        // Validate name
        guard !definition.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AutomationEngineError.invalidDefinition("Name is required")
        }
        
        // Validate actions
        guard !definition.actions.isEmpty else {
            throw AutomationEngineError.invalidDefinition("At least one action is required")
        }
        
        // TODO: Validate device UUIDs exist in HomeKit
        // For MVP, we skip this validation to allow creation without real devices
    }
    
    // MARK: - Logging
    
    func getExecutionLog() async throws -> [AutomationLogEntry] {
        return logEntries
    }
    
    private func saveLog() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(logEntries)
        try data.write(to: logFile, options: .atomic)
    }
}

// MARK: - Errors

enum AutomationEngineError: LocalizedError {
    case invalidJSON
    case invalidDefinition(String)
    case invalidAction(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON format"
        case .invalidDefinition(let details):
            return "Invalid automation definition: \(details)"
        case .invalidAction(let details):
            return "Invalid action: \(details)"
        case .executionFailed(let details):
            return "Execution failed: \(details)"
        }
    }
}
