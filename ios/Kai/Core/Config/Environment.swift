import Foundation

/// Environment configuration for the Kai iOS app.
/// Contains all environment-specific constants and configuration values.
enum AppEnvironment {
    // MARK: - API Configuration

    /// Base URL for the Kai backend API
    static let apiBaseURL = URL(string: "https://kai.pvp2max.com")!

    /// API version prefix
    static let apiVersion = "/api"

    /// Full API base URL with version
    static var apiURL: URL {
        apiBaseURL.appendingPathComponent(apiVersion)
    }

    // MARK: - App Groups & Keychain

    /// App Group identifier for sharing data between app and extensions
    static let appGroupIdentifier = "group.com.arcticauradesigns.kai"

    /// Keychain access group for secure credential storage
    static let keychainAccessGroup = "com.arcticauradesigns.kai.shared"

    /// Keychain service identifier
    static let keychainService = "com.arcticauradesigns.kai.auth"

    // MARK: - Storage Keys

    enum StorageKeys {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let currentUser = "current_user"
        static let offlineQueue = "offline_queue"
        static let lastSyncDate = "last_sync_date"
    }

    // MARK: - Timeouts & Limits

    /// Request timeout interval in seconds
    static let requestTimeout: TimeInterval = 30

    /// Upload timeout interval in seconds (for audio files)
    static let uploadTimeout: TimeInterval = 300

    /// Maximum audio file size in bytes (50 MB)
    static let maxAudioFileSize: Int64 = 50 * 1024 * 1024

    /// Maximum offline queue size
    static let maxOfflineQueueSize: Int = 100
}
