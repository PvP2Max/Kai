import Foundation
import Combine
import UserNotifications

/// ViewModel for the Settings screen.
/// Manages user profile information, preferences, and logout functionality.
@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties

    /// User's display name
    @Published var userName: String = "User"

    /// User's email address
    @Published var userEmail: String = "user@example.com"

    /// Full user object
    @Published var user: User?

    /// Loading state
    @Published var isLoading: Bool = false

    /// Error message for display
    @Published var errorMessage: String?

    /// Whether notifications are enabled
    @Published var notificationsEnabled: Bool = true

    /// Whether logout is in progress
    @Published var isLoggingOut: Bool = false

    /// Controls the delete data confirmation alert
    @Published var showDeleteDataAlert: Bool = false

    // MARK: - Computed Properties

    /// User initials for avatar display
    var userInitials: String {
        user?.initials ?? "U"
    }

    /// App version string
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Member since date string
    var memberSinceDate: String? {
        guard let createdAt = user?.createdAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Member since \(formatter.string(from: createdAt))"
    }

    // MARK: - Initialization

    init() {
        loadUserInfo()
    }

    // MARK: - Methods

    /// Load user information from API
    func loadUserInfo() {
        Task {
            await loadUserInfoAsync()
        }
    }

    /// Async version of loadUserInfo
    func loadUserInfoAsync() async {
        isLoading = true
        errorMessage = nil

        do {
            // TODO: Replace with actual API call
            // let user = try await APIClient.shared.getCurrentUser()

            // Using sample data for now
            try await Task.sleep(nanoseconds: 300_000_000)

            self.user = User.sample
            self.userName = user?.name ?? "User"
            self.userEmail = user?.email ?? "user@example.com"

            // Load notification preference
            notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Toggle notifications setting
    func toggleNotifications(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")

        Task {
            if enabled {
                await requestNotificationPermission()
            }
        }
    }

    /// Delete all user data
    func deleteAllData() async {
        isLoading = true
        errorMessage = nil

        do {
            // TODO: Replace with actual API call
            // try await APIClient.shared.deleteAllUserData()

            try await Task.sleep(nanoseconds: 500_000_000)

            // Clear local data
            clearLocalData()

            // Trigger logout
            await logout()

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Log out the current user
    func logout() async {
        isLoggingOut = true
        errorMessage = nil

        do {
            // TODO: Replace with actual logout logic
            // try await APIClient.shared.logout()

            try await Task.sleep(nanoseconds: 300_000_000)

            // Clear local data
            clearLocalData()

            // Post notification to trigger app-wide logout handling
            NotificationCenter.default.post(name: .userDidLogout, object: nil)

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoggingOut = false
    }

    /// Refresh user info
    func refresh() async {
        await loadUserInfoAsync()
    }

    // MARK: - Private Methods

    private func clearLocalData() {
        // Clear user defaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }

        // Clear any cached data
        URLCache.shared.removeAllCachedResponses()

        // Reset user
        user = nil
        userName = "User"
        userEmail = "user@example.com"
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                print("Notification permission granted")
            }
        } catch {
            print("Failed to request notification permission: \(error)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the user logs out
    static let userDidLogout = Notification.Name("userDidLogout")
}

// MARK: - Bundle Extension

extension Bundle {
    /// App version string including build number
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
