// KeychainHelper.swift
// Secure storage for sensitive credentials using macOS Keychain Services.
//
// Used instead of UserDefaults/@AppStorage for API keys and other secrets.
// UserDefaults stores data as unencrypted plist files readable by any process
// running as the same user. Keychain data is encrypted at rest and access-controlled.

import Foundation
import Security

/// Provides read/write access to the macOS Keychain for storing sensitive credentials.
///
/// All operations use `kSecClassGenericPassword` items scoped to the
/// "com.homekit-automator" service name for namespacing.
enum KeychainHelper {

    private static let serviceName = "com.homekit-automator"

    // MARK: - Save

    /// Stores a string value in the Keychain. Overwrites any existing value for the same key.
    ///
    /// - Parameters:
    ///   - value: The string to store securely
    ///   - key: The account/key name to store it under
    /// - Throws: `KeychainError` if the operation fails
    @discardableResult
    static func save(_ value: String, forKey key: String) throws -> Bool {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first (update = delete + add)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
        return true
    }

    // MARK: - Read

    /// Retrieves a string value from the Keychain.
    ///
    /// - Parameter key: The account/key name to retrieve
    /// - Returns: The stored string, or nil if not found
    static func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    // MARK: - Delete

    /// Removes a value from the Keychain.
    ///
    /// - Parameter key: The account/key name to remove
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Migration

    /// Migrates an API key from UserDefaults to Keychain (one-time migration).
    ///
    /// If a key exists in UserDefaults but not in Keychain, copies it to Keychain
    /// and removes it from UserDefaults. Safe to call multiple times.
    static func migrateFromUserDefaults(userDefaultsKey: String, keychainKey: String) {
        // Skip if already in Keychain
        if read(forKey: keychainKey) != nil { return }

        // Check UserDefaults
        guard let value = UserDefaults.standard.string(forKey: userDefaultsKey),
              !value.isEmpty else { return }

        // Migrate to Keychain
        if (try? save(value, forKey: keychainKey)) != nil {
            // Remove from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for Keychain storage"
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        }
    }
}
