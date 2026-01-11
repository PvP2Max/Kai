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

// Note: AnyCodable is defined in ChatModels.swift
