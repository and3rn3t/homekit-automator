// SocketClient.swift
// Handles communication with the HomeKitHelper via Unix domain socket.

import Foundation
import Logging

/// Client for communicating with the HomeKitHelper process over a Unix domain socket.
///
/// This actor encapsulates the IPC (inter-process communication) layer that enables the CLI (`homekitauto`
/// command) to communicate with the `HomeKitHelper` background process. The architecture follows a simple
/// request-response pattern over a Unix domain socket in the Application Support directory.
///
/// **IPC Architecture:**
/// The communication flow is: CLI Command → SocketClient → Unix Socket → HomeKitHelper
/// This allows the stateless CLI to delegate HomeKit operations to a persistent daemon process that maintains
/// HomeKit framework connections.
///
/// **Protocol:**
/// Communication uses JSON-NL (JSON Newline) format: each message is a JSON object followed by a single
/// newline character (`\n`). This allows for clean message framing on a streaming socket without needing
/// a separate length-prefix or terminator logic.
///
/// **Thread Safety:**
/// This type is an `actor`, which provides exclusive access to socket operations and ensures thread-safe
/// mutation. Since socket I/O is inherently serial and stateful, the actor model prevents concurrent calls
/// from interleaving socket operations (create → connect → send → receive), which would corrupt the protocol.

import HomeKitCore

actor SocketClient {
    static let socketPath = SocketConstants.defaultPath
    private let timeout: TimeInterval = 10.0

    /// Request message sent to the HomeKitHelper.
    ///
    /// Each request includes a unique ID to correlate responses, a command name, and optional parameters.
    /// This structure is JSON-encoded and terminated with a newline before transmission.
    struct Request: Codable {
        /// Unique identifier for this request (typically a UUID string).
        /// Used to match the response with its corresponding request when multiple commands are in flight.
        let id: String

        /// The command to execute (e.g., "get_scenes", "turn_on_accessory", "status").
        let command: String

        /// Optional command-specific parameters, with heterogeneous values (strings, ints, bools, etc.).
        let params: [String: AnyCodableValue]?

        /// Authentication token for verifying the client is authorized.
        let token: String?

        /// Protocol version for forward-compatibility detection.
        let version: Int?
    }

    /// Response message received from the HomeKitHelper.
    ///
    /// The HomeKitHelper responds to each request with a response that includes the matching request ID,
    /// a status ("ok" or "error"), optional data payload, and optional error message.
    struct Response: Codable {
        /// The request ID this response is answering. Must match the Request.id for this transaction.
        let id: String

        /// Status code: "ok" for successful execution, "error" for failures.
        let status: String

        /// The response data payload. May be a string, number, bool, array of scenes/accessories, etc.
        /// Structure depends on the specific command executed. Nil if the command produced no data.
        let data: AnyCodableValue?

        /// Human-readable error message if status is "error". Nil on success.
        let error: String?

        /// Convenience property: returns true if status is "ok".
        var isOk: Bool { status == "ok" }
    }

    /// Send a command to the HomeKitHelper and wait for a response.
    ///
    /// This method orchestrates the complete request-response lifecycle:
    /// 1. **Create**: Generates a unique request ID and builds a `Request` struct.
    /// 2. **Encode**: JSON-encodes the request and appends a newline delimiter.
    /// 3. **Socket Creation**: Creates a Unix domain socket (AF_UNIX, SOCK_STREAM).
    /// 4. **Connect**: Connects to the HomeKitHelper listening at the Application Support socket path.
    /// 5. **Send**: Transmits the JSON-NL encoded request in one or more calls to `send()`.
    /// 6. **Receive**: Reads the response in a loop with a 10-second timeout, accumulating data until
    ///    a newline delimiter is encountered.
    /// 7. **Decode**: JSON-decodes the response and verifies the request ID matches.
    /// 8. **Cleanup**: Automatically closes the socket via `defer`.
    ///
    /// - Parameters:
    ///   - command: The command to execute on the helper (e.g., "get_scenes", "turn_on_accessory").
    ///   - params: Optional command parameters as a dictionary with heterogeneous values.
    ///
    /// - Returns: The decoded `Response` from the helper.
    ///
    /// - Throws:
    ///   - `SocketError.connectionFailed` if socket creation or connection fails.
    ///   - `SocketError.sendFailed` if the request cannot be fully transmitted.
    ///   - `SocketError.noResponse` if no data is received before timeout.
    ///   - `SocketError.responseMismatch` if the response ID doesn't match the request ID.
    ///   - `DecodingError` if the response JSON cannot be decoded.
    func send(command: String, params: [String: AnyCodableValue]? = nil) async throws -> Response {
        let requestId = UUID().uuidString
        let token = SocketConstants.getOrCreateToken()
        Log.socket.debug("Preparing request", metadata: ["command": "\(command)", "requestId": "\(requestId)"])

        // Warn if legacy socket path still exists
        if FileManager.default.fileExists(atPath: SocketConstants.legacySocketPath) {
            Log.socket.warning("Legacy socket found at \(SocketConstants.legacySocketPath) — please remove it. Socket has moved to \(Self.socketPath)")
        }

        let request = Request(id: requestId, command: command, params: params, token: token,
                              version: SocketConstants.protocolVersion)

        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        var requestData = try encoder.encode(request)
        requestData.append(contentsOf: "\n".utf8)

        // Connect to Unix socket
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw SocketError.connectionFailed("Could not create socket")
        }
        defer { close(socket) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Self.socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            Log.socket.error("Connection failed", metadata: ["path": "\(Self.socketPath)"])
            throw SocketError.connectionFailed(
                "Could not connect to HomeKitHelper at \(Self.socketPath). " +
                "Is the HomeKit Automator app running?"
            )
        }
        Log.socket.debug("Connected to HomeKitHelper", metadata: ["path": "\(Self.socketPath)"])

        // Send request
        let bytesSent = requestData.withUnsafeBytes { buffer in
            Darwin.send(socket, buffer.baseAddress!, buffer.count, 0)
        }
        guard bytesSent == requestData.count else {
            Log.socket.error("Send failed", metadata: ["bytesSent": "\(bytesSent)", "expected": "\(requestData.count)"])
            throw SocketError.sendFailed("Failed to send request")
        }
        Log.socket.debug("Request sent", metadata: ["bytes": "\(bytesSent)", "command": "\(command)"])

        // Read response (with timeout)
        var responseData = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
        defer { buffer.deallocate() }

        // Set socket read timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        while true {
            let bytesRead = Darwin.recv(socket, buffer, 65536, 0)
            if bytesRead <= 0 { break }
            responseData.append(buffer, count: bytesRead)
            // Check for newline delimiter
            if responseData.last == UInt8(ascii: "\n") { break }
        }

        guard !responseData.isEmpty else {
            Log.socket.error("No response received", metadata: ["command": "\(command)"])
            throw SocketError.noResponse("No response from HomeKitHelper")
        }
        Log.socket.debug("Response received", metadata: ["bytes": "\(responseData.count)"])

        let decoder = JSONDecoder()
        let response = try decoder.decode(Response.self, from: responseData)

        guard response.id == requestId else {
            Log.socket.error("Response ID mismatch", metadata: ["expected": "\(requestId)", "got": "\(response.id)"])
            throw SocketError.responseMismatch("Response ID mismatch")
        }

        Log.socket.info("Command completed", metadata: ["command": "\(command)", "status": "\(response.status)"])
        return response
    }
}

