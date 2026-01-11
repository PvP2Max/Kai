//
//  Project.swift
//  Kai
//
//  Project model for organizing notes, meetings, and reminders.
//

import Foundation

// MARK: - Project

struct Project: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let status: String
    let createdAt: Date
    let updatedAt: Date
    var noteCount: Int
    var meetingCount: Int
    var reminderCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        status: String = "active",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        noteCount: Int = 0,
        meetingCount: Int = 0,
        reminderCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.noteCount = noteCount
        self.meetingCount = meetingCount
        self.reminderCount = reminderCount
    }

    var totalItemCount: Int {
        noteCount + meetingCount + reminderCount
    }

    var statusDisplayName: String {
        switch status {
        case "active": return "Active"
        case "completed": return "Completed"
        case "archived": return "Archived"
        default: return status.capitalized
        }
    }

    var statusIcon: String {
        switch status {
        case "active": return "circle.fill"
        case "completed": return "checkmark.circle.fill"
        case "archived": return "archivebox.fill"
        default: return "circle"
        }
    }

    var statusColor: String {
        switch status {
        case "active": return "green"
        case "completed": return "blue"
        case "archived": return "gray"
        default: return "gray"
        }
    }
}

// MARK: - Project Detail

struct ProjectDetail: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let noteCount: Int
    let meetingCount: Int
    let reminderCount: Int
    let notes: [ProjectNote]
    let meetings: [ProjectMeeting]
    let reminders: [ProjectReminder]
}

struct ProjectNote: Codable, Identifiable {
    let id: String
    let title: String?
    let createdAt: String

    var displayTitle: String {
        title ?? "Untitled Note"
    }
}

struct ProjectMeeting: Codable, Identifiable {
    let id: String
    let title: String?
    let date: String?

    var displayTitle: String {
        title ?? "Untitled Meeting"
    }
}

struct ProjectReminder: Codable, Identifiable {
    let id: String
    let title: String
    let dueDate: String?
    let priority: Int

    var priorityIcon: String {
        switch priority {
        case 9: return "exclamationmark.3"
        case 5: return "exclamationmark.2"
        case 1: return "exclamationmark"
        default: return ""
        }
    }
}

// MARK: - Create/Update Requests

struct ProjectCreateRequest: Codable {
    let name: String
    let description: String?
}

struct ProjectUpdateRequest: Codable {
    let name: String?
    let description: String?
    let status: String?
}
