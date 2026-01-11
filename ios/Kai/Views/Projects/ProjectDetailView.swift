//
//  ProjectDetailView.swift
//  Kai
//
//  Detailed view of a single project with all related items.
//

import SwiftUI

struct ProjectDetailView: View {
    let projectId: UUID
    @ObservedObject var viewModel: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var editName = ""
    @State private var editDescription = ""

    var body: some View {
        Group {
            if viewModel.isLoadingDetail {
                ProgressView("Loading project...")
            } else if let project = viewModel.selectedProject {
                projectDetailContent(project)
            } else {
                ContentUnavailableView(
                    "Project Not Found",
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
        .navigationTitle(viewModel.selectedProject?.name ?? "Project")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if let project = viewModel.selectedProject {
                            editName = project.name
                            editDescription = project.description ?? ""
                            showEditSheet = true
                        }
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Divider()

                    if viewModel.selectedProject?.status == "active" {
                        Button {
                            Task {
                                _ = await viewModel.completeProject(id: projectId)
                                await viewModel.loadProjectDetail(id: projectId)
                            }
                        } label: {
                            Label("Mark Complete", systemImage: "checkmark.circle")
                        }

                        Button {
                            Task {
                                _ = await viewModel.archiveProject(id: projectId)
                                await viewModel.loadProjectDetail(id: projectId)
                            }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    } else {
                        Button {
                            Task {
                                _ = await viewModel.reactivateProject(id: projectId)
                                await viewModel.loadProjectDetail(id: projectId)
                            }
                        } label: {
                            Label("Reactivate", systemImage: "arrow.uturn.left")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable {
            await viewModel.loadProjectDetail(id: projectId)
        }
        .sheet(isPresented: $showEditSheet) {
            editProjectSheet
        }
        .task {
            await viewModel.loadProjectDetail(id: projectId)
        }
        .onDisappear {
            viewModel.clearSelectedProject()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func projectDetailContent(_ project: ProjectDetail) -> some View {
        List {
            // Status header
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let description = project.description, !description.isEmpty {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 16) {
                            statBadge(count: project.reminderCount, label: "Reminders", icon: "checklist")
                            statBadge(count: project.noteCount, label: "Notes", icon: "note.text")
                            statBadge(count: project.meetingCount, label: "Meetings", icon: "person.3")
                        }
                        .padding(.top, 4)
                    }
                }
            }

            // Reminders Section
            if !project.reminders.isEmpty {
                Section("Reminders") {
                    ForEach(project.reminders) { reminder in
                        reminderRow(reminder)
                    }
                }
            }

            // Notes Section
            if !project.notes.isEmpty {
                Section("Notes") {
                    ForEach(project.notes) { note in
                        noteRow(note)
                    }
                }
            }

            // Meetings Section
            if !project.meetings.isEmpty {
                Section("Meetings") {
                    ForEach(project.meetings) { meeting in
                        meetingRow(meeting)
                    }
                }
            }

            // Empty state for all sections
            if project.reminders.isEmpty && project.notes.isEmpty && project.meetings.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Items Yet", systemImage: "tray")
                    } description: {
                        Text("Items linked to this project will appear here.")
                    }
                }
            }
        }
    }

    private func statBadge(count: Int, label: String, icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text("\(count)")
                    .font(.headline)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 60)
    }

    private func reminderRow(_ reminder: ProjectReminder) -> some View {
        HStack {
            Image(systemName: "circle")
                .foregroundColor(.blue)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(reminder.title)
                        .font(.subheadline)

                    if !reminder.priorityIcon.isEmpty {
                        Image(systemName: reminder.priorityIcon)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if let dueDate = reminder.dueDate {
                    Text(formatDate(dueDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private func noteRow(_ note: ProjectNote) -> some View {
        HStack {
            Image(systemName: "note.text")
                .foregroundColor(.yellow)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.subheadline)

                Text(formatDate(note.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func meetingRow(_ meeting: ProjectMeeting) -> some View {
        HStack {
            Image(systemName: "person.3")
                .foregroundColor(.purple)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                    .font(.subheadline)

                if let date = meeting.date {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var editProjectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $editName)
                }

                Section("Description (Optional)") {
                    TextEditor(text: $editDescription)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let description = editDescription.isEmpty ? nil : editDescription
                            if await viewModel.updateProject(
                                id: projectId,
                                name: editName,
                                description: description
                            ) {
                                showEditSheet = false
                                await viewModel.loadProjectDetail(id: projectId)
                            }
                        }
                    }
                    .disabled(editName.isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: dateString) {
            return formatDate(date)
        }

        // Try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            return formatDate(date)
        }

        return dateString
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProjectDetailView(
            projectId: UUID(),
            viewModel: ProjectsViewModel()
        )
    }
}
