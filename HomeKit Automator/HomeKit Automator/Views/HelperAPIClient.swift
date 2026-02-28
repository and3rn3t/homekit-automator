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
    
    /// Fetches the device map from HomeKitHelper.
    func getDeviceMap() async throws -> DeviceMapResponse {
        let response = try await sendCommand("device-map")
        return try JSONDecoder().decode(DeviceMapResponse.self, from: Data(response.utf8))
    }
    
    /// Lists all homes accessible to HomeKitHelper.
    func listHomes() async throws -> HomesResponse {
        let response = try await sendCommand("list-homes")
        return try JSONDecoder().decode(HomesResponse.self, from: Data(response.utf8))
    }
    
    // MARK: - Automation Management
    
    /// Creates a new automation from a definition.
    func createAutomation(_ definition: AutomationDefinition) async throws -> CreateAutomationResponse {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(definition)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw HelperAPIError.encodingFailed
        }
        
        let response = try await sendCommand("automation create --json '\(jsonString)'")
        return try JSONDecoder().decode(CreateAutomationResponse.self, from: Data(response.utf8))
    }
    
    /// Lists all registered automations.
    func listAutomations() async throws -> [RegisteredAutomation] {
        let response = try await sendCommand("automation list --json")
        return try JSONDecoder().decode([RegisteredAutomation].self, from: Data(response.utf8))
    }
    
    /// Enables an automation by ID.
    func enableAutomation(_ id: String) async throws {
        _ = try await sendCommand("automation enable \(id)")
    }
    
    /// Disables an automation by ID.
    func disableAutomation(_ id: String) async throws {
        _ = try await sendCommand("automation disable \(id)")
    }
    
    /// Deletes an automation by ID.
    func deleteAutomation(_ id: String) async throws {
        _ = try await sendCommand("automation delete \(id)")
    }
    
    /// Manually triggers an automation by ID.
    func triggerAutomation(_ id: String) async throws {
        _ = try await sendCommand("automation trigger \(id)")
    }
    
    // MARK: - Scenes
    
    /// Lists all scenes in the current home.
    func listScenes() async throws -> ScenesResponse {
        let response = try await sendCommand("scene list --json")
        return try JSONDecoder().decode(ScenesResponse.self, from: Data(response.utf8))
    }
    
    /// Activates a scene by name or UUID.
    func activateScene(_ identifier: String) async throws {
        _ = try await sendCommand("scene activate \(identifier)")
    }
    
    // MARK: - Status & Health
    
    /// Checks if the helper is responsive.
    func getStatus() async throws -> StatusResponse {
        let response = try await sendCommand("status")
        return try JSONDecoder().decode(StatusResponse.self, from: Data(response.utf8))
    }
    
    /// Returns the execution log.
    func getExecutionLog() async throws -> [AutomationLogEntry] {
        let response = try await sendCommand("automation log --json")
        return try JSONDecoder().decode([AutomationLogEntry].self, from: Data(response.utf8))
    }
    
    // MARK: - Socket Communication
    
    /// Sends a command to HomeKitHelper and returns the response string.
    private nonisolated func sendCommand(_ command: String) async throws -> String {
        let requestId = UUID().uuidString
        let token = SocketConstants.getOrCreateToken()
        let version = SocketConstants.protocolVersion
        
        let requestDict: [String: Any] = [
            "id": requestId,
            "command": command,
            "token": token,
            "version": version
        ]
        
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
                
                continuation.resume(returning: responseString)
            }
        }
    }
}

// MARK: - Response Types

struct DeviceMapResponse: Codable, Sendable {
    let homes: [HomeInfo]
}

struct HomeInfo: Codable, Sendable {
    let name: String
    let uuid: String
    let rooms: [RoomInfo]
    let accessories: [AccessoryInfo]
}

struct RoomInfo: Codable, Sendable {
    let name: String
    let uuid: String
}

struct AccessoryInfo: Codable, Sendable {
    let name: String
    let uuid: String
    let room: String?
    let category: String
    let characteristics: [CharacteristicInfo]
}

struct CharacteristicInfo: Codable, Sendable {
    let name: String
    let type: String
    let value: AnyCodableValue?
    let format: String?
}

struct HomesResponse: Codable, Sendable {
    let homes: [String]
}

struct CreateAutomationResponse: Codable, Sendable {
    let success: Bool
    let automationId: String?
    let message: String?
}

struct ScenesResponse: Codable, Sendable {
    let scenes: [SceneInfo]
}

struct SceneInfo: Codable, Sendable {
    let name: String
    let uuid: String
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
    
    var errorDescription: String? {
        switch self {
        case .socketCreationFailed: return "Could not create socket"
        case .connectionFailed: return "Could not connect to HomeKitHelper"
        case .sendFailed: return "Failed to send command"
        case .noResponse: return "No response from HomeKitHelper"
        case .encodingFailed: return "Failed to encode request"
        case .decodingFailed: return "Failed to decode response"
        case .helperNotRunning: return "HomeKitHelper is not running"
        }
    }
}
