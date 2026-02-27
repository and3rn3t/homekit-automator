// SocketConstants.swift
// Shared constants and token management for Unix domain socket communication
// between HomeKit Automator and HomeKitHelper.

import Foundation

enum SocketConstants: Sendable {
    
    // MARK: - Configuration
    
    /// Protocol version for socket communication
    static let protocolVersion = "1.0"
    
    /// Default socket path in Application Support directory
    nonisolated static var defaultPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let dir = appSupport.appendingPathComponent("homekit-automator")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        return dir.appendingPathComponent("homekitauto.sock").path
    }
    
    // MARK: - Token Management
    
    private nonisolated(unsafe) static let tokenKey = "com.homekit-automator.socket-token"
    private nonisolated(unsafe) static let keychainService = "homekit-automator"
    
    /// Retrieves or creates a secure authentication token for socket communication.
    /// The token is stored in UserDefaults for simplicity (not sensitive data).
    nonisolated static func getOrCreateToken() -> String {
        // Check if token exists in UserDefaults
        if let existingToken = UserDefaults.standard.string(forKey: tokenKey), !existingToken.isEmpty {
            return existingToken
        }
        
        // Generate new token
        let newToken = UUID().uuidString
        UserDefaults.standard.set(newToken, forKey: tokenKey)
        
        return newToken
    }
    
    /// Resets the authentication token (useful for troubleshooting)
    nonisolated static func resetToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
