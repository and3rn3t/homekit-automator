// ImportExport.swift
// Export and import automations as JSON files.

import Foundation

/// Import and export automation definitions.
struct ImportExport {
    
    let apiClient: HelperAPIClient
    
    // MARK: - Export
    
    /// Exports a single automation to a file.
    func exportAutomation(
        id: String,
        to outputPath: String
    ) async throws {
        Terminal.print(Terminal.spinner("Exporting automation..."))
        
        let automations = try await apiClient.listAutomations()
        guard let automation = automations.first(where: { $0.id == id }) else {
            throw ImportExportError.automationNotFound(id)
        }
        
        try exportAutomation(automation, to: outputPath)
        
        print("\u{001B}[1A\u{001B}[2K", terminator: "")
        Terminal.printSuccess("Exported to \(outputPath)")
    }
    
    /// Exports all automations to a file.
    func exportAll(to outputPath: String) async throws {
        Terminal.print(Terminal.spinner("Exporting all automations..."))
        
        let automations = try await apiClient.listAutomations()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(automations)
        let url = URL(fileURLWithPath: outputPath)
        try data.write(to: url, options: .atomic)
        
        print("\u{001B}[1A\u{001B}[2K", terminator: "")
        Terminal.printSuccess("Exported \(automations.count) automation(s) to \(outputPath)")
    }
    
    private func exportAutomation(
        _ automation: RegisteredAutomation,
        to outputPath: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(automation)
        let url = URL(fileURLWithPath: outputPath)
        try data.write(to: url, options: .atomic)
    }
    
    // MARK: - Import
    
    /// Imports automation(s) from a JSON file.
    func importAutomations(
        from inputPath: String,
        strategy: MergeStrategy = .ask
    ) async throws {
        Terminal.print(Terminal.spinner("Reading file..."))
        
        let url = URL(fileURLWithPath: inputPath)
        let data = try Data(contentsOf: url)
        
        print("\u{001B}[1A\u{001B}[2K", terminator: "")
        
        // Try to parse as single automation first
        let decoder = JSONDecoder()
        
        if let automation = try? decoder.decode(RegisteredAutomation.self, from: data) {
            try await importSingle(automation, strategy: strategy)
        } else if let automations = try? decoder.decode([RegisteredAutomation].self, from: data) {
            try await importMultiple(automations, strategy: strategy)
        } else if let definition = try? decoder.decode(AutomationDefinition.self, from: data) {
            try await importDefinition(definition)
        } else {
            throw ImportExportError.invalidFormat
        }
    }
    
    private func importSingle(
        _ automation: RegisteredAutomation,
        strategy: MergeStrategy
    ) async throws {
        Terminal.printInfo("Found 1 automation: \(automation.name)")
        
        // Check if automation with same ID exists
        let existing = try await apiClient.listAutomations()
        let conflict = existing.first(where: { $0.id == automation.id })
        
        if let conflict = conflict {
            Terminal.printWarning("Automation with ID '\(automation.id)' already exists")
            
            let action = await resolveConflict(
                existing: conflict,
                incoming: automation,
                strategy: strategy
            )
            
            switch action {
            case .skip:
                Terminal.printInfo("Skipped")
                return
            case .replace:
                Terminal.printInfo("Replacing existing automation")
                // Continue to create (will overwrite)
            case .rename:
                // Generate new ID
                var newAutomation = automation
                newAutomation.id = UUID().uuidString
                try await createAutomation(from: newAutomation)
                return
            }
        }
        
        try await createAutomation(from: automation)
    }
    
    private func importMultiple(
        _ automations: [RegisteredAutomation],
        strategy: MergeStrategy
    ) async throws {
        Terminal.printInfo("Found \(automations.count) automation(s)")
        
        var imported = 0
        var skipped = 0
        var errors = 0
        
        for automation in automations {
            do {
                try await importSingle(automation, strategy: strategy)
                imported += 1
            } catch ImportExportError.skipped {
                skipped += 1
            } catch {
                Terminal.printError("Failed to import \(automation.name): \(error.localizedDescription)")
                errors += 1
            }
        }
        
        Terminal.print("")
        Terminal.printSuccess("Imported \(imported) automation(s)")
        if skipped > 0 {
            Terminal.printInfo("Skipped \(skipped) automation(s)")
        }
        if errors > 0 {
            Terminal.printError("Failed to import \(errors) automation(s)")
        }
    }
    
    private func importDefinition(_ definition: AutomationDefinition) async throws {
        Terminal.printInfo("Found automation definition: \(definition.name)")
        
        // Create via API
        let response = try await apiClient.createAutomation(definition)
        
        if response.success {
            Terminal.printSuccess("Created automation: \(definition.name)")
        } else {
            throw ImportExportError.creationFailed(response.message ?? "Unknown error")
        }
    }
    
    private func createAutomation(from registered: RegisteredAutomation) async throws {
        // Convert to definition
        let definition = AutomationDefinition(
            name: registered.name,
            description: registered.description,
            trigger: registered.trigger,
            conditions: registered.conditions,
            actions: registered.actions,
            enabled: registered.enabled
        )
        
        let response = try await apiClient.createAutomation(definition)
        
        if response.success {
            Terminal.printSuccess("Imported: \(registered.name)")
        } else {
            throw ImportExportError.creationFailed(response.message ?? "Unknown error")
        }
    }
    
    // MARK: - Conflict Resolution
    
    private func resolveConflict(
        existing: RegisteredAutomation,
        incoming: RegisteredAutomation,
        strategy: MergeStrategy
    ) async -> ConflictAction {
        switch strategy {
        case .skip:
            return .skip
        case .replace:
            return .replace
        case .rename:
            return .rename
        case .ask:
            Terminal.print("\n" + Terminal.bold("Conflict detected"))
            Terminal.print("  Existing: \(existing.name) (created: \(existing.createdAt))")
            Terminal.print("  Incoming: \(incoming.name)")
            Terminal.print("")
            
            let choice = InteractivePrompts.promptChoice(
                "What would you like to do?",
                options: [
                    ConflictAction.skip,
                    ConflictAction.replace,
                    ConflictAction.rename
                ],
                display: { action in
                    switch action {
                    case .skip:
                        return "Skip - Keep existing automation"
                    case .replace:
                        return "Replace - Overwrite existing automation"
                    case .rename:
                        return "Rename - Import with new ID"
                    }
                }
            )
            
            return choice ?? .skip
        }
    }
}

// MARK: - Types

enum MergeStrategy {
    case skip      // Skip conflicting automations
    case replace   // Replace existing automations
    case rename    // Import with new ID
    case ask       // Ask for each conflict
}

enum ConflictAction {
    case skip
    case replace
    case rename
}

enum ImportExportError: LocalizedError {
    case automationNotFound(String)
    case invalidFormat
    case creationFailed(String)
    case skipped
    
    var errorDescription: String? {
        switch self {
        case .automationNotFound(let id):
            return "Automation not found: \(id)"
        case .invalidFormat:
            return "Invalid file format. Expected RegisteredAutomation or AutomationDefinition JSON"
        case .creationFailed(let message):
            return "Failed to create automation: \(message)"
        case .skipped:
            return "Skipped"
        }
    }
}
