import AppIntents
import Foundation
import SwiftUI

/// Main conversational intent for asking Kai anything
/// Supports multi-turn conversations with follow-up questions
@available(iOS 17.0, *)
struct AskKaiIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "Ask Kai"

    static var description = IntentDescription(
        "Ask Kai anything - from scheduling meetings to getting information",
        categoryName: "Chat",
        searchKeywords: ["ask", "question", "help", "kai", "assistant"]
    )

    static var openAppWhenRun = false

    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    // MARK: - Parameters

    @Parameter(
        title: "Message",
        description: "What would you like to ask Kai?",
        requestValueDialog: IntentDialog("What would you like to ask Kai?")
    )
    var message: String

    @Parameter(
        title: "Conversation ID",
        description: "ID to continue an existing conversation"
    )
    var conversationId: String?

    // MARK: - Initialization

    init() {}

    init(message: String, conversationId: String? = nil) {
        self.message = message
        self.conversationId = conversationId
    }

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = IntentAPIClient.shared

        do {
            // Send message to Kai
            let response = try await client.sendChatMessage(
                message: message,
                conversationId: conversationId
            )

            // Check if Kai is asking a follow-up question
            if response.requiresFollowUp == true,
               let followUpQuestion = response.followUpQuestion {
                // Request the follow-up response from the user
                let followUpAnswer = try await $message.requestValue(
                    IntentDialog(stringLiteral: "\(response.response)\n\n\(followUpQuestion)")
                )

                // Continue the conversation with the follow-up
                let continuationIntent = AskKaiIntent(
                    message: followUpAnswer,
                    conversationId: response.conversationId
                )

                return try await continuationIntent.perform()
            }

            // Return the response
            return .result(dialog: IntentDialog(stringLiteral: response.response))

        } catch let error as IntentAPIError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: IntentDialog("Sorry, I couldn't connect to Kai right now. Please try again."))
        }
    }
}

// MARK: - Parameter Summary

@available(iOS 17.0, *)
extension AskKaiIntent {
    static var parameterSummary: some ParameterSummary {
        Summary("Ask Kai \(\.$message)")
    }
}
