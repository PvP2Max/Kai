//
//  KeychainManager.swift
//  Kai
//
//  Secure token storage using iOS Keychain.
//

import Foundation
import Security

/// Manages secure storage of authentication tokens in the iOS Keychain.
/// Supports shared access with the Siri extension through App Groups.
final class KeychainManager {

    // MARK: - Singleton

    static let shared = KeychainManager()

    // MARK: - Constants

    private enum Keys {
        static let accessToken = "com.kai.accessToken"
        static let refreshToken = "com.kai.refreshToken"
        static let tokenExpiry = "com.kai.tokenExpiry"
    }

    /// App Group identifier for sharing keychain with extensions.
    /// Update this to match your actual App Group identifier.
    private let appGroupIdentifier = "group.com.kai.shared"

    /// Keychain access group for sharing between app and extensions.
    private var accessGroup: String {
        return appGroupIdentifier
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Token Management

    /// Saves both access and refresh tokens to the keychain.
    /// - Parameters:
    ///   - accessToken: The JWT access token.
    ///   - refreshToken: The JWT refresh token.
    ///   - expiresIn: Optional token expiry time in seconds.
    /// - Throws: `KeychainError` if the save operation fails.
    func saveTokens(accessToken: String, refreshToken: String, expiresIn: TimeInterval? = nil) throws {
        try saveItem(accessToken, forKey: Keys.accessToken)
        try saveItem(refreshToken, forKey: Keys.refreshToken)

        if let expiresIn = expiresIn {
            let expiryDate = Date().addingTimeInterval(expiresIn)
            let expiryString = ISO8601DateFormatter().string(from: expiryDate)
            try saveItem(expiryString, forKey: Keys.tokenExpiry)
        }
    }

    /// Retrieves the access token from the keychain.
    /// - Returns: The access token if available, nil otherwise.
    func getAccessToken() -> String? {
        return getItem(forKey: Keys.accessToken)
    }

    /// Retrieves the refresh token from the keychain.
    /// - Returns: The refresh token if available, nil otherwise.
    func getRefreshToken() -> String? {
        return getItem(forKey: Keys.refreshToken)
    }

    /// Retrieves the token expiry date.
    /// - Returns: The expiry date if available, nil otherwise.
    func getTokenExpiry() -> Date? {
        guard let expiryString = getItem(forKey: Keys.tokenExpiry) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: expiryString)
    }

    /// Checks if the current access token has expired or is about to expire.
    /// - Parameter buffer: Time buffer in seconds before actual expiry (default: 60 seconds).
    /// - Returns: True if the token is expired or will expire within the buffer time.
    func isTokenExpired(buffer: TimeInterval = 60) -> Bool {
        guard let expiry = getTokenExpiry() else {
            // If no expiry stored, check if we have a token at all
            return getAccessToken() == nil
        }
        return Date().addingTimeInterval(buffer) >= expiry
    }

    /// Checks if valid tokens exist in the keychain.
    /// - Returns: True if both access and refresh tokens exist.
    func hasValidTokens() -> Bool {
        return getAccessToken() != nil && getRefreshToken() != nil
    }

    /// Clears all authentication tokens from the keychain.
    func clearTokens() {
        deleteItem(forKey: Keys.accessToken)
        deleteItem(forKey: Keys.refreshToken)
        deleteItem(forKey: Keys.tokenExpiry)
    }

    // MARK: - Private Keychain Operations

    private func saveItem(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // First, try to delete any existing item
        deleteItem(forKey: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Add access group for sharing with extensions
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func getItem(forKey key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteItem(forKey key: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Update Tokens

    /// Updates only the access token (useful after refresh).
    /// - Parameter accessToken: The new access token.
    /// - Throws: `KeychainError` if the update fails.
    func updateAccessToken(_ accessToken: String, expiresIn: TimeInterval? = nil) throws {
        try saveItem(accessToken, forKey: Keys.accessToken)

        if let expiresIn = expiresIn {
            let expiryDate = Date().addingTimeInterval(expiresIn)
            let expiryString = ISO8601DateFormatter().string(from: expiryDate)
            try saveItem(expiryString, forKey: Keys.tokenExpiry)
        }
    }
}

// MARK: - Keychain Error

/// Errors that can occur during keychain operations.
enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case itemNotFound
    case unexpectedData
    case unhandledError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for keychain storage."
        case .saveFailed(let status):
            return "Failed to save item to keychain. Status: \(status)"
        case .itemNotFound:
            return "Item not found in keychain."
        case .unexpectedData:
            return "Unexpected data format in keychain."
        case .unhandledError(let status):
            return "Unhandled keychain error. Status: \(status)"
        }
    }
}
