import Foundation

/// User model matching the backend UserResponse schema.
/// Represents an authenticated user in the Kai system.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct User: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for the user
    let id: UUID

    /// User's email address
    let email: String

    /// User's display name
    let name: String

    /// When the user account was created
    let createdAt: Date

    /// When the user account was last updated
    let updatedAt: Date

    /// User initials for avatar display
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let firstChar = name.first {
            return String(firstChar).uppercased()
        }
        return "U"
    }

    /// Sample user for previews and development
    static let sample = User(
        id: UUID(),
        email: "user@example.com",
        name: "John Doe",
        createdAt: Date().addingTimeInterval(-86400 * 30),
        updatedAt: Date()
    )

    init(id: UUID, email: String, name: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.email = email
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Authentication Models

/// Request body for user registration
struct UserCreateRequest: Codable, Sendable {
    let email: String
    let password: String
    let name: String
}

/// Request body for user login
struct UserLoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

/// Authentication token response from the backend
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct AuthToken: Codable, Sendable {
    /// JWT access token for API requests
    let accessToken: String

    /// JWT refresh token for obtaining new access tokens
    let refreshToken: String

    /// Token type (typically "bearer")
    let tokenType: String
}
