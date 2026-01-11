//
//  MessageBubbleView.swift
//  Kai
//
//  Individual message bubble view for chat conversations.
//

import SwiftUI

struct MessageBubbleView: View {
    // MARK: - Properties

    let message: Message

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUserMessage {
                Spacer(minLength: 60)
                userMessageBubble
            } else {
                assistantMessageBubble
                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - User Message Bubble

    private var userMessageBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.content)
                .font(.body)
                .foregroundColor(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(MessageBubbleShape(isFromUser: true))

            // Timestamp
            Text(formatTime(message.createdAt))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.trailing, 4)
        }
    }

    // MARK: - Assistant Message Bubble

    private var assistantMessageBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Avatar
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                // Message content
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(bubbleBackgroundColor)
                    .clipShape(MessageBubbleShape(isFromUser: false))

                // Model indicator and timestamp
                HStack(spacing: 8) {
                    if let model = message.modelUsed {
                        modelBadge(model)
                    }

                    Text(formatTime(message.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - Avatar View

    private var avatarView: some View {
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
    }

    // MARK: - Model Badge

    private func modelBadge(_ model: String) -> some View {
        let displayName = modelDisplayName(model)
        let badgeColor = modelColor(model)

        return HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 6, height: 6)

            Text(displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Computed Properties

    private var isUserMessage: Bool {
        message.role == .user
    }

    private var bubbleBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
    }

    // MARK: - Helper Methods

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func modelDisplayName(_ model: String) -> String {
        let lowercased = model.lowercased()
        if lowercased.contains("haiku") {
            return "Haiku"
        } else if lowercased.contains("sonnet") {
            return "Sonnet"
        } else if lowercased.contains("opus") {
            return "Opus"
        } else {
            // Extract model name from full identifier
            if let lastPart = model.split(separator: "-").first {
                return String(lastPart).capitalized
            }
            return model
        }
    }

    private func modelColor(_ model: String) -> Color {
        let lowercased = model.lowercased()
        if lowercased.contains("haiku") {
            return .green
        } else if lowercased.contains("sonnet") {
            return .blue
        } else if lowercased.contains("opus") {
            return .purple
        } else {
            return .secondary
        }
    }
}

// MARK: - Message Bubble Shape

struct MessageBubbleShape: Shape {
    let isFromUser: Bool
    let cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return Path(path.cgPath)
    }

    private var corners: UIRectCorner {
        if isFromUser {
            return [.topLeft, .topRight, .bottomLeft]
        } else {
            return [.topLeft, .topRight, .bottomRight]
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
extension Message {
    static func preview(role: MessageRole, content: String, model: String? = nil) -> Message {
        Message(
            id: UUID(),
            role: role,
            content: content,
            toolCalls: nil,
            modelUsed: model,
            createdAt: Date()
        )
    }
}
#endif

// MARK: - Preview

#Preview("Conversation") {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubbleView(
                message: Message.preview(
                    role: .user,
                    content: "What's on my calendar today?"
                )
            )

            MessageBubbleView(
                message: Message.preview(
                    role: .assistant,
                    content: "You have 3 meetings today:\n\n1. Team standup at 9:00 AM\n2. Product review at 11:00 AM\n3. 1:1 with Sarah at 2:00 PM\n\nWould you like me to add any preparation time before these meetings?",
                    model: "claude-3-sonnet-20240229"
                )
            )

            MessageBubbleView(
                message: Message.preview(
                    role: .user,
                    content: "Yes, please add 15 minutes before the product review."
                )
            )

            MessageBubbleView(
                message: Message.preview(
                    role: .assistant,
                    content: "I'll propose adding a 15-minute preparation block before your product review. Should I create this event on your calendar?",
                    model: "claude-3-haiku-20240307"
                )
            )
        }
        .padding()
    }
    .background(Color(.systemBackground))
}

#Preview("Model Badges") {
    VStack(spacing: 16) {
        MessageBubbleView(
            message: Message.preview(
                role: .assistant,
                content: "Quick response using Haiku - the fastest model.",
                model: "claude-3-haiku-20240307"
            )
        )

        MessageBubbleView(
            message: Message.preview(
                role: .assistant,
                content: "Standard response using Sonnet - balanced performance.",
                model: "claude-3-sonnet-20240229"
            )
        )

        MessageBubbleView(
            message: Message.preview(
                role: .assistant,
                content: "Complex analysis using Opus - the most capable model.",
                model: "claude-3-opus-20240229"
            )
        )
    }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Dark Mode") {
    VStack(spacing: 16) {
        MessageBubbleView(
            message: Message.preview(
                role: .user,
                content: "How does dark mode look?"
            )
        )

        MessageBubbleView(
            message: Message.preview(
                role: .assistant,
                content: "Dark mode looks great! The message bubbles have proper contrast and the model badges are clearly visible.",
                model: "claude-3-sonnet-20240229"
            )
        )
    }
    .padding()
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}
