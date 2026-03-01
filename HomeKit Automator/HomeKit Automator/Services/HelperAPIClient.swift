// HelperAPIClient.swift
// Client for communicating with HomeKitHelper via Unix domain socket.
// Provides async/await APIs for automation commands, device queries, and status checks.

import Foundation

/// Client for sending commands to HomeKitHelper and receiving responses.
@MainActor
final class HelperAPIClient {
    
    // MARK: - Singleton
    
    static let shared = HelperAPIClient()
    
    // MARK: - Properties
    
    private let socketPath: String
    private let timeout: TimeInterval = 30.0 // 30 second timeout for long operations
    
    // MARK: - Init
    
    init(socketPath: String? = nil) {
        self.socketPath = socketPath ?? SocketConstants.defaultPath
    }
    
    // MARK: - Device Management
    
    /// Fetches the full device discovery map from HomeKitHelper.
    func getDeviceMap() async throws -> DeviceMapResponse {
        let response = try await sendCommand("discover")
        return try JSONDecoder().decode(DeviceMapResponse.self, from: Data(response.utf8))
    }
    
    /// Gets the current state of a specific device by name or UUID.
    func getDevice(nameOrUuid: String) async throws -> String {
        return try await sendCommand("get_device", params: ["name": .string(nameOrUuid)])
    }
    
    /// Sets a device characteristic value.
    func setDevice(nameOrUuid: String, characteristic: String, value: AnyCodableValue) async throws -> String {
        return try await sendCommand("set_device", params: [
            "name": .string(nameOrUuid),
            "characteristic": .string(characteristic),
            "value": value
        ])
    }
    
    // MARK: - Room & Scene Queries
    
    /// Lists all rooms, optionally filtered by home name.
    func listRooms(homeName: String? = nil) async throws -> String {
        var params: [String: AnyCodableValue] = [:]
        if let home = homeName {
            params["home"] = .string(home)
        }
        return try await sendCommand("list_rooms", params: params.isEmpty ? nil : params)
    }
    
    /// Lists all scenes in the current home.
    func listScenes(homeName: String? = nil) async throws -> ScenesResponse {
        var params: [String: AnyCodableValue] = [:]
        if let home = homeName {
            params["home"] = .string(home)
        }
        let response = try await sendCommand("list_scenes", params: params.isEmpty ? nil : params)
        return try JSONDecoder().decode(ScenesResponse.self, from: Data(response.utf8))
    }
    
    /// Activates a scene by name or UUID.
    func activateScene(_ identifier: String) async throws {
        _ = try await sendCommand("trigger_scene", params: ["name": .string(identifier)])
    }
    
    // MARK: - Status & Health
    
    /// Checks if the helper is responsive.
    func getStatus() async throws -> StatusResponse {
        let response = try await sendCommand("status")
        return try JSONDecoder().decode(StatusResponse.self, from: Data(response.utf8))
    }
    
    // MARK: - State Changes
    
    /// Returns recent device state changes, optionally filtered by device name.
    func getStateChanges(deviceName: String? = nil) async throws -> String {
        var params: [String: AnyCodableValue] = [:]
        if let device = deviceName {
            params["device"] = .string(device)
        }
        return try await sendCommand("state_changes", params: params.isEmpty ? nil : params)
    }
    
    /// Subscribes to state change notifications for a specific device.
    func subscribe(deviceName: String) async throws -> String {
        return try await sendCommand("subscribe", params: ["device": .string(deviceName)])
    }
    
    // MARK: - Config
    
    /// Gets the current helper configuration.
    func getConfig() async throws -> String {
        return try await sendCommand("get_config")
    }
    
    /// Updates helper configuration values.
    func setConfig(defaultHome: String? = nil, filterMode: String? = nil) async throws -> String {
        var params: [String: AnyCodableValue] = [:]
        if let home = defaultHome {
            params["defaultHome"] = .string(home)
        }
        if let mode = filterMode {
            params["filterMode"] = .string(mode)
        }
        return try await sendCommand("set_config", params: params.isEmpty ? nil : params)
    }
    
    /// Signals the helper to shut down gracefully.
    func shutdown() async throws {
        _ = try await sendCommand("shutdown")
    }
    
    // MARK: - Automation Execution
    
