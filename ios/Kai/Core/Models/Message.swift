import Foundation

/// Message model matching the backend MessageResponse schema.
/// Represents a single message within a conversation.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct Message: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for the message
    let id: UUID

    /// Role of the message sender ("user" or "assistant")
    let role: MessageRole

    /// The text content of the message
    let content: String

    /// Tool calls made during this message (if any)
    let toolCalls: [String: AnyCodable]?

    /// The AI model used to generate this message (for assistant messages)
    let modelUsed: String?

    /// When the message was created
    let createdAt: Date
}

/// Role of a message sender
enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}
