import SwiftUI

struct ConversationListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ConversationListViewModel()

    let onConversationSelected: (ConversationSummary) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    LoadingView(message: "Loading conversations...")
                } else if viewModel.conversations.isEmpty {
                    EmptyConversationsView()
                } else {
                    conversationList
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.createNewConversation()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(viewModel.groupedConversations.keys.sorted().reversed(), id: \.self) { section in
                Section(header: Text(section)) {
                    ForEach(viewModel.groupedConversations[section] ?? []) { conversation in
                        ConversationRowView(conversation: conversation)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onConversationSelected(conversation)
                                dismiss()
                            }
                    }
                    .onDelete { indexSet in
                        deleteConversations(at: indexSet, in: section)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteConversations(at indexSet: IndexSet, in section: String) {
        guard let conversations = viewModel.groupedConversations[section] else { return }

        for index in indexSet {
            let conversation = conversations[index]
            Task {
                await viewModel.deleteConversation(conversation)
            }
        }
    }
}

// MARK: - Conversation Row View

struct ConversationRowView: View {
    let conversation: ConversationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(conversation.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(conversation.formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                if conversation.messageCount > 0 {
                    Label("\(conversation.messageCount) messages", systemImage: "message")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State View

struct EmptyConversationsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Conversations")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start a new conversation with Kai to see it here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - View Model

@MainActor
class ConversationListViewModel: ObservableObject {
    @Published var conversations: [ConversationSummary] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    var groupedConversations: [String: [ConversationSummary]] {
        Dictionary(grouping: conversations) { conversation in
            conversation.dateSection
        }
    }

    init() {
        Task {
            await loadConversations()
        }
    }

    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try await APIClient.shared.getConversations()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func refresh() async {
        await loadConversations()
    }

    func deleteConversation(_ conversation: ConversationSummary) async {
        do {
            try await APIClient.shared.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func createNewConversation() {
        // Post notification to create new conversation
        NotificationCenter.default.post(name: .createNewConversation, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let createNewConversation = Notification.Name("createNewConversation")
}

// MARK: - Preview

#Preview {
    ConversationListView { conversation in
        print("Selected: \(conversation.displayTitle)")
    }
}
