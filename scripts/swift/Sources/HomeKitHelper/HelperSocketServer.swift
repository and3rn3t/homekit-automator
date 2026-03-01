// HelperSocketServer.swift
// Unix domain socket server that receives JSON commands from the CLI tool
// and dispatches them to the HomeKitManager.

import Foundation

/// GCD-based Unix domain socket server for HomeKit command processing.
///
/// ARCHITECTURE:
/// Uses Grand Central Dispatch (GCD) instead of async/NIO because:
/// - HomeKit operations must run on @MainActor (main thread)
/// - GCD integrates naturally with main dispatch queue and RunLoop
/// - Socket I/O is simple and synchronous; async runtime overhead is unnecessary
///
/// SOCKET PROTOCOL:
/// Listens on a Unix domain socket in ~/Library/Application Support/homekit-automator/ for newline-delimited JSON commands.
/// Each line is a complete JSON request; responses are sent back as JSON-NL.
class HelperSocketServer {
    /// Reference to the HomeKitManager that processes all commands
    private let homeKitManager: HomeKitManager
    /// Low-level socket file descriptor for Unix domain socket
    private var serverSocket: Int32 = -1
    /// Flag to signal the accept loop to stop
    private var isRunning = false
    /// Background GCD queue for accepting connections; doesn't block main thread
    private let queue = DispatchQueue(label: "com.homekitautomator.socket", qos: .userInitiated)

    init(homeKitManager: HomeKitManager) {
        self.homeKitManager = homeKitManager
    }

    /// Creates the socket, binds to the Application Support socket path with 0o600 permissions, and begins accepting connections.
    /// Accepts clients on a background GCD queue without blocking the main thread.
    /// - Returns: `true` if the server started successfully, `false` if socket/bind/listen failed.
    @discardableResult
    func start() -> Bool {
        let socketPath = SocketConstants.defaultPath

        // Warn about and clean up legacy socket path
        if FileManager.default.fileExists(atPath: SocketConstants.legacySocketPath) {
            let legacyMsg = "Legacy socket at \(SocketConstants.legacySocketPath) — remove it. Moved to \(socketPath)"
            print("[SocketServer] WARNING: \(legacyMsg)")
            unlink(SocketConstants.legacySocketPath)
        }

        // Remove existing socket file
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[SocketServer] ERROR: Could not create socket (errno: \(errno) \u{2014} \(String(cString: strerror(errno))))")
            return false
        }

