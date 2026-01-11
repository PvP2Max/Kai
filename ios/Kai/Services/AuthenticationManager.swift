//
//  AuthenticationManager.swift
//  Kai
//
//  Authentication state management with biometric support.
//

import Foundation
import LocalAuthentication
import Combine

/// Manages authentication state and provides login/logout functionality.
@MainActor
final class AuthenticationManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AuthenticationManager()

    // MARK: - Published Properties

    /// Whether the user is currently authenticated.
    @Published private(set) var isAuthenticated: Bool = false

    /// The current user's information.
    @Published private(set) var currentUser: User?

    /// Whether biometric authentication is required on app launch.
    @Published var requiresBiometric: Bool = false

    /// Whether the device supports biometric authentication.
    @Published private(set) var biometricType: BiometricType = .none

    /// Loading state for authentication operations.
    @Published private(set) var isLoading: Bool = false

    /// The most recent authentication error.
    @Published private(set) var error: AuthenticationError?

    // MARK: - Types

    /// Types of biometric authentication available.
    enum BiometricType {
        case none
        case faceID
        case touchID
        case opticID

        var displayName: String {
            switch self {
            case .none: return "None"
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            }
        }

        var iconName: String {
            switch self {
            case .none: return "xmark.circle"
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            }
        }
    }

    // MARK: - Private Properties

    private let keychain = KeychainManager.shared
    private let apiClient = APIClient.shared
    private var cancellables = Set<AnyCancellable>()
    private let biometricEnabledKey = "biometricAuthEnabled"

    // MARK: - Initialization

    private init() {
        checkBiometricAvailability()
        loadBiometricPreference()
        checkExistingSession()
    }

    // MARK: - Public Methods

    /// Logs in with email and password.
    /// - Parameters:
    ///   - email: The user's email address.
    ///   - password: The user's password.
    func login(email: String, password: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let request = LoginRequest(email: email, password: password)
            let response: TokenResponse = try await apiClient.requestUnauthenticated(
                .login,
                method: .post,
                body: request
            )

            // Save tokens
            try keychain.saveTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken
            )

            // Update shared keychain for Siri extension
            SharedKeychain.setAccessToken(response.accessToken)
            SharedKeychain.setRefreshToken(response.refreshToken)

            // Fetch user info
            try await fetchCurrentUser()

            isAuthenticated = true

            #if DEBUG
            print("[AuthenticationManager] Login successful for \(email)")
            #endif

        } catch let apiError as APIError {
            let authError = mapAPIError(apiError)
            self.error = authError
            throw authError
        } catch {
            let authError = AuthenticationError.unknown(error)
            self.error = authError
            throw authError
        }
    }

    /// Authenticates using biometric (Face ID / Touch ID).
    func authenticateWithBiometric() async throws {
        guard biometricType != .none else {
            throw AuthenticationError.biometricNotAvailable
        }

        guard keychain.hasValidTokens() else {
            throw AuthenticationError.noStoredCredentials
        }

        isLoading = true
        error = nil

        defer { isLoading = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password"

        let reason = "Unlock Kai to access your assistant"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            guard success else {
                throw AuthenticationError.biometricFailed
            }

            // Verify tokens are still valid by fetching user
            try await fetchCurrentUser()

            isAuthenticated = true

            #if DEBUG
            print("[AuthenticationManager] Biometric authentication successful")
            #endif

        } catch let laError as LAError {
            let authError = mapLAError(laError)
            self.error = authError
            throw authError
        } catch let authError as AuthenticationError {
            self.error = authError
            throw authError
        } catch {
            let authError = AuthenticationError.unknown(error)
            self.error = authError
            throw authError
        }
    }

    /// Logs out the current user.
    func logout() {
        keychain.clearTokens()
        SharedKeychain.clearTokens()
        currentUser = nil
        isAuthenticated = false
        error = nil

        #if DEBUG
        print("[AuthenticationManager] User logged out")
        #endif
    }

    /// Enables or disables biometric authentication requirement.
    /// - Parameter enabled: Whether biometric should be required.
    func setBiometricEnabled(_ enabled: Bool) {
        requiresBiometric = enabled
        UserDefaults.standard.set(enabled, forKey: biometricEnabledKey)
    }

    /// Refreshes the current user information from the server.
    func refreshUser() async throws {
        try await fetchCurrentUser()
    }

    // MARK: - Private Methods

    private func checkExistingSession() {
        Task {
            guard keychain.hasValidTokens() else {
                isAuthenticated = false
                return
            }

            // If biometric is required, don't auto-authenticate
            if requiresBiometric && biometricType != .none {
                return
            }

            do {
                try await fetchCurrentUser()
                isAuthenticated = true
            } catch {
                // Token is invalid - clear it
                logout()
            }
        }
    }

    private func fetchCurrentUser() async throws {
        let response: UserResponse = try await apiClient.request(.me)

        currentUser = User(
            id: response.id,
            email: response.email,
            name: response.name,
            createdAt: response.createdAt,
            updatedAt: response.updatedAt
        )
    }

    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            case .opticID:
                biometricType = .opticID
            case .none:
                biometricType = .none
            @unknown default:
                biometricType = .none
            }
        } else {
            biometricType = .none
        }
    }

    private func loadBiometricPreference() {
        requiresBiometric = UserDefaults.standard.bool(forKey: biometricEnabledKey)
    }

    private func mapAPIError(_ error: APIError) -> AuthenticationError {
        switch error {
        case .notAuthenticated:
            return .invalidCredentials
        case .badRequest(let message):
            if message.lowercased().contains("email") {
                return .invalidEmail
            } else if message.lowercased().contains("password") {
                return .invalidPassword
            }
            return .serverError(message)
        case .serverError:
            return .serverError("Server error occurred")
        default:
            return .serverError(error.localizedDescription)
        }
    }

    private func mapLAError(_ error: LAError) -> AuthenticationError {
        switch error.code {
        case .authenticationFailed:
            return .biometricFailed
        case .userCancel:
            return .biometricCancelled
        case .userFallback:
            return .biometricFallback
        case .biometryNotAvailable:
            return .biometricNotAvailable
        case .biometryNotEnrolled:
            return .biometricNotEnrolled
        case .biometryLockout:
            return .biometricLockout
        default:
            return .biometricFailed
        }
    }
}

