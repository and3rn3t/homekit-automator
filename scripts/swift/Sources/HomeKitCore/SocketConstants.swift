// SocketConstants.swift
// HomeKitCore — Single source of truth for socket path, token management, and config directory.
//
// All targets (CLI, Helper, GUI) should use these constants to avoid triplication
// of socket path computation, token read/create logic, and directory creation.
//
// Previously, SocketClient.swift, HelperSocketServer.swift, and HelperManager.swift
// each had their own independent copy of this logic.

import Foundation

/// Shared socket and authentication constants for all HomeKit Automator components.
///
/// Provides:
/// - Socket path: `~/Library/Application Support/homekit-automator/homekitauto.sock`
/// - Auth token: `~/Library/Application Support/homekit-automator/.auth_token`
/// - Config directory: `~/Library/Application Support/homekit-automator/`
///
/// All paths use the macOS Application Support convention. The config directory
/// is created on demand if it does not exist.
public enum SocketConstants {

    /// The Application Support subdirectory for HomeKit Automator.
    /// Created on demand if it does not exist. Returns nil only if the system
    /// has no Application Support directory (practically impossible on macOS).
    public static var appSupportDir: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("homekit-automator")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Default socket path in user-scoped Application Support directory.
    /// Returns a fallback path in /tmp if Application Support is unavailable.
    public static var defaultPath: String {
        guard let dir = appSupportDir else {
            return "/tmp/homekitauto.sock"
        }
        return dir.appendingPathComponent("homekitauto.sock").path
    }

    /// Path to the authentication token file.
    public static var tokenPath: String {
        guard let dir = appSupportDir else {
            return "/tmp/homekitauto.auth_token"
        }
        return dir.appendingPathComponent(".auth_token").path
    }

    /// Generate or read the shared authentication token.
    ///
    /// If a token file exists and is non-empty, returns its contents.
    /// Otherwise, generates a new UUID token, writes it to disk with
    /// mode 0600 (owner-only), and returns it.
    public static func getOrCreateToken() -> String {
        let path = tokenPath
        if let existing = try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let token = UUID().uuidString
        try? token.write(toFile: path, atomically: true, encoding: .utf8)
        // Set file permissions to owner-only (0600)
        chmod(path, 0o600)
        return token
    }

    /// Validates an incoming request's token against the stored token.
    public static func validateToken(_ requestToken: String?) -> Bool {
        guard let requestToken = requestToken, !requestToken.isEmpty else { return false }
        let expected = getOrCreateToken()
        return requestToken == expected
    }

    /// The legacy socket path that was used before the Application Support migration.
    public static let legacySocketPath = "/tmp/homekitauto.sock"

    /// Protocol version for socket IPC. Incremented when the request/response
    /// format changes in a backward-incompatible way.
    public static let protocolVersion = 1
}
