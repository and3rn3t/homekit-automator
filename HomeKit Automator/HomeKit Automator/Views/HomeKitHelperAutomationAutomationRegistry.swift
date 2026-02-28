// AutomationRegistry.swift
// Manages persistence of automations to disk (JSON files).

import Foundation

/// Manages loading and saving automations to the filesystem.
actor AutomationRegistry {
    
    // MARK: - Properties
    
    private let configDir: URL
    private let registryPath: URL
    private let logger = HelperLogger.shared
    
    private var automations: [RegisteredAutomation] = []
    
    // MARK: - Init
    
    init() {
        // Use Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        configDir = appSupport.appendingPathComponent("homekit-automator")
        registryPath = configDir.appendingPathComponent("automations.json")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    // MARK: - Load
    
    /// Loads all automations from disk.
    func load() async throws -> [RegisteredAutomation] {
        guard FileManager.default.fileExists(atPath: registryPath.path) else {
            await logger.log("No automations file found, starting with empty registry", level: .info)
            automations = []
            return []
        }
        
        await logger.log("Loading automations from disk", level: .debug)
        
        let data = try Data(contentsOf: registryPath)
        let decoder = JSONDecoder()
        automations = try decoder.decode([RegisteredAutomation].self, from: data)
        
        await logger.log("Loaded \(automations.count) automations", level: .info)
        
        return automations
    }
    
    // MARK: - Save
    
    /// Saves all automations to disk.
    func save() async throws {
        await logger.log("Saving \(automations.count) automations to disk", level: .debug)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(automations)
        try data.write(to: registryPath, options: .atomic)
        
        await logger.log("Automations saved successfully", level: .debug)
    }
    
    // MARK: - CRUD Operations
    
    /// Adds a new automation to the registry.
    func add(_ automation: RegisteredAutomation) async throws {
        // Check for duplicate ID
        if automations.contains(where: { $0.id == automation.id }) {
            throw RegistryError.duplicateId(automation.id)
        }
        
        automations.append(automation)
        try await save()
        
        await logger.log("Added automation: \(automation.name) (\(automation.id))", level: .info)
    }
    
    /// Gets an automation by ID.
    func get(id: String) async throws -> RegisteredAutomation {
        guard let automation = automations.first(where: { $0.id == id }) else {
            throw RegistryError.notFound(id)
        }
        
        return automation
    }
    
    /// Gets all automations.
    func getAll() async -> [RegisteredAutomation] {
        return automations
    }
    
    /// Updates an existing automation.
    func update(_ automation: RegisteredAutomation) async throws {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else {
            throw RegistryError.notFound(automation.id)
        }
        
        automations[index] = automation
        try await save()
        
        await logger.log("Updated automation: \(automation.name) (\(automation.id))", level: .info)
    }
    
    /// Deletes an automation by ID.
    func delete(id: String) async throws {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw RegistryError.notFound(id)
        }
        
        let name = automations[index].name
        automations.remove(at: index)
        try await save()
        
        await logger.log("Deleted automation: \(name) (\(id))", level: .info)
    }
    
    /// Enables an automation.
    func enable(id: String) async throws {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw RegistryError.notFound(id)
        }
        
        automations[index].enabled = true
        try await save()
        
        await logger.log("Enabled automation: \(automations[index].name)", level: .info)
    }
    
    /// Disables an automation.
    func disable(id: String) async throws {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw RegistryError.notFound(id)
        }
        
        automations[index].enabled = false
        try await save()
        
        await logger.log("Disabled automation: \(automations[index].name)", level: .info)
    }
    
    /// Updates the last run timestamp for an automation.
    func updateLastRun(id: String, timestamp: String) async throws {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw RegistryError.notFound(id)
        }
        
        automations[index].lastRun = timestamp
        try await save()
    }
}

// MARK: - Errors

enum RegistryError: LocalizedError {
    case notFound(String)
    case duplicateId(String)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Automation not found: \(id)"
        case .duplicateId(let id):
            return "Automation with ID already exists: \(id)"
        case .invalidData:
            return "Invalid automation data"
        }
    }
}
