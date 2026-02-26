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
/// - DispatchSemaphore bridges low-level GCD socket code with Swift async/await
///
/// SOCKET PROTOCOL:
/// Listens on /tmp/homekitauto.sock for newline-delimited JSON commands.
/// Each line is a complete JSON request; responses are sent back as JSON-NL.
class HelperSocketServer {
    private let socketPath = "/tmp/homekitauto.sock"
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

    /// Creates the socket, binds to /tmp/homekitauto.sock with 0o600 permissions, and begins accepting connections.
    /// Accepts clients on a background GCD queue without blocking the main thread.
    func start() {
        // Remove existing socket file
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[SocketServer] ERROR: Could not create socket")
            return
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
            print("[SocketServer] ERROR: Could not bind to \(socketPath)")
            return
        }

        // Set socket permissions (owner only)
        chmod(socketPath, 0o600)

        // Listen
        guard listen(serverSocket, 5) == 0 else {
            print("[SocketServer] ERROR: Could not listen")
            return
        }

        isRunning = true
        print("[SocketServer] Listening on \(socketPath)")

        // Accept connections in background
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    /// Stops the accept loop, closes the server socket, and removes the socket file.
    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(socketPath)
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
                    print("[SocketServer] Accept error: \(errno)")
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
    /// 2. Parse request JSON: {id, command, params}
    /// 3. Dispatch command to HomeKitManager via @MainActor Task
    /// 4. Wait for response using DispatchSemaphore
    /// 5. Send JSON response back to client
    /// 6. Close socket
    ///
    /// The semaphore pattern ensures the response is fully prepared before the socket closes,
    /// even though command execution happens asynchronously on the main thread.
    private func handleConnection(_ clientSocket: Int32) {
        defer { close(clientSocket) }

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

        guard !data.isEmpty else { return }

        // Parse request
        struct Request: Codable {
            let id: String
            let command: String
            let params: [String: AnyCodableValue]?
        }

        guard let request = try? JSONDecoder().decode(Request.self, from: data) else {
            sendError(clientSocket, id: "unknown", message: "Invalid request JSON")
            return
        }

        // Dispatch command to main thread and wait for response using semaphore
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: [String: Any] = [:]
        var responseError: String?

        /// SEMAPHORE-BASED ASYNC DISPATCH PATTERN:
        /// 1. Create a DispatchSemaphore to block handleConnection until the async Task completes
        /// 2. Task { @MainActor in ... } ensures all HomeKitManager operations run on main thread
        /// 3. semaphore.signal() at the end unblocks the calling thread
        /// 4. semaphore.wait() below blocks until signal() is called
        /// This allows socket I/O (on a background queue) to coordinate with main-thread-only HomeKit operations.
        Task { @MainActor in
            do {
                switch request.command {
                /// COMMAND DISPATCH:

                /// "status": Returns overall HomeKit status (connected, homes, automation count)
                case "status":
                    responseData = await self.homeKitManager.getStatus()

                /// "discover": Enumerates all homes, rooms, accessories, characteristics, and scenes
                case "discover":
                    responseData = await self.homeKitManager.discover()

                /// "get_device": Retrieves all characteristics (state) of a named or UUID accessory
                case "get_device":
                    let name = request.params?["name"]?.stringValue ?? ""
                    responseData = try await self.homeKitManager.getDevice(nameOrUuid: name)

                /// "set_device": Writes a single characteristic value on a device
                case "set_device":
                    let name = request.params?["name"]?.stringValue ??
                               request.params?["uuid"]?.stringValue ?? ""
                    let characteristic = request.params?["characteristic"]?.stringValue ?? ""
                    let value = request.params?["value"]?.rawValue ?? ""
                    responseData = try await self.homeKitManager.setDevice(
                        nameOrUuid: name,
                        characteristic: characteristic,
                        value: value
                    )

                /// "list_rooms": Lists all rooms across all homes (or filtered by homeName)
                case "list_rooms":
                    let home = request.params?["home"]?.stringValue
                    let rooms = await self.homeKitManager.listRooms(homeName: home)
                    responseData = ["rooms": rooms]

                /// "list_scenes": Lists all scenes (action sets) across all homes (or filtered by homeName)
                case "list_scenes":
                    let home = request.params?["home"]?.stringValue
                    let scenes = await self.homeKitManager.listScenes(homeName: home)
                    responseData = ["scenes": scenes]

                /// "trigger_scene": Executes a scene by name or UUID
                case "trigger_scene":
                    let name = request.params?["name"]?.stringValue ?? ""
                    responseData = try await self.homeKitManager.triggerScene(nameOrUuid: name)

                /// "state_changes": Returns recent device state changes from the circular buffer
                case "state_changes":
                    let deviceFilter = request.params?["device"]?.stringValue
                    let changes = self.homeKitManager.getStateChanges(deviceName: deviceFilter)
                    responseData = [
                        "changes": changes,
                        "count": changes.count
                    ]

                /// "subscribe": Subscribes to state change notifications for a specific device
                case "subscribe":
                    let deviceName = request.params?["device"]?.stringValue ?? ""
                    if deviceName.isEmpty {
                        responseError = "Missing 'device' parameter for subscribe command"
                    } else {
                        responseData = self.homeKitManager.subscribe(deviceName: deviceName)
                    }

                /// "get_config": Returns persisted config (filterMode, defaultHome, etc.)
                case "get_config":
                    responseData = self.loadConfig()

                /// "set_config": Updates config values (filterMode, defaultHome) and persists to ~/.config/homekit-automator/config.json
                case "set_config":
                    // Update config values
                    var config = self.loadConfig()
                    if let home = request.params?["defaultHome"]?.stringValue {
                        config["defaultHome"] = home
                    }
                    if let mode = request.params?["filterMode"]?.stringValue {
                        config["filterMode"] = mode
                    }
                    self.saveConfig(config)
                    responseData = config

                /// "shutdown": Signals the app to exit (for graceful process termination)
                case "shutdown":
                    responseData = ["status": "shutting_down"]
                    // Exit after responding
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        exit(0)
                    }

                default:
                    responseError = "Unknown command: \(request.command)"
                }
            } catch {
                responseError = error.localizedDescription
            }
            semaphore.signal()
        }

        semaphore.wait()

        // Send response
        if let error = responseError {
            sendError(clientSocket, id: request.id, message: error)
        } else {
            sendSuccess(clientSocket, id: request.id, data: responseData)
        }
    }

    // MARK: - Response Helpers

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
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(contentsOf: "\n".utf8)
        data.withUnsafeBytes { buffer in
            _ = send(socket, buffer.baseAddress!, buffer.count, 0)
        }
    }

    // MARK: - Config

    /// Path to config file: ~/.config/homekit-automator/config.json
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/homekit-automator/config.json").path

    /// Loads config from ~/.config/homekit-automator/config.json or returns default if missing.
    /// Default config: {"filterMode": "all"}
    /// - Returns: Dictionary with persisted or default settings
    private func loadConfig() -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: configPath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["filterMode": "all"]
        }
        return dict
    }

    /// Persists config to ~/.config/homekit-automator/config.json with pretty printing.
    /// Creates parent directories if needed; uses atomic writes to prevent corruption.
    /// - Parameters:
    ///   - config: Configuration dictionary to persist
    private func saveConfig(_ config: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) else { return }
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
    }
}


