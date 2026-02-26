// HelperManager.swift
// Manages the lifecycle of the HomeKitHelper process: launch, monitor, stop, and auto-restart.

import AppKit
import Foundation
import HomeKitCore

/// Status of the HomeKitHelper companion process.
enum HelperStatus: String, Sendable {
    case running
    case stopped
    case error
    case restarting
}

/// Manages the HomeKitHelper companion process that provides HomeKit framework access.
///
/// Responsibilities:
/// - Launch/stop the helper app via NSWorkspace
/// - Periodic health checks via Unix domain socket
/// - Auto-restart with a sliding window limiter (max 5 restarts per 15 minutes)
@Observable
@MainActor
final class HelperManager {

    // MARK: - Published State

    /// Whether the helper process is currently running and responsive.
    private(set) var isHelperRunning: Bool = false

    /// Current status of the helper process.
    private(set) var helperStatus: HelperStatus = .stopped

    // MARK: - Configuration

    /// Maximum number of automatic restarts allowed within the sliding window.
    var maxRestarts: Int = 5

    /// Sliding window duration for restart limiting (15 minutes).
    private let restartWindowDuration: TimeInterval = 15 * 60

    /// Socket path used for health-check pings (defaults to Application Support directory).
    var socketPath: String = SocketConstants.defaultPath

    // MARK: - Internal State

    /// Timestamps of recent automatic restarts, used for sliding-window rate limiting.
    private var restartTimestamps: [Date] = []

    /// Bundle identifier for the HomeKitHelper companion app.
    private let helperBundleIdentifier = "com.homekit-automator.HomeKitHelper"

    /// Name of the helper app bundle.
    private let helperAppName = "HomeKitHelper.app"

    // MARK: - Lifecycle

    /// Launches the HomeKitHelper companion app.
    ///
    /// The helper is located adjacent to the main app bundle. If it's already running
    /// (detected by bundle identifier), this method updates state without launching a
    /// second instance.
    func launchHelper() async {
        helperStatus = .restarting

        // Check if already running
        if NSRunningApplication.runningApplications(withBundleIdentifier: helperBundleIdentifier).first != nil {
            helperStatus = .running
            isHelperRunning = true
            return
        }

        // Attempt to find and open the helper app
        let helperURL = locateHelperApp()
        guard let url = helperURL else {
            helperStatus = .error
            isHelperRunning = false
            print("[HelperManager] Could not locate \(helperAppName)")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false // Helper has no UI
        configuration.addsToRecentItems = false

        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            // Give the helper a moment to start its socket server
            try? await Task.sleep(for: .seconds(3))
            await healthCheck()
        } catch {
            helperStatus = .error
            isHelperRunning = false
            print("[HelperManager] Failed to launch helper: \(error)")
        }
    }

    /// Stops the HomeKitHelper by sending a shutdown command via the socket.
    ///
    /// Falls back to terminating via NSRunningApplication if the socket command fails.
    func stopHelper() async {
        // Try graceful shutdown via socket
        do {
            _ = try await sendSocketCommand("shutdown")
            try? await Task.sleep(for: .seconds(2))
        } catch {
            // Graceful shutdown failed; force-terminate
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: helperBundleIdentifier).first {
                app.terminate()
            }
        }

