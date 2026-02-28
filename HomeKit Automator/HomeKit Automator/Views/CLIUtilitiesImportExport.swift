// ImportExport.swift
// Import and export automation definitions as JSON files.

import Foundation

/// Handles importing and exporting automations.
struct ImportExport {
    
    private let apiClient: HelperAPIClient
    
    init(apiClient: HelperAPIClient = .shared) {
        self.apiClient = apiClient
    }
    
    // MARK: - Export
    
    /// Exports a single automation to JSON.
    func exportAutomation(id: String, outputPath: String? = nil) async throws {
        // Load automation
        let automations = try await apiClient.listAutomations()
        
        guard let automation = automations.first(where: { $0.id == id }) else {
            throw ImportExportError.automationNotFound(id)
        }
        
        // Convert to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(automation)
        
        // Determine output path
        let path = outputPath ?? "\(automation.name.replacingOccurrences(of: " ", with: "-")).json"
        let url = URL(fileURLWithPath: path)
        
        // Write to file
        try data.write(to: url)
        
        Terminal.printSuccess("Exported automation to: \(url.path)")
    }
    
    /// Exports all automations to a single JSON file.
    func exportAll(outputPath: String) async throws {
        let automations = try await apiClient.listAutomations()
        
        guard !automations.isEmpty else {
            Terminal.printWarning("No automations to export")
            return
        }
        
        // Convert to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(automations)
        
        // Write to file
        let url = URL(fileURLWithPath: outputPath)
        try data.write(to: url)
        
        Terminal.printSuccess("Exported \(automations.count) automation(s) to: \(url.path)")
    }
    
    /// Exports automations matching a filter.
    func exportFiltered(
        enabled: Bool? = nil,
        pattern: String? = nil,
        outputPath: String
    ) async throws {
        var automations = try await apiClient.listAutomations()
        
        // Apply filters
        if let enabled = enabled {
            automations = automations.filter { $0.enabled == enabled }
        }
        
        if let pattern = pattern {
            let lowercasePattern = pattern.lowercased()
            automations = automations.filter { $0.name.lowercased().contains(lowercasePattern) }
        }
        
        guard !automations.isEmpty else {
            Terminal.printWarning("No automations match the filter")
            return
        }
        
        // Export
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(automations)
        
        let url = URL(fileURLWithPath: outputPath)
        try data.write(to: url)
        
        Terminal.printSuccess("Exported \(automations.count) automation(s) to: \(url.path)")
    }
    
    // MARK: - Import
    
