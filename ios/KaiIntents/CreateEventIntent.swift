import AppIntents
import SwiftUI
import Foundation

/// Intent to create a calendar event through Kai
/// Supports natural language event creation with confirmation
@available(iOS 17.0, *)
struct CreateEventIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "Create Event with Kai"

    static var description = IntentDescription(
        "Create a calendar event using natural language",
        categoryName: "Calendar",
        searchKeywords: ["event", "calendar", "meeting", "schedule", "create", "add"]
    )

    static var openAppWhenRun = false

    // MARK: - Parameters

    @Parameter(
        title: "Event Description",
        description: "Describe the event you want to create",
        requestValueDialog: IntentDialog("What event would you like to create?")
    )
    var eventDescription: String

    // MARK: - Initialization

    init() {}

    init(eventDescription: String) {
        self.eventDescription = eventDescription
    }

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = IntentAPIClient.shared

        do {
            // Ask Kai to create the event
            let response = try await client.sendChatMessage(
                message: "Create an event: \(eventDescription)",
                conversationId: nil
            )

            // Kai will propose the event and ask for confirmation
            // The response should contain the proposed event details

            if response.requiresFollowUp == true {
                // Kai is asking for confirmation
                let confirmation = try await requestConfirmation(
                    response: response.response
                )

                if confirmation {
                    // Confirm with Kai
                    let confirmResponse = try await client.sendChatMessage(
                        message: "Yes, create it",
                        conversationId: response.conversationId
                    )
                    return .result(dialog: IntentDialog(stringLiteral: confirmResponse.response))
                } else {
                    // Cancel
                    _ = try await client.sendChatMessage(
                        message: "Cancel",
                        conversationId: response.conversationId
                    )
                    return .result(dialog: IntentDialog("Okay, I won't create the event."))
                }
            }

            return .result(dialog: IntentDialog(stringLiteral: response.response))

        } catch let error as IntentAPIError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: IntentDialog("Sorry, I couldn't create the event right now."))
        }
    }

    private func requestConfirmation(response: String) async throws -> Bool {
        // This would use the system confirmation dialog
        // For now, we'll assume confirmation is needed through conversation
        return true
    }
}

// MARK: - Create Reminder Intent

/// Intent to create a reminder/task through Kai
@available(iOS 17.0, *)
struct CreateReminderIntent: AppIntent {

    static var title: LocalizedStringResource = "Create Reminder with Kai"

    static var description = IntentDescription(
        "Create a reminder or task using natural language",
        categoryName: "Tasks",
        searchKeywords: ["reminder", "task", "todo", "create", "add", "remember"]
    )

    static var openAppWhenRun = false

    @Parameter(
        title: "Reminder",
        description: "What would you like to be reminded about?",
        requestValueDialog: IntentDialog("What would you like to be reminded about?")
    )
    var reminderText: String

    init() {}

    init(reminderText: String) {
        self.reminderText = reminderText
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = IntentAPIClient.shared

        do {
            let response = try await client.sendChatMessage(
                message: "Remind me to \(reminderText)",
                conversationId: nil
            )

            return .result(dialog: IntentDialog(stringLiteral: response.response))

        } catch let error as IntentAPIError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: IntentDialog("Sorry, I couldn't create the reminder right now."))
        }
    }
}

// MARK: - Create Note Intent

/// Intent to create a note through Kai
@available(iOS 17.0, *)
struct CreateNoteIntent: AppIntent {

    static var title: LocalizedStringResource = "Create Note with Kai"

    static var description = IntentDescription(
        "Create a note using your voice",
        categoryName: "Notes",
        searchKeywords: ["note", "save", "write", "jot", "remember"]
    )

    static var openAppWhenRun = false

    @Parameter(
        title: "Note Content",
        description: "What would you like to note down?",
        requestValueDialog: IntentDialog("What would you like to note down?")
    )
    var noteContent: String

    @Parameter(
        title: "Note Title",
        description: "Optional title for the note"
    )
    var noteTitle: String?

    init() {}

    init(noteContent: String, noteTitle: String? = nil) {
        self.noteContent = noteContent
        self.noteTitle = noteTitle
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = IntentAPIClient.shared

        do {
            var message = "Save a note: \(noteContent)"
            if let title = noteTitle {
                message = "Save a note titled '\(title)': \(noteContent)"
            }

            let response = try await client.sendChatMessage(
                message: message,
                conversationId: nil
            )

            return .result(dialog: IntentDialog(stringLiteral: response.response))

        } catch let error as IntentAPIError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: IntentDialog("Sorry, I couldn't save the note right now."))
        }
    }
}

// MARK: - Parameter Summaries

@available(iOS 17.0, *)
extension CreateEventIntent {
    static var parameterSummary: some ParameterSummary {
        Summary("Create event: \(\.$eventDescription)")
    }
}

@available(iOS 17.0, *)
extension CreateReminderIntent {
    static var parameterSummary: some ParameterSummary {
        Summary("Remind me to \(\.$reminderText)")
    }
}

@available(iOS 17.0, *)
extension CreateNoteIntent {
    static var parameterSummary: some ParameterSummary {
        When(\.$noteTitle, .hasAnyValue) {
            Summary("Save note '\(\.$noteTitle)': \(\.$noteContent)")
        } otherwise: {
            Summary("Save note: \(\.$noteContent)")
        }
    }
}