    /// Executes an automation's actions by sending device/scene commands to the helper.
    ///
    /// Automation CRUD is handled by `AutomationStore` (shared on-disk registry).
    /// This method only executes the runtime actions via the HomeKitHelper bridge.
    func triggerAutomation(_ automationId: String, store: AutomationStore? = nil) async throws {
        // Load from the shared store, or read from disk directly
        let automation: RegisteredAutomation?
        if let store = store {
            automation = store.automations.first { $0.id == automationId }
        } else {
            // Read directly from disk (same path as AutomationStore)
            let configDir = SocketConstants.appSupportDir ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/homekit-automator")
            let registryPath = configDir.appendingPathComponent("automations.json")
            let data: Data
            do {
                data = try Data(contentsOf: registryPath)
            } catch {
                throw HelperAPIError.serverError("Could not read automations registry: \(error.localizedDescription)")
            }
            do {
                let automations = try JSONDecoder().decode([RegisteredAutomation].self, from: data)
                automation = automations.first { $0.id == automationId }
            } catch {
                throw HelperAPIError.serverError("Automations registry is corrupt: \(error.localizedDescription)")
            }
        }
        
        guard let automation = automation else {
            throw HelperAPIError.serverError("Automation not found: \(automationId)")
        }
        
        // Execute each action sequentially
        for action in automation.actions {
            if action.delaySeconds > 0 {
                try await Task.sleep(for: .seconds(action.delaySeconds))
            }
            
            if let sceneName = action.sceneName, !sceneName.isEmpty {
                try await activateScene(sceneName)
            } else {
                _ = try await setDevice(
                    nameOrUuid: action.deviceName,
                    characteristic: action.characteristic,
                    value: action.value
                )
            }
        }
    }
    
    /// Creates an automation by persisting it to the shared registry on disk.
    ///
    /// This writes directly to the same `automations.json` file used by the CLI
    /// and `AutomationStore`. Returns a response indicating success.
    func createAutomation(_ definition: AutomationDefinition) async throws -> CreateAutomationResponse {
        let configDir = SocketConstants.appSupportDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/homekit-automator")
        let registryPath = configDir.appendingPathComponent("automations.json")
        
        // Load existing automations
        var automations: [RegisteredAutomation] = []
        if let data = try? Data(contentsOf: registryPath) {
            do {
                automations = try JSONDecoder().decode([RegisteredAutomation].self, from: data)
            } catch {
                // Registry exists but contains corrupt JSON — back it up instead of silently discarding
                let backupPath = registryPath.deletingPathExtension()
                    .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: registryPath, to: backupPath)
                print("[HelperAPIClient] WARNING: Corrupt automations registry backed up to \(backupPath.lastPathComponent). Decode error: \(error.localizedDescription)")
                throw HelperAPIError.serverError("Automations registry is corrupt (backed up). Decode error: \(error.localizedDescription)")
            }
        }
        
        // Check for duplicate name
        if automations.contains(where: { $0.name.lowercased() == definition.name.lowercased() }) {
            return CreateAutomationResponse(success: false, automationId: nil,
                                           message: "An automation named '\(definition.name)' already exists")
        }
        
        // Create registered automation
        let newId = UUID().uuidString
        let registered = RegisteredAutomation(
            id: newId,
            name: definition.name,
            description: definition.description,
            trigger: definition.trigger,
            conditions: definition.conditions,
            actions: definition.actions,
            enabled: definition.enabled ?? true,
            shortcutName: "HKA-\(definition.name.replacingOccurrences(of: " ", with: "-"))",
            createdAt: sharedISO8601Formatter.string(from: Date())
        )
        
        automations.append(registered)
        
        // Persist atomically
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(automations)
        try data.write(to: registryPath, options: .atomic)
        
