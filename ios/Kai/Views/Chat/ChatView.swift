//
//  ChatView.swift
//  Kai
//
//  Main chat interface for conversing with Kai.
//

import SwiftUI

struct ChatView: View {
    // MARK: - State

    @StateObject private var viewModel = ChatViewModel()
    @State private var showConversationHistory: Bool = false
    @State private var isAnimating: Bool = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Focus State

    @FocusState private var isInputFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages Area
                messagesScrollView

                // Divider
                Divider()

                // Input Area
                inputArea
            }
            .navigationTitle("Kai")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showConversationHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .medium))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.startNewConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showConversationHistory) {
                ConversationHistorySheet(
                    viewModel: viewModel,
                    isPresented: $showConversationHistory
                )
            }
            .task {
                await viewModel.loadConversations()
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    isAnimating = true
                }
            }
        }
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        emptyStateView
                            .padding(.top, 80)
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }

                        // Loading indicator for assistant response
                        if viewModel.isLoading {
                            typingIndicator
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("typing-indicator", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // App Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1 : 0.8)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(isAnimating ? 1 : 0)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isAnimating)

            VStack(spacing: 8) {
                Text("Start a Conversation")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Ask Kai anything about your schedule,\ntasks, notes, or meetings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 10)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: isAnimating)

            // Suggestion chips
            VStack(spacing: 10) {
                suggestionChip("What's on my calendar today?")
                suggestionChip("Summarize my last meeting")
                suggestionChip("What tasks are due this week?")
            }
            .padding(.top, 8)
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 10)
            .animation(.easeOut(duration: 0.5).delay(0.3), value: isAnimating)
        }
        .padding()
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            viewModel.inputText = text
            Task {
                await viewModel.sendMessage()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text(text)
                    .font(.subheadline)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(20)
        }
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Text("K")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )

            // Typing dots
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    TypingDot(delay: Double(index) * 0.15)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemGray6))
            .cornerRadius(18)

            Spacer()
        }
        .padding(.leading, 4)
        .id("typing-indicator")
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            // Queued messages indicator
            if viewModel.hasQueuedMessages {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text("\(viewModel.queuedMessageCount) message(s) queued")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Spacer()

                    Button("Retry") {
                        Task {
                            await viewModel.retryQueuedMessages()
                        }
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // Error message
            if let error = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input field
            HStack(alignment: .bottom, spacing: 12) {
                // Text field
                TextField("Message Kai...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .focused($isInputFocused)

                // Send button
                Button {
                    Task {
                        await viewModel.sendMessage()
                    }
                    isInputFocused = false
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            canSend
                                ? LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.3)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                        .animation(.easeInOut(duration: 0.2), value: canSend)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Computed Properties

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading
    }
}

// MARK: - Typing Dot

struct TypingDot: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.0 : 0.5)
            .opacity(isAnimating ? 1.0 : 0.3)
            .animation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Conversation History Sheet

struct ConversationHistorySheet: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                if viewModel.conversations.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start chatting with Kai to see your conversation history here.")
                    )
                } else {
                    ForEach(viewModel.conversations) { conversation in
                        Button {
                            Task {
                                await viewModel.loadConversation(id: conversation.id)
                                isPresented = false
                            }
                        } label: {
                            ConversationSummaryRowView(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .fontWeight(.medium)
                }
            }
            .task {
                await viewModel.loadConversations()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Conversation Summary Row View

struct ConversationSummaryRowView: View {
    let conversation: ConversationSummary

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "bubble.left.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 18))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formatDate(conversation.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if conversation.messageCount > 0 {
                        Text("\(conversation.messageCount) messages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview {
    ChatView()
}