        // Bind to path
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

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("[SocketServer] ERROR: Could not bind to \(socketPath) (errno: \(errno) \u{2014} \(String(cString: strerror(errno))))")
            return false
        }

        // Set socket permissions (owner only)
        chmod(socketPath, 0o600)

        // Listen
        guard listen(serverSocket, 5) == 0 else {
            print("[SocketServer] ERROR: Could not listen (errno: \(errno) \u{2014} \(String(cString: strerror(errno))))")
            return false
        }

        isRunning = true
        print("[SocketServer] Listening on \(socketPath)")

        // Accept connections in background
        queue.async { [weak self] in
            self?.acceptLoop()
        }
        return true
    }

    /// Stops the accept loop, closes the server socket, and removes the socket file.
    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(SocketConstants.defaultPath)
        print("[SocketServer] Stopped.")
    }

    // MARK: - Connection Handling

    /// Blocks in a loop accepting client connections.
    /// Each new client is dispatched to handleConnection on a global GCD queue.
    /// ACCEPT LOOP PATTERN:
    /// 1. accept() blocks waiting for a client
    /// 2. When a client connects, spawn handleConnection on a background queue
    /// 3. Loop continues immediately to accept the next client
    /// 4. Exits when isRunning becomes false or accept() returns an error
    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverSocket, sockPtr, &clientAddrLen)
                }
            }

            if clientSocket < 0 {
                if isRunning {
                    print("[SocketServer] Accept error: \(errno) \u{2014} \(String(cString: strerror(errno)))")
                }
                continue
            }

            // Handle each connection in its own queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleConnection(clientSocket)
            }
        }
    }

    /// Handles a single client connection: reads one JSON-NL message, dispatches the command, and sends response.
    /// STEPS:
    /// 1. Read JSON-NL message from socket (up to newline, timeout 30s)
    /// 2. Parse request JSON: {id, command, params, token, version}
    /// 3. Dispatch command to HomeKitManager via @MainActor continuation
    /// 4. Send JSON response back to client
    /// 5. Close socket
    ///
    /// Uses `withCheckedContinuation` to bridge the GCD background thread with
    /// the @MainActor HomeKit operations, avoiding the DispatchSemaphore anti-pattern
    /// which could cause thread starvation under high concurrency.
    private func handleConnection(_ clientSocket: Int32) {
        // Note: clientSocket is closed in the dispatchGroup.notify callback below,
        // NOT in a defer block, because the response is sent asynchronously.

        // Read until newline
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
        defer { buffer.deallocate() }

        // Set read timeout to prevent indefinite blocking
        var tv = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        while true {
            let bytesRead = recv(clientSocket, buffer, 65536, 0)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
            if data.last == UInt8(ascii: "\n") { break }
        }

        guard !data.isEmpty else {
            close(clientSocket)
            return
        }

        // Parse request
        struct Request: Codable {
            let id: String
            let command: String
            let params: [String: AnyCodableValue]?
            let token: String?
            let version: Int?
        }

        guard let request = try? JSONDecoder().decode(Request.self, from: data) else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            print("[SocketServer] ERROR: Could not decode request JSON: \(preview)")
            if let decodeError = (try? { () throws -> Request in try JSONDecoder().decode(Request.self, from: data) })() {
                _ = decodeError // unreachable, used to extract error
            }
            sendError(clientSocket, id: "unknown", message: "Invalid request JSON. Ensure request has 'id' (string) and 'command' (string) fields.")
            close(clientSocket)
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        print("[SocketServer] \u{2192} Received command: \(request.command) (id: \(request.id.prefix(8))...)")

        // Validate authentication token
        guard SocketConstants.validateToken(request.token) else {
            print("[SocketServer] Rejected unauthorized request for command: \(request.command)")
            sendError(clientSocket, id: request.id, message: "Unauthorized: invalid or missing authentication token")
            close(clientSocket)
            return
        }

        // Dispatch command to main actor and send response via callback.
        // Previous versions used DispatchGroup.wait() or DispatchSemaphore which block
        // GCD threads waiting for @MainActor work, risking thread-pool exhaustion under
        // concurrent connections. Instead, we use DispatchGroup.notify() to send the
        // response asynchronously when the MainActor work completes, freeing the GCD
        // thread immediately.
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        var responseData: [String: Any] = [:]
        var responseError: String?

        Task { @MainActor in
            defer { dispatchGroup.leave() }
            do {
                let result = try await self.dispatchCommand(
                    request.command, params: request.params
                )
                responseData = result.data
                responseError = result.error
            } catch {
                responseError = error.localizedDescription
            }
        }

        dispatchGroup.notify(queue: .global()) { [self] in
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            // Send response (and close socket) once MainActor work is done
            if let error = responseError {
                print("[SocketServer] \u{2190} Command \(request.command) failed (\(String(format: "%.1f", elapsed * 1000))ms): \(error)")
                self.sendError(clientSocket, id: request.id, message: error)
            } else {
                print("[SocketServer] \u{2190} Command \(request.command) completed (\(String(format: "%.1f", elapsed * 1000))ms)")
                self.sendSuccess(clientSocket, id: request.id, data: responseData)
            }
            close(clientSocket)
        }
    }

    // MARK: - Command Dispatch

    /// Dispatches a command to the appropriate HomeKitManager method.
    /// Returns both data and an optional error string; at most one will be populated.
    @MainActor
    private func dispatchCommand(
        _ command: String, params: [String: AnyCodableValue]?
    ) async throws -> (data: [String: Any], error: String?) {
        switch command {
        case "status":
            return (try await homeKitManager.getStatus(), nil)
        case "discover":
            return (try await homeKitManager.discover(), nil)
        case "get_device":
            let name = params?["name"]?.stringValue ?? ""
            return (try await homeKitManager.getDevice(nameOrUuid: name), nil)
        case "set_device":
            let name = params?["name"]?.stringValue ?? params?["uuid"]?.stringValue ?? ""
            let characteristic = params?["characteristic"]?.stringValue ?? ""
            let value = params?["value"]?.rawValue ?? ""
            return (try await homeKitManager.setDevice(
                nameOrUuid: name, characteristic: characteristic, value: value
            ), nil)
        case "list_rooms":
            let home = params?["home"]?.stringValue
            let rooms = try await homeKitManager.listRooms(homeName: home)
            return (["rooms": rooms], nil)
        case "list_scenes":
            let home = params?["home"]?.stringValue
            let scenes = try await homeKitManager.listScenes(homeName: home)
            return (["scenes": scenes], nil)
        case "trigger_scene":
            let name = params?["name"]?.stringValue ?? ""
            return (try await homeKitManager.triggerScene(nameOrUuid: name), nil)
        case "state_changes":
            let deviceFilter = params?["device"]?.stringValue
            let changes = homeKitManager.getStateChanges(deviceName: deviceFilter)
            return (["changes": changes, "count": changes.count], nil)
        case "subscribe":
            let deviceName = params?["device"]?.stringValue ?? ""
            if deviceName.isEmpty {
                return ([:], "Missing 'device' parameter for subscribe command")
            }
            return (homeKitManager.subscribe(deviceName: deviceName), nil)
        case "get_config":
            return (loadConfig(), nil)
        case "set_config":
            var config = loadConfig()
            if let home = params?["defaultHome"]?.stringValue { config["defaultHome"] = home }
            if let mode = params?["filterMode"]?.stringValue { config["filterMode"] = mode }
            saveConfig(config)
            return (config, nil)
        case "shutdown":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
            return (["status": "shutting_down"], nil)
        default:
            return ([:], "Unknown command: \(command)")
        }
    }

    // MARK: - Response Helpers
    //
    // Note: These use JSONSerialization (not Codable) because HomeKitManager returns
    // [String: Any] dictionaries from Apple's HomeKit APIs. The CLI side uses Codable
    // with AnyCodableValue to decode these responses. Both sides produce equivalent JSON;
    // the serialization boundary is at the socket protocol layer.

    private func sendSuccess(_ socket: Int32, id: String, data: [String: Any]) {
        let response: [String: Any] = [
            "id": id,
            "status": "ok",
            "data": data
        ]
        sendJSON(socket, response)
    }

    private func sendError(_ socket: Int32, id: String, message: String) {
        let response: [String: Any] = [
            "id": id,
            "status": "error",
            "error": message
        ]
        sendJSON(socket, response)
    }

    private func sendJSON(_ socket: Int32, _ object: [String: Any]) {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object)
        } catch {
            print("[SocketServer] ERROR: Failed to serialize response JSON: \(error.localizedDescription)")
            // Send a minimal error response so the client doesn't hang
            let fallback = "{\"status\":\"error\",\"error\":\"Internal: response serialization failed\"}\n"
            _ = fallback.withCString { ptr in
                Darwin.send(socket, ptr, strlen(ptr), 0)
            }
            return
        }
        var payload = data
        payload.append(contentsOf: "\n".utf8)
        payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var totalSent = 0
            let count = buffer.count
            while totalSent < count {
                let sent = Darwin.send(socket, baseAddress + totalSent, count - totalSent, 0)
                if sent <= 0 {
                    let errDesc = String(cString: strerror(errno))
                    print("[SocketServer] WARNING: send() failed after \(totalSent)/\(count) bytes (errno: \(errno) — \(errDesc))")
                    break
                }
                totalSent += sent
            }
        }
    }

    // MARK: - Config

    /// Path to config file in Application Support directory
    private var configPath: String {
        guard let dir = SocketConstants.appSupportDir else {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/homekit-automator/config.json").path
        }
        return dir.appendingPathComponent("config.json").path
    }

    /// Loads config from ~/Library/Application Support/homekit-automator/config.json or returns default if missing.
    /// Default config: {"filterMode": "all"}
    /// - Returns: Dictionary with persisted or default settings
    private func loadConfig() -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: configPath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["filterMode": "all"]
        }
        return dict
    }

    /// Persists config to ~/Library/Application Support/homekit-automator/config.json with pretty printing.
    /// Creates parent directories if needed; uses atomic writes to prevent corruption.
    /// Logs warnings on failure instead of silently swallowing errors.
    /// - Parameters:
    ///   - config: Configuration dictionary to persist
    private func saveConfig(_ config: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) else {
            print("[SocketServer] WARNING: Could not serialize config to JSON")
            return
        }
        let dir = (configPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            print("[SocketServer] WARNING: Could not create config directory at \(dir): \(error.localizedDescription)")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        } catch {
            print("[SocketServer] WARNING: Could not write config to \(configPath): \(error.localizedDescription)")
        }
    }
}
