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
    @Published var error: String?

    private var cachedBriefings: [String: Briefing] = [:]

    var groupedBriefings: [String: [Briefing]] {
        Dictionary(grouping: briefings) { briefing in
            briefing.dateSection
        }
    }

    func loadBriefings() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Load today's briefing from API
        await generateBriefing()
    }

    func refresh() async {
        await loadBriefings()
    }

    func generateBriefing() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        do {
            let response: BriefingAPIResponse = try await APIClient.shared.request(
                .briefingsDaily,
                method: .get
            )

            let briefing = Briefing(from: response)

            // Update or add briefing
            if let existingIndex = briefings.firstIndex(where: { $0.dateKey == briefing.dateKey }) {
                briefings[existingIndex] = briefing
            } else {
                briefings.insert(briefing, at: 0)
            }
        } catch {
            self.error = error.localizedDescription
            #if DEBUG
            print("[BriefingsViewModel] Failed to generate briefing: \(error)")
            #endif
        }
    }

    func deleteBriefing(_ briefing: Briefing) async {
        briefings.removeAll { $0.id == briefing.id }
    }
}

// MARK: - API Response Models

struct BriefingAPIResponse: Codable {
    let date: String
    let briefing: BriefingData
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case date
        case briefing
        case generatedAt = "generated_at"
    }
}

struct BriefingData: Codable {
    let summary: String
    let events: [BriefingEvent]?
    let reminders: [BriefingReminder]?
    let followUps: [BriefingFollowUp]?
    let weather: BriefingWeather?
    let emails: BriefingEmails?

    enum CodingKeys: String, CodingKey {
        case summary
        case events
        case reminders
        case followUps = "follow_ups"
        case weather
        case emails
    }
}

struct BriefingEvent: Codable {
    let id: String?
    let summary: String?
    let title: String?
    let start: String?
    let end: String?
    let location: String?

    var displayTitle: String {
        title ?? summary ?? "Untitled Event"
    }
}

struct BriefingReminder: Codable {
    let id: String?
    let title: String
    let dueDate: String?
    let priority: Int?
    let projectName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueDate = "due_date"
        case priority
        case projectName = "project_name"
    }
}

struct BriefingFollowUp: Codable {
    let id: String?
    let title: String
    let dueDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueDate = "due_date"
    }
}

struct BriefingWeather: Codable {
    let description: String?
    let temperature: Double?
    let temperatureUnit: String?
    let conditions: String?

    enum CodingKeys: String, CodingKey {
        case description
        case temperature
        case temperatureUnit = "temperature_unit"
        case conditions
    }

    var displayString: String {
        if let desc = description {
            return desc
        }
        var parts: [String] = []
        if let conditions = conditions {
            parts.append(conditions)
        }
        if let temp = temperature {
            let unit = temperatureUnit ?? "F"
            parts.append("\(Int(temp))°\(unit)")
        }
        return parts.isEmpty ? "Weather data unavailable" : parts.joined(separator: ", ")
    }
}

struct BriefingEmails: Codable {
    let totalCount: Int?
    let unreadCount: Int?
    let highlights: [String]?

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case unreadCount = "unread_count"
        case highlights
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
    let dateKey: String

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

    // Initialize from API response
    init(from response: BriefingAPIResponse) {
        self.id = response.date
        self.dateKey = response.date
        self.title = "Daily Briefing"

        // Parse the summary - the backend returns Claude's text
        self.summary = response.briefing.summary

        // Convert events to display strings
        self.events = response.briefing.events?.map { event in
            var eventStr = event.displayTitle
            if let start = event.start {
                // Parse time from ISO string
                let timeStr = Briefing.formatEventTime(start)
                if !timeStr.isEmpty {
                    eventStr += " at \(timeStr)"
                }
            }
            return eventStr
        } ?? []

        // Convert reminders to display strings
        self.tasks = response.briefing.reminders?.map { reminder in
            var taskStr = reminder.title
            if let project = reminder.projectName {
                taskStr += " (\(project))"
            }
            return taskStr
        } ?? []

        // Convert follow-ups to display strings
        self.reminders = response.briefing.followUps?.map { $0.title } ?? []

        // Weather
        self.weather = response.briefing.weather?.displayString

        // Extract insights from summary if present, or use email highlights
        if let emails = response.briefing.emails, let highlights = emails.highlights, !highlights.isEmpty {
            self.insights = "Email: " + highlights.joined(separator: ". ")
        } else {
            self.insights = nil
        }

        // Parse created at time
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: response.generatedAt) {
            self.createdAt = date
        } else {
            self.createdAt = Date()
        }
    }

    // Manual initializer for compatibility
    init(
        id: String,
        title: String,
        summary: String,
        events: [String],
        tasks: [String],
        reminders: [String],
        weather: String?,
        insights: String?,
        createdAt: Date
    ) {
        self.id = id
        self.dateKey = id
        self.title = title
        self.summary = summary
        self.events = events
        self.tasks = tasks
        self.reminders = reminders
        self.weather = weather
        self.insights = insights
        self.createdAt = createdAt
    }

    private static func formatEventTime(_ isoString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date = isoFormatter.date(from: isoString)
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: isoString)
        }

        guard let eventDate = date else { return "" }

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return timeFormatter.string(from: eventDate)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BriefingsView()
    }
}
