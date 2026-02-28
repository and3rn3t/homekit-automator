// CommandHandler.swift
// Routes socket commands to appropriate services and formats responses.

import Foundation

/// Handles incoming commands from the socket server and routes them to services.
actor CommandHandler {
    
    private let homeKitManager: HomeKitManager
    private let automationEngine: AutomationEngine
    private let logger = HelperLogger.shared
    
    init(homeKitManager: HomeKitManager, automationEngine: AutomationEngine) {
        self.homeKitManager = homeKitManager
        self.automationEngine = automationEngine
    }
    
    /// Handles a command and returns a JSON response string.
    func handle(command: String) async -> String {
        do {
            // Parse command (format: "command arg1 arg2 --flag value")
            let parts = parseCommand(command)
            let cmd = parts.command
            let args = parts.args
            let flags = parts.flags
            
            // Route to appropriate handler
            let result: Any
            
            switch cmd {
            // Status & Health
            case "status":
                result = await handleStatus()
                
            case "shutdown":
                result = await handleShutdown()
                
            // Device Management
            case "device-map":
                result = try await homeKitManager.getDeviceMap()
                
            case "list-homes":
                result = try await homeKitManager.listHomes()
                
            case "device":
                guard args.count > 0 else { throw CommandError.missingArguments }
                result = try await handleDeviceCommand(args[0], args: Array(args.dropFirst()), flags: flags)
                
            // Scene Management
            case "scene":
                guard args.count > 0 else { throw CommandError.missingArguments }
                result = try await handleSceneCommand(args[0], args: Array(args.dropFirst()), flags: flags)
                
            // Automation Management
            case "automation":
                guard args.count > 0 else { throw CommandError.missingArguments }
                result = try await handleAutomationCommand(args[0], args: Array(args.dropFirst()), flags: flags)
                
            default:
                throw CommandError.unknownCommand(cmd)
            }
            
            // Format successful response
            return successResponse(result)
            
        } catch {
            await logger.logError(error)
            return errorResponse(error)
        }
    }
    
    // MARK: - Command Parsing
    
    private struct ParsedCommand {
        let command: String
        let args: [String]
        let flags: [String: String]
    }
    
    private func parseCommand(_ command: String) -> ParsedCommand {
        var parts = command.split(separator: " ").map(String.init)
        guard !parts.isEmpty else {
            return ParsedCommand(command: "", args: [], flags: [:])
        }
        
        let cmd = parts.removeFirst()
        var args: [String] = []
        var flags: [String: String] = [:]
        
        var i = 0
        while i < parts.count {
            let part = parts[i]
            
            if part.hasPrefix("--") {
                // Flag with value
                let flagName = String(part.dropFirst(2))
                if i + 1 < parts.count && !parts[i + 1].hasPrefix("--") {
                    flags[flagName] = parts[i + 1]
                    i += 2
                } else {
                    flags[flagName] = "true"
                    i += 1
                }
            } else {
                // Regular argument
                args.append(part)
                i += 1
            }
        }
        
        return ParsedCommand(command: cmd, args: args, flags: flags)
    }
    
    // MARK: - Status Commands
    
    private func handleStatus() async -> [String: Any] {
        let uptime = ProcessInfo.processInfo.systemUptime
        return [
            "status": "ok",
            "version": "1.0.0",
            "uptime": uptime,
            "homeKit": await homeKitManager.isAuthorized() ? "authorized" : "not_authorized"
        ]
    }
    
    private func handleShutdown() async -> [String: String] {
        await logger.log("Shutdown requested", level: .info)
        
        // Give time to send response before exiting
        Task {
            try? await Task.sleep(for: .seconds(1))
            exit(0)
        }
        
        return ["status": "shutting_down"]
    }
    
    // MARK: - Device Commands
    
    private func handleDeviceCommand(_ subcommand: String, args: [String], flags: [String: String]) async throws -> Any {
        switch subcommand {
        case "list":
            return try await homeKitManager.listDevices(home: flags["home"])
            
        case "get":
            guard let deviceId = args.first else { throw CommandError.missingArguments }
            return try await homeKitManager.getDevice(uuid: deviceId)
            
        case "set":
            guard args.count >= 3 else { throw CommandError.missingArguments }
            let deviceId = args[0]
            let characteristic = args[1]
            let value = args[2]
            try await homeKitManager.setCharacteristic(deviceUUID: deviceId, characteristic: characteristic, value: parseValue(value))
            return ["status": "success"]
            
        default:
            throw CommandError.unknownSubcommand(subcommand)
        }
    }
    
    // MARK: - Scene Commands
    
    private func handleSceneCommand(_ subcommand: String, args: [String], flags: [String: String]) async throws -> Any {
        switch subcommand {
        case "list":
            return try await homeKitManager.listScenes(home: flags["home"])
            
        case "activate":
            guard let sceneName = args.first else { throw CommandError.missingArguments }
            try await homeKitManager.activateScene(name: sceneName)
            return ["status": "success", "scene": sceneName]
            
        default:
            throw CommandError.unknownSubcommand(subcommand)
        }
    }
    
    // MARK: - Automation Commands
    
    private func handleAutomationCommand(_ subcommand: String, args: [String], flags: [String: String]) async throws -> Any {
        switch subcommand {
        case "create":
            guard let jsonString = flags["json"] else {
                throw CommandError.missingArguments
            }
            return try await automationEngine.createAutomation(from: jsonString)
            
        case "list":
            return try await automationEngine.listAutomations()
            
        case "get":
            guard let id = args.first else { throw CommandError.missingArguments }
            return try await automationEngine.getAutomation(id: id)
            
        case "enable":
            guard let id = args.first else { throw CommandError.missingArguments }
            try await automationEngine.enableAutomation(id: id)
            return ["status": "success", "id": id, "enabled": true]
            
        case "disable":
            guard let id = args.first else { throw CommandError.missingArguments }
            try await automationEngine.disableAutomation(id: id)
            return ["status": "success", "id": id, "enabled": false]
            
        case "delete":
            guard let id = args.first else { throw CommandError.missingArguments }
            try await automationEngine.deleteAutomation(id: id)
            return ["status": "success", "id": id, "deleted": true]
            
        case "trigger":
            guard let id = args.first else { throw CommandError.missingArguments }
            try await automationEngine.triggerAutomation(id: id)
            return ["status": "success", "id": id, "triggered": true]
            
        case "log":
            return try await automationEngine.getExecutionLog()
            
        default:
            throw CommandError.unknownSubcommand(subcommand)
        }
    }
    
    // MARK: - Helpers
    
    private func parseValue(_ string: String) -> Any {
        // Try bool
        if string.lowercased() == "true" { return true }
        if string.lowercased() == "false" { return false }
        
        // Try int
        if let int = Int(string) { return int }
        
        // Try double
        if let double = Double(string) { return double }
        
        // Default to string
        return string
    }
    
    private func successResponse(_ result: Any) -> String {
        let dict: [String: Any] = ["status": "success", "result": result]
        
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        
        return "{\"status\":\"success\"}"
    }
    
    private func errorResponse(_ error: Error) -> String {
        let dict: [String: Any] = [
            "status": "error",
            "error": error.localizedDescription
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        
        return "{\"status\":\"error\"}"
    }
}

// MARK: - Errors

enum CommandError: LocalizedError {
    case unknownCommand(String)
    case unknownSubcommand(String)
    case missingArguments
    case invalidArguments
    
    var errorDescription: String? {
        switch self {
        case .unknownCommand(let cmd):
            return "Unknown command: \(cmd)"
        case .unknownSubcommand(let sub):
            return "Unknown subcommand: \(sub)"
        case .missingArguments:
            return "Missing required arguments"
        case .invalidArguments:
            return "Invalid arguments"
        }
    }
}
