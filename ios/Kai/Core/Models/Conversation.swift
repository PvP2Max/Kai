import Foundation

/// Conversation model matching the backend ConversationResponse schema.
/// Represents a chat conversation containing multiple messages.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct Conversation: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for the conversation
    let id: UUID

    /// Optional title for the conversation
    let title: String?

    /// When the conversation was created
    let createdAt: Date

    /// When the conversation was last updated
    let updatedAt: Date

    /// Messages within this conversation
    var messages: [Message]

    init(
        id: UUID,
        title: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

/// Lightweight conversation model for list views.
/// Matches the backend ConversationListResponse schema.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct ConversationSummary: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for the conversation
    let id: UUID

    /// Optional title for the conversation
    let title: String?

    /// When the conversation was created
    let createdAt: Date

    /// When the conversation was last updated
    let updatedAt: Date

    /// Number of messages in the conversation
    let messageCount: Int
}

// MARK: - Convenience Extensions

extension Conversation {
    /// Returns the last message in the conversation, if any
    var lastMessage: Message? {
        messages.last
    }

    /// Returns a display title, using the first message content if no title is set
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content
            return String(content.prefix(50)) + (content.count > 50 ? "..." : "")
        }
        return "New Conversation"
    }

    /// Returns a preview of the last message content
    var lastMessagePreview: String? {
        guard let lastMsg = lastMessage else { return nil }
        let content = lastMsg.content
        return String(content.prefix(100)) + (content.count > 100 ? "..." : "")
    }

    /// Number of messages in the conversation
    var messageCount: Int {
        messages.count
    }

    /// Whether any messages contain tool calls
    var hasToolCalls: Bool {
        messages.contains { $0.toolCalls != nil && !($0.toolCalls?.isEmpty ?? true) }
    }

    /// Formatted time for display
    var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    /// Date section for grouping
    var dateSection: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(updatedAt) {
            return "Today"
        } else if calendar.isDateInYesterday(updatedAt) {
            return "Yesterday"
        } else if calendar.isDate(updatedAt, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(updatedAt, equalTo: Date(), toGranularity: .month) {
            return "This Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: updatedAt)
        }
    }
}

extension ConversationSummary {
    /// Returns a display title, defaulting to "New Conversation" if no title is set
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return "New Conversation"
    }

    /// Date section for grouping
    var dateSection: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(updatedAt) {
            return "Today"
        } else if calendar.isDateInYesterday(updatedAt) {
            return "Yesterday"
        } else if calendar.isDate(updatedAt, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(updatedAt, equalTo: Date(), toGranularity: .month) {
            return "This Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: updatedAt)
        }
    }

    /// Formatted time for display
    var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}
