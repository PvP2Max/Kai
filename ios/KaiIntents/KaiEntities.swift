import AppIntents
import Foundation

// MARK: - Meeting Entity

/// Entity representing a meeting for use in App Intents
@available(iOS 17.0, *)
struct MeetingEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meeting"

    static var defaultQuery = MeetingEntityQuery()

    var id: String
    var title: String
    var startTime: Date?
    var duration: Int? // minutes
    var hasRecording: Bool
    var isTranscribed: Bool

    var displayRepresentation: DisplayRepresentation {
        var subtitle: String? = nil
        if let startTime = startTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            subtitle = formatter.string(from: startTime)
        }

        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: subtitle.map { LocalizedStringResource(stringLiteral: $0) },
            image: .init(systemName: hasRecording ? "mic.circle.fill" : "calendar")
        )
    }
}

@available(iOS 17.0, *)
struct MeetingEntityQuery: EntityQuery {
    func entities(for identifiers: [MeetingEntity.ID]) async throws -> [MeetingEntity] {
        // Would fetch from API, but returning empty for now
        // This would be implemented with actual API calls in production
        return []
    }

    func suggestedEntities() async throws -> [MeetingEntity] {
        // Return recent meetings as suggestions
        return []
    }
}

// MARK: - Event Entity

/// Entity representing a calendar event
@available(iOS 17.0, *)
struct CalendarEventEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar Event"

    static var defaultQuery = CalendarEventEntityQuery()

    var id: String
    var title: String
    var startTime: Date
    var endTime: Date?
    var location: String?
    var isAllDay: Bool

    var displayRepresentation: DisplayRepresentation {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let timeString = isAllDay ? "All day" : formatter.string(from: startTime)

        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: timeString),
            image: .init(systemName: "calendar")
        )
    }
}

@available(iOS 17.0, *)
struct CalendarEventEntityQuery: EntityQuery {
    func entities(for identifiers: [CalendarEventEntity.ID]) async throws -> [CalendarEventEntity] {
        return []
    }

    func suggestedEntities() async throws -> [CalendarEventEntity] {
        return []
    }
}

// MARK: - Task Entity

/// Entity representing a task/reminder
@available(iOS 17.0, *)
struct TaskEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Task"

    static var defaultQuery = TaskEntityQuery()

    var id: String
    var title: String
    var priority: TaskPriority
    var dueDate: Date?
    var isCompleted: Bool

    var displayRepresentation: DisplayRepresentation {
        var subtitle: String? = nil
        if let dueDate = dueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            subtitle = "Due: \(formatter.string(from: dueDate))"
        }

        let iconName = isCompleted ? "checkmark.circle.fill" : "circle"

        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: subtitle.map { LocalizedStringResource(stringLiteral: $0) },
            image: .init(systemName: iconName)
        )
    }
}

@available(iOS 17.0, *)
enum TaskPriority: String, AppEnum {
    case high
    case medium
    case low

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"

    static var caseDisplayRepresentations: [TaskPriority: DisplayRepresentation] = [
        .high: DisplayRepresentation(title: "High", image: .init(systemName: "exclamationmark.circle.fill")),
        .medium: DisplayRepresentation(title: "Medium", image: .init(systemName: "minus.circle.fill")),
        .low: DisplayRepresentation(title: "Low", image: .init(systemName: "arrow.down.circle.fill"))
    ]
}

@available(iOS 17.0, *)
struct TaskEntityQuery: EntityQuery {
    func entities(for identifiers: [TaskEntity.ID]) async throws -> [TaskEntity] {
        return []
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        return []
    }
}

// MARK: - Conversation Entity

/// Entity representing a chat conversation with Kai
@available(iOS 17.0, *)
struct ConversationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Conversation"

    static var defaultQuery = ConversationEntityQuery()

    var id: String
    var title: String?
    var lastMessage: String?
    var lastMessageDate: Date?

    var displayRepresentation: DisplayRepresentation {
        let displayTitle = title ?? "Conversation"

        var subtitle: String? = nil
        if let lastMessage = lastMessage {
            subtitle = String(lastMessage.prefix(50))
        }

        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: displayTitle),
            subtitle: subtitle.map { LocalizedStringResource(stringLiteral: $0) },
            image: .init(systemName: "bubble.left.and.bubble.right")
        )
    }
}

@available(iOS 17.0, *)
struct ConversationEntityQuery: EntityQuery {
    func entities(for identifiers: [ConversationEntity.ID]) async throws -> [ConversationEntity] {
        return []
    }

    func suggestedEntities() async throws -> [ConversationEntity] {
        return []
    }
}
