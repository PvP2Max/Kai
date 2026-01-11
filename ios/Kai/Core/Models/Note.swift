import Foundation

/// Note model matching the backend NoteResponse schema.
/// Represents a note created by the user or captured from meetings/conversations.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct Note: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for the note
    let id: UUID

    /// Note title (optional)
    var title: String?

    /// Note content
    var content: String

    /// Source of the note (e.g., "manual", "meeting", "voice")
    let source: String?

    /// Associated meeting event ID (if captured from a meeting)
    let meetingEventId: String?

    /// Associated project ID (if linked to a project)
    let projectId: UUID?

    /// Tags for organization
    var tags: [String]?

    /// When the note was created
    let createdAt: Date

    /// When the note was last updated
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String? = nil,
        content: String,
        source: String? = "manual",
        meetingEventId: String? = nil,
        projectId: UUID? = nil,
        tags: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.source = source
        self.meetingEventId = meetingEventId
        self.projectId = projectId
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Display title, using content preview if no title is set
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return preview
    }

    /// Content preview (first 100 characters)
    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 100 {
            return trimmed
        }
        return String(trimmed.prefix(100)) + "..."
    }

    /// Relative date string (e.g., "2h ago")
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    /// Full formatted created date
    var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Full formatted updated date
    var formattedUpdatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }

    /// Whether the note has been modified since creation
    var hasBeenEdited: Bool {
        abs(createdAt.timeIntervalSince(updatedAt)) > 1
    }

    /// Whether the note has any tags
    var hasTags: Bool {
        !(tags?.isEmpty ?? true)
    }
}

// MARK: - Create/Update Request Models

/// Request body for creating a note
/// Note: APIClient uses `.convertToSnakeCase` so no CodingKeys needed.
struct NoteCreateRequest: Codable, Sendable {
    let title: String?
    let content: String
    let projectId: UUID?
    let tags: [String]?
    let source: String?

    init(
        title: String? = nil,
        content: String,
        projectId: UUID? = nil,
        tags: [String]? = nil,
        source: String? = "ios"
    ) {
        self.title = title
        self.content = content
        self.projectId = projectId
        self.tags = tags
        self.source = source
    }
}

/// Request body for updating a note
/// Note: APIClient uses `.convertToSnakeCase` so no CodingKeys needed.
struct NoteUpdateRequest: Codable, Sendable {
    let title: String?
    let content: String?
    let projectId: UUID?
    let tags: [String]?

    init(
        title: String? = nil,
        content: String? = nil,
        projectId: UUID? = nil,
        tags: [String]? = nil
    ) {
        self.title = title
        self.content = content
        self.projectId = projectId
        self.tags = tags
    }
}

// MARK: - Note Source

/// Source of a note
enum NoteSource: String, Codable, Sendable {
    case manual
    case meeting
    case voice
    case ios
    case siri
    case web
}

// MARK: - Sample Data

extension Note {
    static let sample = Note(
        id: UUID(),
        title: "Meeting Notes",
        content: "Discussed project timeline and deliverables. Key action items: finalize design by Friday, schedule user testing for next week.",
        source: "manual",
        meetingEventId: nil,
        projectId: nil,
        tags: ["work", "meetings"],
        createdAt: Date().addingTimeInterval(-86400),
        updatedAt: Date().addingTimeInterval(-3600)
    )

    static let samples: [Note] = [
        Note(
            id: UUID(),
            title: "Meeting Notes",
            content: "Discussed project timeline and deliverables. Key action items: finalize design by Friday, schedule user testing for next week.",
            source: "manual",
            meetingEventId: nil,
            projectId: nil,
            tags: ["work", "meetings"],
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date().addingTimeInterval(-3600)
        ),
        Note(
            id: UUID(),
            title: "Ideas for App",
            content: "Add voice commands for quick note creation. Integrate with calendar for context-aware reminders. Consider widget support.",
            source: "manual",
            meetingEventId: nil,
            projectId: nil,
            tags: ["ideas", "development"],
            createdAt: Date().addingTimeInterval(-172800),
            updatedAt: Date().addingTimeInterval(-86400)
        ),
        Note(
            id: UUID(),
            title: "Shopping List",
            content: "Groceries: milk, eggs, bread, cheese, vegetables. Hardware store: batteries, light bulbs.",
            source: "voice",
            meetingEventId: nil,
            projectId: nil,
            tags: ["personal"],
            createdAt: Date().addingTimeInterval(-259200),
            updatedAt: Date().addingTimeInterval(-259200)
        ),
        Note(
            id: UUID(),
            title: "Book Recommendations",
            content: "1. Atomic Habits by James Clear\n2. Deep Work by Cal Newport\n3. The Pragmatic Programmer",
            source: "manual",
            meetingEventId: nil,
            projectId: nil,
            tags: ["reading"],
            createdAt: Date().addingTimeInterval(-345600),
            updatedAt: Date().addingTimeInterval(-172800)
        )
    ]
}
