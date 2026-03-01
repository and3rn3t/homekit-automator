// SocketConstants.swift
// HomeKit Automator — This file should match HomeKitCore/SocketConstants.swift — do not edit independently.
//
// Single source of truth for socket path, token management, and config directory.
// All targets (CLI, Helper, GUI) should use consistent socket/token logic
// to avoid authentication failures between components.

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
enum SocketConstants: Sendable {

    /// The Application Support subdirectory for HomeKit Automator.
    /// Created on demand if it does not exist. Returns nil only if the system
    /// has no Application Support directory (practically impossible on macOS).
    static var appSupportDir: URL? {
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
    static var defaultPath: String {
        guard let dir = appSupportDir else {
            return "/tmp/homekitauto.sock"
        }
        return dir.appendingPathComponent("homekitauto.sock").path
    }

    /// Path to the authentication token file.
    static var tokenPath: String {
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
    /// Logs a warning if the token cannot be persisted to disk.
    static func getOrCreateToken() -> String {
        let path = tokenPath
        if let existing = try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let token = UUID().uuidString
        do {
            try token.write(toFile: path, atomically: true, encoding: .utf8)
            // Set file permissions to owner-only (0600)
            chmod(path, 0o600)
        } catch {
            // Token is usable for this session but won't persist across restarts.
            // This can cause auth failures if the other component reads a different token.
            print("[SocketConstants] WARNING: Could not persist auth token to \(path): \(error.localizedDescription)")
        }
        return token
    }

    /// Validates an incoming request's token against the stored token.
    /// Uses constant-time comparison to prevent timing side-channel attacks.
    static func validateToken(_ requestToken: String?) -> Bool {
        guard let requestToken = requestToken, !requestToken.isEmpty else { return false }
        let expected = getOrCreateToken()
        // Constant-time comparison: always compare all bytes regardless of mismatch position.
        let requestBytes = Array(requestToken.utf8)
        let expectedBytes = Array(expected.utf8)
        guard requestBytes.count == expectedBytes.count else { return false }
        var result: UInt8 = 0
        for (a, b) in zip(requestBytes, expectedBytes) {
            result |= a ^ b
        }
        return result == 0
    }

    /// Deletes the persisted auth token so that the next call to `getOrCreateToken()`
    /// generates a fresh one. Used by the Debug view to force re-authentication.
    static func resetToken() {
        let path = tokenPath
        try? FileManager.default.removeItem(atPath: path)
    }

    /// The legacy socket path that was used before the Application Support migration.
    static let legacySocketPath = "/tmp/homekitauto.sock"

    /// Protocol version for socket IPC. Incremented when the request/response
    /// format changes in a backward-incompatible way.
    static let protocolVersion = 1
}