// MARK: - Authentication Error

/// Errors that can occur during authentication.
enum AuthenticationError: LocalizedError, Identifiable {
    case invalidCredentials
    case invalidEmail
    case invalidPassword
    case noStoredCredentials
    case biometricNotAvailable
    case biometricNotEnrolled
    case biometricFailed
    case biometricCancelled
    case biometricFallback
    case biometricLockout
    case serverError(String)
    case unknown(Error)

    var id: String {
        return errorDescription ?? "unknown"
    }

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password. Please try again."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .invalidPassword:
            return "Password is incorrect. Please try again."
        case .noStoredCredentials:
            return "No stored credentials found. Please log in."
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .biometricNotEnrolled:
            return "No biometric data enrolled. Please set up Face ID or Touch ID in Settings."
        case .biometricFailed:
            return "Biometric authentication failed. Please try again."
        case .biometricCancelled:
            return "Biometric authentication was cancelled."
        case .biometricFallback:
            return "Please use your password to authenticate."
        case .biometricLockout:
            return "Too many failed attempts. Please try again later or use your password."
        case .serverError(let message):
            return message
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials, .invalidPassword:
            return "Check your password and try again."
        case .invalidEmail:
            return "Enter a valid email address."
        case .noStoredCredentials:
            return "Log in with your email and password."
        case .biometricNotAvailable:
            return "Use email and password to log in."
        case .biometricNotEnrolled:
            return "Go to Settings > Face ID & Passcode to enroll."
        case .biometricLockout:
            return "Wait a few minutes or use your password."
        default:
            return nil
        }
    }
}
