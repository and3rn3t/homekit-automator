// SocketServer.swift
// Unix domain socket server for receiving commands from the main HomeKit Automator app.

import Foundation
import Darwin

/// Unix domain socket server that listens for JSON commands.
actor SocketServer {
    
    // MARK: - Properties
    
    private let socketPath: String
    private let homeKitManager: HomeKitManager
    private let automationEngine: AutomationEngine
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private var acceptTask: Task<Void, Never>?
    
    private let logger = HelperLogger.shared
    
    // MARK: - Init
    
    init(homeKitManager: HomeKitManager, automationEngine: AutomationEngine, socketPath: String? = nil) {
        self.homeKitManager = homeKitManager
        self.automationEngine = automationEngine
        self.socketPath = socketPath ?? SocketConstants.defaultPath
    }
    
    deinit {
        if serverSocket >= 0 {
            close(serverSocket)
        }
    }
    
    // MARK: - Lifecycle
    
    /// Starts the socket server and begins accepting connections.
    func start() async throws {
        guard !isRunning else { return }
        
        await logger.log("Starting socket server at \(socketPath)", level: .info)
        
        // Remove existing socket file if present
        if FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.removeItem(atPath: socketPath)
        }
        
        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw SocketError.createFailed
        }
        
        // Configure address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw SocketError.pathTooLong
        }
        
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }
        
        // Bind
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw SocketError.bindFailed
        }
        
        // Set permissions (owner only)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: socketPath)
        
        // Listen
        guard listen(serverSocket, 5) == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw SocketError.listenFailed
        }
        
        isRunning = true
        await logger.log("Socket server listening", level: .info)
        
        // Start accepting connections
        acceptTask = Task {
            await acceptConnections()
        }
    }
    
    /// Stops the socket server.
    func stop() async {
        guard isRunning else { return }
        
        await logger.log("Stopping socket server", level: .info)
        
        isRunning = false
        acceptTask?.cancel()
        acceptTask = nil
        
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        
        // Clean up socket file
        try? FileManager.default.removeItem(atPath: socketPath)
        
        await logger.log("Socket server stopped", level: .info)
    }
    
    // MARK: - Connection Handling
    
    private func acceptConnections() async {
        await logger.log("Accepting connections", level: .debug)
        
        while isRunning {
            // Accept (blocking call)
            let clientSocket = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [serverSocket] in
                    var addr = sockaddr_un()
                    var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                    
                    let client = withUnsafeMutablePointer(to: &addr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                            Darwin.accept(serverSocket, sockPtr, &addrLen)
                        }
                    }
                    
                    continuation.resume(returning: client)
                }
            }
            
            guard clientSocket >= 0, isRunning else {
                continue
            }
            
            // Handle connection in separate task
            Task {
                await handleConnection(clientSocket)
            }
        }
    }
    
    private func handleConnection(_ socket: Int32) async {
        defer { close(socket) }
        
        await logger.log("Client connected", level: .debug)
        
        // Set timeout
        var tv = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        
        // Read request
        var buffer = [UInt8](repeating: 0, count: 16384)
        let bytesRead = Darwin.recv(socket, &buffer, buffer.count, 0)
        
        guard bytesRead > 0 else {
            await logger.log("No data received from client", level: .warning)
            return
        }
        
        let data = Data(bytes: buffer, count: bytesRead)
        guard let requestString = String(data: data, encoding: .utf8) else {
            await logger.log("Invalid UTF-8 data received", level: .warning)
            return
        }
        
        // Process request
        let response = await handleRequest(requestString)
        
        // Send response
        var responseData = (response + "\n").data(using: .utf8)!
        responseData.withUnsafeBytes { ptr in
            _ = Darwin.send(socket, ptr.baseAddress!, ptr.count, 0)
        }
        
        await logger.log("Response sent to client", level: .debug)
    }
    
    // MARK: - Request Handling
    
    private func handleRequest(_ requestString: String) async -> String {
        do {
            guard let data = requestString.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
                throw SocketError.invalidRequest
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SocketError.invalidRequest
            }
            
            // Validate token
            guard let token = json["token"] as? String,
                  token == SocketConstants.getOrCreateToken() else {
                throw SocketError.invalidToken
            }
            
            // Extract command
            guard let command = json["command"] as? String else {
                throw SocketError.invalidRequest
            }
            
            await logger.log("Handling command: \(command)", level: .debug)
            
            // Route to handler
            let commandHandler = CommandHandler(
                homeKitManager: homeKitManager,
                automationEngine: automationEngine
            )
            
            let result = await commandHandler.handle(command: command)
            
            return result
            
        } catch {
            await logger.logError(error)
            return errorResponse(error)
        }
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
        
        return "{\"status\":\"error\",\"error\":\"Unknown error\"}"
    }
}

// MARK: - Errors

enum SocketError: LocalizedError {
    case createFailed
    case pathTooLong
    case bindFailed
    case listenFailed
    case invalidRequest
    case invalidToken
    
    var errorDescription: String? {
        switch self {
        case .createFailed: return "Failed to create socket"
        case .pathTooLong: return "Socket path is too long"
        case .bindFailed: return "Failed to bind socket"
        case .listenFailed: return "Failed to listen on socket"
        case .invalidRequest: return "Invalid request format"
        case .invalidToken: return "Invalid authentication token"
        }
    }
}
