import SwiftUI

struct BriefingsView: View {
    @StateObject private var viewModel = BriefingsViewModel()
    @State private var selectedBriefing: Briefing?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.briefings.isEmpty {
                ProgressView("Loading briefings...")
            } else if viewModel.briefings.isEmpty {
                emptyStateView
            } else {
                briefingsList
            }
        }
        .navigationTitle("Briefings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.generateBriefing()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.isGenerating)
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $selectedBriefing) { briefing in
            BriefingDetailView(briefing: briefing)
        }
        .task {
            await viewModel.loadBriefings()
        }
    }

    private var briefingsList: some View {
        List {
            if viewModel.isGenerating {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Generating briefing...")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            ForEach(viewModel.groupedBriefings.keys.sorted().reversed(), id: \.self) { section in
                Section(header: Text(section)) {
                    ForEach(viewModel.groupedBriefings[section] ?? []) { briefing in
                        BriefingRowView(briefing: briefing)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedBriefing = briefing
                            }
                    }
                    .onDelete { indexSet in
                        deleteBriefings(at: indexSet, in: section)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Briefings")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Generate a briefing to get a summary of your day, upcoming events, and important tasks.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task {
                    await viewModel.generateBriefing()
                }
            } label: {
                Label("Generate Briefing", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            .disabled(viewModel.isGenerating)
        }
    }

    private func deleteBriefings(at indexSet: IndexSet, in section: String) {
        guard let briefings = viewModel.groupedBriefings[section] else { return }

        for index in indexSet {
            let briefing = briefings[index]
            Task {
                await viewModel.deleteBriefing(briefing)
            }
        }
    }
}

// MARK: - Briefing Row View

struct BriefingRowView: View {
    let briefing: Briefing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(briefing.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(briefing.formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(briefing.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)

            HStack(spacing: 12) {
                if briefing.eventCount > 0 {
                    Label("\(briefing.eventCount) events", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                if briefing.taskCount > 0 {
                    Label("\(briefing.taskCount) tasks", systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                if briefing.reminderCount > 0 {
                    Label("\(briefing.reminderCount) reminders", systemImage: "bell")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Briefing Detail View

struct BriefingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let briefing: Briefing

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(briefing.formattedDate)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(briefing.summary)
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Events section
                    if !briefing.events.isEmpty {
                        BriefingSectionView(
                            title: "Today's Events",
                            icon: "calendar",
                            iconColor: .blue
                        ) {
                            ForEach(briefing.events, id: \.self) { event in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                    Text(event)
                                        .font(.body)
                                }
                            }
                        }
                    }

                    // Tasks section
                    if !briefing.tasks.isEmpty {
                        BriefingSectionView(
                            title: "Tasks",
                            icon: "checkmark.circle",
                            iconColor: .green
                        ) {
                            ForEach(briefing.tasks, id: \.self) { task in
                                HStack(spacing: 12) {
                                    Image(systemName: "circle")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text(task)
                                        .font(.body)
                                }
                            }
                        }
                    }

                    // Reminders section
                    if !briefing.reminders.isEmpty {
                        BriefingSectionView(
                            title: "Reminders",
                            icon: "bell",
                            iconColor: .orange
                        ) {
                            ForEach(briefing.reminders, id: \.self) { reminder in
                                HStack(spacing: 12) {
                                    Image(systemName: "bell.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    Text(reminder)
                                        .font(.body)
                                }
                            }
                        }
                    }

                    // Weather section
                    if let weather = briefing.weather {
                        BriefingSectionView(
                            title: "Weather",
                            icon: "cloud.sun",
                            iconColor: .cyan
                        ) {
                            Text(weather)
                                .font(.body)
                        }
                    }

                    // Insights section
                    if let insights = briefing.insights {
                        BriefingSectionView(
                            title: "Insights",
                            icon: "lightbulb",
                            iconColor: .yellow
                        ) {
                            Text(insights)
                                .font(.body)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(briefing.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Share functionality
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Briefing Section View

struct BriefingSectionView<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 4)
        }
    }
}

// MARK: - Briefings View Model

@MainActor
class BriefingsViewModel: ObservableObject {
    @Published var briefings: [Briefing] = []
    @Published var isLoading = false
    @Published var isGenerating = false

    var groupedBriefings: [String: [Briefing]] {
        Dictionary(grouping: briefings) { briefing in
            briefing.dateSection
        }
    }

    func loadBriefings() async {
        isLoading = true
        defer { isLoading = false }

        // TODO: Replace with actual API call when backend supports briefings
        // For now, use sample data
        try? await Task.sleep(nanoseconds: 500_000_000)
        briefings = Briefing.samples
    }

    func refresh() async {
        await loadBriefings()
    }

    func generateBriefing() async {
        isGenerating = true
        defer { isGenerating = false }

        // TODO: Replace with actual API call when backend supports briefings
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let newBriefing = Briefing(
            id: UUID().uuidString,
            title: "Your Daily Briefing",
            summary: "Here's what you need to know for today.",
            events: ["Team standup at 9:00 AM", "Product review at 2:00 PM"],
            tasks: ["Review PR #123", "Update documentation"],
            reminders: ["Call dentist"],
            weather: "Partly cloudy, 72°F",
            insights: "You have a busy afternoon - consider blocking focus time this morning.",
            createdAt: Date()
        )
        briefings.insert(newBriefing, at: 0)
    }

    func deleteBriefing(_ briefing: Briefing) async {
        briefings.removeAll { $0.id == briefing.id }
        // TODO: Add API call when backend supports briefings
    }
}

// MARK: - Briefing Model

struct Briefing: Identifiable {
    let id: String
    let title: String
    let summary: String
    let events: [String]
    let tasks: [String]
    let reminders: [String]
    let weather: String?
    let insights: String?
    let createdAt: Date

    var eventCount: Int { events.count }
    var taskCount: Int { tasks.count }
    var reminderCount: Int { reminders.count }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var dateSection: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(createdAt) {
            return "Today"
        } else if calendar.isDateInYesterday(createdAt) {
            return "Yesterday"
        } else if calendar.isDate(createdAt, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: createdAt)
        }
    }

    static let samples: [Briefing] = [
        Briefing(
            id: "1",
            title: "Morning Briefing",
            summary: "You have 3 meetings today and 5 tasks to complete.",
            events: ["Team standup at 9:00 AM", "Product review at 11:00 AM", "1:1 with Sarah at 2:00 PM"],
            tasks: ["Review PR #123", "Update documentation", "Prepare demo", "Send weekly report", "Review budget"],
            reminders: ["Call dentist at 4 PM", "Pick up dry cleaning"],
            weather: "Sunny, 75°F",
            insights: "Your afternoon is packed - consider preparing for meetings this morning.",
            createdAt: Date()
        ),
        Briefing(
            id: "2",
            title: "Yesterday's Summary",
            summary: "You completed 4 tasks and attended 2 meetings.",
            events: ["Design review", "Sprint planning"],
            tasks: ["Completed code review", "Fixed bug #456", "Updated tests", "Deployed to staging"],
            reminders: [],
            weather: nil,
            insights: "Great productivity! You're ahead on your sprint goals.",
            createdAt: Date().addingTimeInterval(-86400)
        )
    ]
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BriefingsView()
    }
}