// MARK: - Errors

/// Errors that can occur during IPC communication with the HomeKitHelper.
enum SocketError: LocalizedError {
    /// Thrown when the Unix domain socket cannot be created or when connection to the helper fails.
    /// Common causes: socket file descriptor creation failed, socket path does not exist, permission denied,
    /// or the HomeKitHelper is not running.
    case connectionFailed(String)

    /// Thrown when the full request cannot be transmitted to the socket.
    /// This occurs if `send()` syscall returns a count less than the request byte count,
    /// indicating incomplete transmission and an unrecoverable socket state.
    case sendFailed(String)

    /// Thrown when the socket read loop completes without receiving any data.
    /// This occurs when `recv()` returns 0 or an error, typically due to timeout (10 seconds)
    /// or the helper closing the connection prematurely.
    case noResponse(String)

    /// Thrown when the response JSON is successfully decoded but the `id` field does not match
    /// the `id` of the original request. This indicates a protocol violation or socket state corruption.
    case responseMismatch(String)

    /// Thrown when the response status is "error" and the helper included an error message.
    /// This represents a valid protocol exchange but an operation failure on the helper side
    /// (e.g., invalid command, missing accessory, HomeKit authorization failure).
    case helperError(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return msg
        case .sendFailed(let msg): return msg
        case .noResponse(let msg): return msg
        case .responseMismatch(let msg): return msg
        case .helperError(let msg): return msg
        }
    }
}
