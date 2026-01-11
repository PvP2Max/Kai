//
//  ActivityLog.swift
//  Kai
//
//  Activity log models for tracking user actions.
//

import Foundation

/// Activity log item from the backend
struct ActivityLogItem: Codable, Identifiable {
    let id: UUID
    let actionType: String
    let actionData: [String: AnyCodable]
    let source: String?
    let reversible: Bool
    let reversed: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case actionType = "action_type"
        case actionData = "action_data"
        case source
        case reversible
        case reversed
        case createdAt = "created_at"
    }

    /// Human-readable description of the action
    var actionDescription: String {
        switch actionType {
        case "note_create":
            return "Created note: \(actionData["title"]?.value as? String ?? "Untitled")"
        case "note_update":
            return "Updated note: \(actionData["title"]?.value as? String ?? "Untitled")"
        case "note_delete":
            return "Deleted note: \(actionData["title"]?.value as? String ?? "Untitled")"
        case "calendar_create":
            return "Created event: \(actionData["title"]?.value as? String ?? actionData["summary"]?.value as? String ?? "Untitled")"
        case "calendar_update":
            return "Updated event: \(actionData["title"]?.value as? String ?? actionData["summary"]?.value as? String ?? "Untitled")"
        case "calendar_delete":
            return "Deleted event: \(actionData["title"]?.value as? String ?? actionData["summary"]?.value as? String ?? "Untitled")"
        case "reminder_create":
            return "Created reminder: \(actionData["title"]?.value as? String ?? "Untitled")"
        case "reminder_complete":
            return "Completed reminder: \(actionData["title"]?.value as? String ?? "Untitled")"
        case "project_create":
            return "Created project: \(actionData["name"]?.value as? String ?? "Untitled")"
        case "project_update":
            return "Updated project: \(actionData["name"]?.value as? String ?? "Untitled")"
        case "meeting_create":
            return "Recorded meeting: \(actionData["title"]?.value as? String ?? "Untitled")"
        case "follow_up_create":
            return "Created follow-up: \(actionData["title"]?.value as? String ?? "Untitled")"
        default:
            return actionType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// SF Symbol icon for the action type
    var actionIcon: String {
        switch actionType {
        case let type where type.contains("note"):
            return "note.text"
        case let type where type.contains("calendar"):
            return "calendar"
        case let type where type.contains("reminder"):
            return "checklist"
        case let type where type.contains("project"):
            return "folder"
        case let type where type.contains("meeting"):
            return "person.3"
        case let type where type.contains("follow_up"):
            return "arrow.uturn.forward"
        default:
            return "clock.arrow.circlepath"
        }
    }

    /// Color for the action icon
    var actionColor: String {
        switch actionType {
        case let type where type.contains("note"):
            return "orange"
        case let type where type.contains("calendar"):
            return "blue"
        case let type where type.contains("reminder"):
            return "green"
        case let type where type.contains("project"):
            return "purple"
        case let type where type.contains("meeting"):
            return "indigo"
        case let type where type.contains("delete"):
            return "red"
        default:
            return "gray"
        }
    }

    /// Relative time string
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

/// Response for undo action
struct UndoResponse: Codable {
    let success: Bool
    let message: String
    let activityId: UUID

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case activityId = "activity_id"
    }
}

/// Helper type to decode arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unable to encode value"))
        }
    }
}