        helperStatus = .stopped
        isHelperRunning = false
    }

    /// Performs a health check by pinging the helper via the Unix domain socket.
    ///
    /// Updates `isHelperRunning` and `helperStatus`. If the helper is unresponsive,
    /// triggers a restart (subject to rate limiting).
    func healthCheck() async {
        do {
            let response = try await sendSocketCommand("status")
            if response.contains("\"status\":\"ok\"") || response.contains("\"status\": \"ok\"") {
                helperStatus = .running
                isHelperRunning = true
            } else {
                helperStatus = .error
                isHelperRunning = false
                await restartIfNeeded()
            }
        } catch {
            helperStatus = .stopped
            isHelperRunning = false
            await restartIfNeeded()
        }
    }

    /// Attempts to restart the helper if the restart rate limit has not been exceeded.
    ///
    /// Maintains a sliding window of restart timestamps. If the number of restarts within
    /// the last 15 minutes exceeds `maxRestarts`, the restart is skipped and an error state
    /// is set.
    func restartIfNeeded() async {
        // Prune old timestamps outside the sliding window
        let cutoff = Date().addingTimeInterval(-restartWindowDuration)
        restartTimestamps.removeAll { $0 < cutoff }

        guard restartTimestamps.count < maxRestarts else {
            helperStatus = .error
            isHelperRunning = false
            print("[HelperManager] Max restarts (\(maxRestarts)) exceeded in \(Int(restartWindowDuration / 60))-minute window. Not restarting.")
            return
        }

        restartTimestamps.append(Date())
        helperStatus = .restarting
        print("[HelperManager] Restarting helper (attempt \(restartTimestamps.count)/\(maxRestarts))")
        await launchHelper()
    }

    // MARK: - Socket Communication

    /// Sends a simple command to the helper via Unix domain socket and returns the raw
    /// JSON response string.
    private nonisolated func sendSocketCommand(_ command: String) async throws -> String {
        let requestId = UUID().uuidString
        let token = SocketConstants.getOrCreateToken()
        let version = SocketConstants.protocolVersion
        let json = """
        {"id":"\(requestId)","command":"\(command)","token":"\(token)","version":\(version)}
        """

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [socketPath] in
                let sock = socket(AF_UNIX, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    continuation.resume(throwing: HelperManagerError.socketCreationFailed)
                    return
                }
                defer { close(sock) }

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
                    continuation.resume(throwing: HelperManagerError.connectionFailed)
                    return
                }

                // Send
                var message = json + "\n"
                let sent = message.withUTF8 { buffer in
                    Darwin.send(sock, buffer.baseAddress!, buffer.count, 0)
                }
                guard sent == message.utf8.count else {
                    continuation.resume(throwing: HelperManagerError.sendFailed)
                    return
                }

                // Receive (5-second timeout for health checks)
                var tv = timeval(tv_sec: 5, tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var responseData = Data()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 8192)
                defer { buf.deallocate() }

                while true {
                    let bytesRead = Darwin.recv(sock, buf, 8192, 0)
                    if bytesRead <= 0 { break }
                    responseData.append(buf, count: bytesRead)
                    if responseData.last == UInt8(ascii: "\n") { break }
                }

                guard !responseData.isEmpty, let responseString = String(data: responseData, encoding: .utf8) else {
                    continuation.resume(throwing: HelperManagerError.noResponse)
                    return
                }

                continuation.resume(returning: responseString)
            }
        }
    }

    // MARK: - Helper Location

    /// Locates the HomeKitHelper app bundle relative to the main app.
    private func locateHelperApp() -> URL? {
        // Check inside the main app bundle's helpers
        if let helpersURL = Bundle.main.builtInPlugInsURL?
            .deletingLastPathComponent()
            .appendingPathComponent("Library")
            .appendingPathComponent("LoginItems")
            .appendingPathComponent(helperAppName) {
            if FileManager.default.fileExists(atPath: helpersURL.path) {
                return helpersURL
            }
        }

        // Check alongside the main app
        if let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(helperAppName) as URL? {
            if FileManager.default.fileExists(atPath: appURL.path) {
                return appURL
            }
        }

        // Check in Applications
        let applicationsPath = "/Applications/\(helperAppName)"
        if FileManager.default.fileExists(atPath: applicationsPath) {
            return URL(fileURLWithPath: applicationsPath)
        }

        return nil
    }
}

// MARK: - Errors

enum HelperManagerError: LocalizedError {
    case socketCreationFailed
    case connectionFailed
    case sendFailed
    case noResponse

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed: return "Could not create socket"
        case .connectionFailed: return "Could not connect to HomeKitHelper socket"
        case .sendFailed: return "Failed to send command to HomeKitHelper"
        case .noResponse: return "No response from HomeKitHelper"
        }
    }
}