    /// Imports automations from a JSON file.
    func importAutomations(
        from filePath: String,
        strategy: ImportStrategy = .ask,
        validate: Bool = true
    ) async throws {
        // Read file
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        
        // Try to parse as array
        let decoder = JSONDecoder()
        var automations: [RegisteredAutomation]
        
        if let array = try? decoder.decode([RegisteredAutomation].self, from: data) {
            automations = array
        } else if let single = try? decoder.decode(RegisteredAutomation.self, from: data) {
            automations = [single]
        } else {
            throw ImportExportError.invalidJSON
        }
        
        Terminal.printInfo("Found \(automations.count) automation(s) in file")
        
        // Load existing automations
        let existing = try await apiClient.listAutomations()
        let existingIDs = Set(existing.map { $0.id })
        let existingNames = Set(existing.map { $0.name })
        
        // Check for conflicts
        var conflicts: [RegisteredAutomation] = []
        var new: [RegisteredAutomation] = []
        
        for automation in automations {
            if existingIDs.contains(automation.id) || existingNames.contains(automation.name) {
                conflicts.append(automation)
            } else {
                new.append(automation)
            }
        }
        
        if !conflicts.isEmpty {
            Terminal.printWarning("Found \(conflicts.count) conflict(s)")
            
            for conflict in conflicts {
                Terminal.print("  • " + Terminal.colored(conflict.name, .yellow))
            }
            
            // Handle conflicts based on strategy
            let resolvedConflicts = try await resolveConflicts(conflicts, strategy: strategy)
            automations = new + resolvedConflicts
        }
        
        // Validate if requested
        if validate {
            Terminal.print("\n" + Terminal.spinner("Validating automations..."))
            
            let validator = ValidationEngine(apiClient: apiClient)
            var validAutomations: [RegisteredAutomation] = []
            
            for automation in automations {
                let definition = AutomationDefinition(
                    name: automation.name,
                    description: automation.description,
                    trigger: automation.trigger,
                    conditions: automation.conditions,
                    actions: automation.actions,
                    enabled: automation.enabled
                )
                
                let result = try await validator.validate(definition)
                
                if result.isValid {
                    validAutomations.append(automation)
                } else {
                    Terminal.printWarning("Skipping invalid automation: \(automation.name)")
                }
            }
            
            automations = validAutomations
        }
        
        // Import
        guard !automations.isEmpty else {
            Terminal.printWarning("No automations to import")
            return
        }
        
        Terminal.print("\n" + Terminal.spinner("Importing \(automations.count) automation(s)..."))
        
        var imported = 0
        var failed = 0
        
        for automation in automations {
            do {
                // Convert to definition
                let definition = AutomationDefinition(
                    name: automation.name,
                    description: automation.description,
                    trigger: automation.trigger,
                    conditions: automation.conditions,
                    actions: automation.actions,
                    enabled: automation.enabled
                )
                
                _ = try await apiClient.createAutomation(definition)
                imported += 1
            } catch {
                Terminal.printError("Failed to import '\(automation.name)': \(error.localizedDescription)")
                failed += 1
            }
        }
        
        Terminal.printSuccess("Imported \(imported) automation(s)")
        
        if failed > 0 {
            Terminal.printWarning("\(failed) automation(s) failed to import")
        }
    }
    
    // MARK: - Conflict Resolution
    
    private func resolveConflicts(
        _ conflicts: [RegisteredAutomation],
        strategy: ImportStrategy
    ) async throws -> [RegisteredAutomation] {
        switch strategy {
        case .skip:
            return []
            
        case .overwrite:
            return conflicts
            
        case .rename:
            return conflicts.map { automation in
                var modified = automation
                modified.name = "\(automation.name) (imported)"
                modified.id = UUID().uuidString
                return modified
            }
            
        case .ask:
            var resolved: [RegisteredAutomation] = []
            
            for conflict in conflicts {
                Terminal.print("\n" + Terminal.warningIcon("Conflict: \(conflict.name)"))
                
                let choice = InteractivePrompts.promptChoice(
                    "How to resolve?",
                    options: [
                        "Skip this automation",
                        "Rename to '\(conflict.name) (imported)'",
                        "Overwrite existing",
                        "Cancel import"
                    ],
                    display: { $0 }
                )
                
                switch choice {
                case "Skip this automation":
                    continue
                    
                case "Rename to '\(conflict.name) (imported)'":
                    var modified = conflict
                    modified.name = "\(conflict.name) (imported)"
                    modified.id = UUID().uuidString
                    resolved.append(modified)
                    
                case "Overwrite existing":
                    resolved.append(conflict)
                    
                case "Cancel import":
                    throw ImportExportError.cancelled
                    
                default:
                    continue
                }
            }
            
            return resolved
        }
    }
}

// MARK: - Import Strategy

enum ImportStrategy {
    case skip          // Skip conflicts
    case overwrite     // Overwrite existing
    case rename        // Rename imports
    case ask           // Ask user for each conflict
}

// MARK: - Errors

enum ImportExportError: LocalizedError {
    case automationNotFound(String)
    case invalidJSON
    case cancelled
    case fileNotFound
    case writeError
    
    var errorDescription: String? {
        switch self {
        case .automationNotFound(let id):
            return "Automation not found: \(id)"
        case .invalidJSON:
            return "Invalid JSON format"
        case .cancelled:
            return "Import cancelled by user"
        case .fileNotFound:
            return "File not found"
        case .writeError:
            return "Failed to write file"
        }
    }
}
