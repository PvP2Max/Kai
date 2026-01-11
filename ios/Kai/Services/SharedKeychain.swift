//
//  SharedKeychain.swift
//  Kai
//
//  Static keychain helpers for Siri extension access.
//

import Foundation
import Security

/// Static helpers for accessing shared keychain items from Siri extension.
/// Uses App Group for cross-target keychain sharing.
enum SharedKeychain {

    // MARK: - Constants

    private enum Keys {
        static let accessToken = "com.kai.accessToken"
        static let refreshToken = "com.kai.refreshToken"
    }

    /// App Group identifier - must match the main app's KeychainManager.
    private static let appGroupIdentifier = "group.com.kai.shared"

    // MARK: - Access Token

    /// Sets the access token in the shared keychain.
    /// - Parameter token: The access token to store.
    /// - Returns: True if the operation succeeded.
    @discardableResult
    static func setAccessToken(_ token: String) -> Bool {
        return saveItem(token, forKey: Keys.accessToken)
    }

    /// Gets the access token from the shared keychain.
    /// - Returns: The access token if available, nil otherwise.
    static func getAccessToken() -> String? {
        return getItem(forKey: Keys.accessToken)
    }

    // MARK: - Refresh Token

    /// Sets the refresh token in the shared keychain.
    /// - Parameter token: The refresh token to store.
    /// - Returns: True if the operation succeeded.
    @discardableResult
    static func setRefreshToken(_ token: String) -> Bool {
        return saveItem(token, forKey: Keys.refreshToken)
    }

    /// Gets the refresh token from the shared keychain.
    /// - Returns: The refresh token if available, nil otherwise.
    static func getRefreshToken() -> String? {
        return getItem(forKey: Keys.refreshToken)
    }

    // MARK: - Clear Tokens

    /// Clears all tokens from the shared keychain.
    static func clearTokens() {
        deleteItem(forKey: Keys.accessToken)
        deleteItem(forKey: Keys.refreshToken)
    }

    /// Checks if valid tokens exist.
    /// - Returns: True if an access token exists.
    static func hasValidTokens() -> Bool {
        return getAccessToken() != nil
    }

    // MARK: - Private Helpers

    private static func saveItem(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        // Delete existing item first
        deleteItem(forKey: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Add access group for sharing
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = appGroupIdentifier
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func getItem(forKey key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = appGroupIdentifier
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

    private static func deleteItem(forKey key: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = appGroupIdentifier
        #endif

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Extension-Safe Token Refresh

extension SharedKeychain {

    /// Attempts to refresh the access token using the refresh token.
    /// This is a simplified version for use in extensions.
    /// - Returns: The new access token if refresh succeeded, nil otherwise.
    static func refreshAccessToken() async -> String? {
        guard let refreshToken = getRefreshToken() else {
            return nil
        }

        let url = URL(string: "https://kai.pvp2max.com/api/auth/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refresh_token": refreshToken]

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            struct TokenResponse: Decodable {
                let access_token: String
                let refresh_token: String
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            // Update stored tokens
            setAccessToken(tokenResponse.access_token)
            setRefreshToken(tokenResponse.refresh_token)

            return tokenResponse.access_token
        } catch {
            print("[SharedKeychain] Token refresh failed: \(error)")
            return nil
        }
    }
}
