import SwiftUI

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showingEventDetail: CalendarEvent?
    @State private var showingNewEvent = false

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode picker
                Picker("View Mode", selection: $viewModel.viewMode) {
                    ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Calendar header
                calendarHeader

                // Calendar grid
                if viewModel.viewMode == .month {
                    monthView
                } else {
                    weekView
                }

                Divider()
                    .padding(.top, 8)

                // Events list for selected day
                eventsList
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        viewModel.goToToday()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadEvents(for: Date())
            }
            .sheet(item: $showingEventDetail) { event in
                EventDetailSheet(event: event, viewModel: viewModel)
            }
            .sheet(isPresented: $showingNewEvent) {
                NewEventSheet(viewModel: viewModel, selectedDate: viewModel.selectedDate)
            }
        }
    }

    // MARK: - Calendar Header
    private var calendarHeader: some View {
        HStack {
            Button {
                if viewModel.viewMode == .month {
                    viewModel.goToPreviousMonth()
                } else {
                    viewModel.goToPreviousWeek()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Text(viewModel.currentMonthName)
                .font(.headline)

            Spacer()

            Button {
                if viewModel.viewMode == .month {
                    viewModel.goToNextMonth()
                } else {
                    viewModel.goToNextWeek()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Month View
    private var monthView: some View {
        VStack(spacing: 8) {
            // Weekday headers
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)

            // Calendar days
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.currentMonthDates, id: \.self) { date in
                    DayCell(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                        isToday: Calendar.current.isDateInToday(date),
                        isCurrentMonth: Calendar.current.isDate(date, equalTo: viewModel.selectedDate, toGranularity: .month),
                        hasEvents: viewModel.hasEvents(on: date),
                        eventCount: viewModel.eventCount(on: date)
                    )
                    .onTapGesture {
                        viewModel.selectDate(date)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Week View
    private var weekView: some View {
        VStack(spacing: 8) {
            // Weekday headers with dates
            HStack(spacing: 4) {
                ForEach(viewModel.currentWeekDates, id: \.self) { date in
                    VStack(spacing: 4) {
                        Text(weekdayLetter(for: date))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        DayCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                            isToday: Calendar.current.isDateInToday(date),
                            isCurrentMonth: true,
                            hasEvents: viewModel.hasEvents(on: date),
                            eventCount: viewModel.eventCount(on: date)
                        )
                        .onTapGesture {
                            viewModel.selectDate(date)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Events List
    private var eventsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDateTitle)
                    .font(.headline)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            if viewModel.eventsForSelectedDate.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.eventsForSelectedDate) { event in
                            EventRow(event: event)
                                .onTapGesture {
                                    showingEventDetail = event
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Helpers
    private var selectedDateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: viewModel.selectedDate)
    }

    private func weekdayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Day Cell
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let hasEvents: Bool
    let eventCount: Int

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                } else if isToday {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                }

                Text(dayNumber)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(isToday || isSelected ? .semibold : .regular)
                    .foregroundStyle(
                        isSelected ? .white :
                            (isCurrentMonth ? .primary : Color.secondary.opacity(0.5))
                    )
            }
            .frame(width: 36, height: 36)

            // Event indicator dots
            if hasEvents {
                HStack(spacing: 2) {
                    ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.8) : Color.accentColor)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 6)
            } else {
                Spacer()
                    .frame(height: 6)
            }
        }
    }
}

// MARK: - Event Row
struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(event.formattedTimeRange, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let location = event.location {
                        Label(location, systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Event Detail Sheet
struct EventDetailSheet: View {
    let event: CalendarEvent
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let calendarName = event.calendarName {
                            Text(calendarName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.formattedDate)
                            Text(event.formattedTimeRange)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.accentColor)
                    }

                    if let location = event.location {
                        Label {
                            Text(location)
                        } icon: {
                            Image(systemName: "location")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                if let description = event.description, !description.isEmpty {
                    Section("Notes") {
                        Text(description)
                            .font(.body)
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Event", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Event", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                }
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                EditEventSheet(event: event, viewModel: viewModel) {
                    dismiss()
                }
            }
            .confirmationDialog(
                "Delete Event",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteEvent()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(event.title)\"? This cannot be undone.")
            }
            .overlay {
                if isDeleting {
                    ProgressView("Deleting...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func deleteEvent() {
        isDeleting = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.deleteEvent(id: event.id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isDeleting = false
                }
            }
        }
    }
}

// MARK: - New Event Sheet
struct NewEventSheet: View {
    @ObservedObject var viewModel: CalendarViewModel
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    init(viewModel: CalendarViewModel, selectedDate: Date) {
        self.viewModel = viewModel
        self.selectedDate = selectedDate

        // Initialize dates based on selected date
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let now = Date()
        let currentComponents = calendar.dateComponents([.hour, .minute], from: now)
        components.hour = currentComponents.hour
        components.minute = 0

        let start = calendar.date(from: components) ?? now
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? now

        _startDate = State(initialValue: start)
        _endDate = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event Title", text: $title)
                }

                Section {
                    Toggle("All Day", isOn: $isAllDay)

                    DatePicker(
                        "Starts",
                        selection: $startDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )

                    DatePicker(
                        "Ends",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                }

                Section {
                    TextField("Location", text: $location)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveEvent()
                    }
                    .disabled(title.isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView("Saving...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func saveEvent() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.createEvent(
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    location: location.isEmpty ? nil : location,
                    notes: notes.isEmpty ? nil : notes
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Edit Event Sheet
struct EditEventSheet: View {
    let event: CalendarEvent
    @ObservedObject var viewModel: CalendarViewModel
    var onSave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay: Bool
    @State private var location: String
    @State private var notes: String
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    init(event: CalendarEvent, viewModel: CalendarViewModel, onSave: (() -> Void)? = nil) {
        self.event = event
        self.viewModel = viewModel
        self.onSave = onSave

        _title = State(initialValue: event.title)
        _startDate = State(initialValue: event.start)
        _endDate = State(initialValue: event.end)
        _isAllDay = State(initialValue: event.isAllDay)
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: event.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event Title", text: $title)
                }

                Section {
                    Toggle("All Day", isOn: $isAllDay)

                    DatePicker(
                        "Starts",
                        selection: $startDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )

                    DatePicker(
                        "Ends",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                }

                Section {
                    TextField("Location", text: $location)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveEvent()
                    }
                    .disabled(title.isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView("Saving...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func saveEvent() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.updateEvent(
                    id: event.id,
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    location: location.isEmpty ? nil : location,
                    notes: notes.isEmpty ? nil : notes
                )
                await MainActor.run {
                    onSave?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview
#Preview {
    CalendarView()
}