        return CreateAutomationResponse(success: true, automationId: newId, message: nil)
    }
    
    // MARK: - Socket Communication
    
    /// Sends a structured command to HomeKitHelper and returns the response string.
    ///
    /// Commands and params must match the HelperSocketServer dispatch table:
    /// - "status", "discover", "get_device", "set_device", "list_rooms",
    ///   "list_scenes", "trigger_scene", "state_changes", "subscribe",
    ///   "get_config", "set_config", "shutdown"
    ///
    /// - Parameters:
    ///   - command: Structured command name (e.g., "discover", "set_device")
    ///   - params: Optional typed parameters dictionary
    /// - Returns: Response JSON string from the helper
    private func sendCommand(_ command: String, params: [String: AnyCodableValue]? = nil) async throws -> String {
        let requestId = UUID().uuidString
        let token = SocketConstants.getOrCreateToken()
        let version = SocketConstants.protocolVersion
        
        // Build a Codable request matching the HelperSocketServer's Request struct
        var requestDict: [String: Any] = [
            "id": requestId,
            "command": command,
            "token": token,
            "version": version
        ]
        
        // Encode params via AnyCodableValue for type-safe serialization
        if let params = params {
            let encoder = JSONEncoder()
            if let paramsData = try? encoder.encode(params),
               let paramsObj = try? JSONSerialization.jsonObject(with: paramsData) {
                requestDict["params"] = paramsObj
            }
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestDict)
        guard let json = String(data: jsonData, encoding: .utf8) else {
            throw HelperAPIError.encodingFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [socketPath, timeout] in
                let sock = socket(AF_UNIX, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    continuation.resume(throwing: HelperAPIError.socketCreationFailed)
                    return
                }
                defer { close(sock) }
                
                // Set timeout
                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                
                // Connect
                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                let pathBytes = socketPath.utf8CString
                withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                        for (i, byte) in pathBytes.enumerated() {
                            dest[i] = byte
                        }
                    }
                }
                
                let connectResult = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        Darwin.connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                
                guard connectResult == 0 else {
                    continuation.resume(throwing: HelperAPIError.connectionFailed)
                    return
                }
                
                // Send
                var message = json + "\n"
                let sent = message.withUTF8 { buffer in
                    Darwin.send(sock, buffer.baseAddress!, buffer.count, 0)
                }
                guard sent == message.utf8.count else {
                    continuation.resume(throwing: HelperAPIError.sendFailed)
                    return
                }
                
                // Receive
                var responseData = Data()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 16384)
                defer { buf.deallocate() }
                
                while true {
                    let bytesRead = Darwin.recv(sock, buf, 16384, 0)
                    if bytesRead <= 0 { break }
                    responseData.append(buf, count: bytesRead)
                    // Check for newline terminator
                    if responseData.last == UInt8(ascii: "\n") { break }
                }
                
                guard !responseData.isEmpty,
                      let responseString = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    continuation.resume(throwing: HelperAPIError.noResponse)
                    return
                }
                
                // Unwrap the server envelope: {"id": ..., "status": "ok"|"error", "data": {...}, "error": "..."}
                // Return just the "data" portion as JSON string for callers to decode.
                guard let envelope = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                    continuation.resume(returning: responseString)
                    return
                }
                
                if let errorMsg = envelope["error"] as? String, envelope["status"] as? String == "error" {
                    continuation.resume(throwing: HelperAPIError.serverError(errorMsg))
                    return
                }
                
                if let data = envelope["data"] {
                    if let dataJSON = try? JSONSerialization.data(withJSONObject: data),
                       let dataString = String(data: dataJSON, encoding: .utf8) {
                        continuation.resume(returning: dataString)
                    } else {
                        continuation.resume(returning: responseString)
                    }
                } else {
                    continuation.resume(returning: responseString)
                }
            }
        }
    }
}

// MARK: - Response Types

/// Wraps the full discovery response from the "discover" command.
struct DeviceMapResponse: Codable, Sendable {
    let homes: [HomeInfo]?
    let accessories: [AccessoryInfo]?
    let rooms: [[String: String]]?
    let scenes: [[String: String]]?
}

struct HomeInfo: Codable, Sendable {
    let name: String
    let uuid: String
    let rooms: [RoomInfo]?
    let accessories: [AccessoryInfo]?
}

struct RoomInfo: Codable, Sendable {
    let name: String
    let uuid: String
}

struct AccessoryInfo: Codable, Sendable {
    let name: String
    let uuid: String
    let room: String?
    let category: String?
    let characteristics: [CharacteristicInfo]?
}

struct CharacteristicInfo: Codable, Sendable {
    let name: String
    let type: String?
    let value: AnyCodableValue?
    let format: String?
}

struct ScenesResponse: Codable, Sendable {
    let scenes: [SceneInfo]
}

struct SceneInfo: Codable, Sendable {
    let name: String
    let uuid: String
}

struct CreateAutomationResponse: Codable, Sendable {
    let success: Bool
    let automationId: String?
    let message: String?
}

struct StatusResponse: Codable, Sendable {
    let status: String
    let version: String?
    let uptime: TimeInterval?
}

// MARK: - Errors

enum HelperAPIError: LocalizedError {
    case socketCreationFailed
    case connectionFailed
    case sendFailed
    case noResponse
    case encodingFailed
    case decodingFailed
    case helperNotRunning
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .socketCreationFailed: return "Could not create socket"
        case .connectionFailed: return "Could not connect to HomeKitHelper"
        case .sendFailed: return "Failed to send command"
        case .noResponse: return "No response from HomeKitHelper"
        case .encodingFailed: return "Failed to encode request"
        case .decodingFailed: return "Failed to decode response"
        case .helperNotRunning: return "HomeKitHelper is not running"
        case .serverError(let message): return "HomeKitHelper error: \(message)"
        }
    }
}
