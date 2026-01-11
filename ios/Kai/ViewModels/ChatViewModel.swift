//
//  ChatViewModel.swift
//  Kai
//
//  Chat functionality view model using existing APIClient and models.
//

import Foundation
import Combine

// MARK: - Queued Message for Offline Support

struct QueuedMessage: Codable, Identifiable {
    let id: UUID
    let content: String
    let conversationId: UUID?
    let createdAt: Date

    init(content: String, conversationId: UUID?) {
        self.id = UUID()
        self.content = content
        self.conversationId = conversationId
        self.createdAt = Date()
    }
}

// MARK: - ChatViewModel

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var messages: [Message] = []
    @Published var conversations: [ConversationSummary] = []
    @Published var currentConversationId: UUID?
    @Published var isLoading: Bool = false
    @Published var inputText: String = ""
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var queuedMessages: [QueuedMessage] = []
    private let queueKey = "kai_queued_messages"
    private var cancellables = Set<AnyCancellable>()
    private let apiClient = APIClient.shared
    private let networkMonitor = NetworkMonitor.shared

    // MARK: - Initialization

    init() {
        loadQueuedMessages()
        setupNetworkObserver()
    }

    // MARK: - Network Observer

    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                Task {
                    await self?.retryQueuedMessages()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Send a message to Kai
    func sendMessage() async {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // Clear input immediately for better UX
        let messageContent = trimmedText
        inputText = ""
        errorMessage = nil

        // Add optimistic user message
        let userMessage = Message(
            id: UUID(),
            role: .user,
            content: messageContent,
            toolCalls: nil,
            modelUsed: nil,
            createdAt: Date()
        )
        messages.append(userMessage)

        // Check network connectivity
        guard networkMonitor.isConnected else {
            queueMessage(content: messageContent, conversationId: currentConversationId)
            errorMessage = "Message queued for sending when online"
            return
        }

        isLoading = true

        do {
            let request = ChatRequest(
                message: messageContent,
                conversationId: currentConversationId,
                source: .ios
            )

            let response: ChatResponse = try await apiClient.request(
                .chat,
                method: .post,
                body: request
            )

            // Update conversation ID if this was a new conversation
            if currentConversationId == nil {
                currentConversationId = response.conversationId
            }

            // Extract model name from modelInfo
            let modelName = response.modelInfo?.model

            // Add assistant response
            let assistantMessage = Message(
                id: UUID(),
                role: .assistant,
                content: response.response,
                toolCalls: nil,
                modelUsed: modelName,
                createdAt: Date()
            )
            messages.append(assistantMessage)

            // Refresh conversations list
            await loadConversations()

        } catch let error as APIError {
            errorMessage = error.localizedDescription
            // Remove optimistic message on failure
            if let index = messages.lastIndex(where: { $0.id == userMessage.id }) {
                messages.remove(at: index)
            }
            // Queue for retry if network related
            if case .notAuthenticated = error {
                // Don't queue auth errors
            } else {
                queueMessage(content: messageContent, conversationId: currentConversationId)
            }
        } catch {
            errorMessage = error.localizedDescription
            // Remove optimistic message on failure
            if let index = messages.lastIndex(where: { $0.id == userMessage.id }) {
                messages.remove(at: index)
            }
            // Queue for retry
            queueMessage(content: messageContent, conversationId: currentConversationId)
        }

        isLoading = false
    }

    /// Load all conversations for the current user
    func loadConversations() async {
        do {
            let response: [Conversation] = try await apiClient.getConversations()

            // Convert to ConversationSummary
            conversations = response.map { item in
                ConversationSummary(
                    id: item.id,
                    title: item.title,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    messageCount: item.messages.count
                )
            }
        } catch let error as APIError {
            // 404 just means no conversations yet - not an error
            if case .notFound = error {
                conversations = []
            } else {
                errorMessage = "Failed to load conversations: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    /// Load a specific conversation with all messages
    func loadConversation(id: UUID) async {
        isLoading = true

        do {
            let conversation: Conversation = try await apiClient.getConversation(id: id)

            currentConversationId = conversation.id

            // Use the messages directly from the conversation
            messages = conversation.messages
        } catch {
            errorMessage = "Failed to load conversation: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Start a new conversation
    func startNewConversation() {
        currentConversationId = nil
        messages = []
        inputText = ""
        errorMessage = nil
    }

    /// Retry sending queued messages
    func retryQueuedMessages() async {
        guard networkMonitor.isConnected else { return }

        let messagesToRetry = queuedMessages
        queuedMessages = []
        saveQueuedMessages()

        for queuedMessage in messagesToRetry {
            inputText = queuedMessage.content
            currentConversationId = queuedMessage.conversationId
            await sendMessage()
        }
    }

    /// Check if there are queued messages
    var hasQueuedMessages: Bool {
        !queuedMessages.isEmpty
    }

    /// Number of queued messages
    var queuedMessageCount: Int {
        queuedMessages.count
    }

    // MARK: - Private Methods

    private func queueMessage(content: String, conversationId: UUID?) {
        let queued = QueuedMessage(content: content, conversationId: conversationId)
        queuedMessages.append(queued)
        saveQueuedMessages()
    }

    private func saveQueuedMessages() {
        if let data = try? JSONEncoder().encode(queuedMessages) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }

    private func loadQueuedMessages() {
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let messages = try? JSONDecoder().decode([QueuedMessage].self, from: data) {
            queuedMessages = messages
        }
    }
}
