//
//  MeetingDetailView.swift
//  Kai
//
//  Created by Kai on 2024.
//

import SwiftUI

struct MeetingDetailView: View {

    // MARK: - Properties

    let meeting: Meeting
    @ObservedObject var viewModel: MeetingsViewModel

    // MARK: - State

    @State private var selectedTab: DetailTab = .summary
    @State private var refreshedMeeting: Meeting?

    // MARK: - Types

    enum DetailTab: String, CaseIterable {
        case summary = "Summary"
        case transcript = "Transcript"
    }

    // MARK: - Computed Properties

    private var currentMeeting: Meeting {
        refreshedMeeting ?? meeting
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Tab selector
            Picker("View", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            ScrollView {
                switch selectedTab {
                case .summary:
                    summaryView
                case .transcript:
                    transcriptView
                }
            }
        }
        .navigationTitle(currentMeeting.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if let updated = await viewModel.refreshMeeting(id: meeting.id) {
                            refreshedMeeting = updated
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 12) {
            // Meeting icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "waveform")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
            }

            // Title
            Text(currentMeeting.displayTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            // Date and time
            if let dateRange = currentMeeting.dateRangeDisplay {
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(currentMeeting.displayDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Status badges
            HStack(spacing: 16) {
                StatusIndicator(
                    icon: "text.alignleft",
                    label: "Transcript",
                    isActive: currentMeeting.hasTranscript
                )

                StatusIndicator(
                    icon: "sparkles",
                    label: "Summary",
                    isActive: currentMeeting.hasSummary
                )
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Summary View

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let summary = currentMeeting.summary {
                // Discussion section
                if let discussion = summary.discussion, !discussion.isEmpty {
                    SummarySection(title: "Discussion", icon: "bubble.left.and.bubble.right") {
                        Text(discussion)
                            .font(.body)
                    }
                }

                // Key Points section
                if let keyPoints = summary.keyPoints, !keyPoints.isEmpty {
                    SummarySection(title: "Key Points", icon: "list.bullet") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(.blue)
                                        .padding(.top, 6)

                                    Text(point)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }

                // Action Items section
                if let actionItems = summary.actionItems, !actionItems.isEmpty {
                    SummarySection(title: "Action Items", icon: "checkmark.circle") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(actionItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "square")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .padding(.top, 3)

                                    Text(item)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }

                // Attendees section
                if let attendees = summary.attendees, !attendees.isEmpty {
                    SummarySection(title: "Attendees", icon: "person.2") {
                        FlowLayout(spacing: 8) {
                            ForEach(attendees, id: \.self) { attendee in
                                Text(attendee)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Show empty state if summary exists but has no content
                if summary.isEmpty {
                    noSummaryView
                }
            } else {
                noSummaryView
            }
        }
        .padding()
    }

    private var noSummaryView: some View {
        ContentUnavailableView {
            Label("No Summary", systemImage: "sparkles")
        } description: {
            Text("AI summary is not yet available for this meeting.")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Transcript View

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let transcript = currentMeeting.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding()
            } else {
                ContentUnavailableView {
                    Label("No Transcript", systemImage: "text.alignleft")
                } description: {
                    Text("Transcript is not yet available for this meeting.")
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
}

// MARK: - Summary Section

struct SummarySection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.blue)

                Text(title)
                    .font(.headline)
            }

            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? "\(icon).fill" : icon)
                .font(.subheadline)

            Text(label)
                .font(.subheadline)
        }
        .foregroundStyle(isActive ? .green : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isActive ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing

                self.size.width = max(self.size.width, currentX - spacing)
            }

            self.size.height = currentY + lineHeight
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MeetingDetailView(
            meeting: Meeting(
                id: UUID(),
                eventTitle: "Product Planning Meeting",
                eventStart: Date(),
                eventEnd: Date().addingTimeInterval(3600),
                transcript: "This is a sample transcript of the meeting discussion...",
                summary: MeetingSummary(
                    discussion: "The team discussed the upcoming product roadmap and prioritized features for Q2.",
                    keyPoints: [
                        "New user onboarding flow to be redesigned",
                        "Performance improvements are top priority",
                        "Mobile app launch planned for March"
                    ],
                    actionItems: [
                        "Design team to create wireframes by Friday",
                        "Engineering to scope performance work",
                        "PM to update roadmap document"
                    ],
                    attendees: ["John", "Sarah", "Mike", "Emily"]
                ),
                createdAt: Date()
            ),
            viewModel: MeetingsViewModel()
        )
    }
}
