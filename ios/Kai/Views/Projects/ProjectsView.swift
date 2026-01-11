//
//  ProjectsView.swift
//  Kai
//
//  Main view for listing and managing projects.
//

import SwiftUI

struct ProjectsView: View {
    @StateObject private var viewModel = ProjectsViewModel()
    @State private var showCreateSheet = false
    @State private var newProjectName = ""
    @State private var newProjectDescription = ""
    @State private var selectedProjectId: UUID?
    @State private var showStatusFilter = false
    @State private var statusFilter: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.projects.isEmpty {
                    ProgressView("Loading projects...")
                } else if viewModel.projects.isEmpty {
                    emptyStateView
                } else {
                    projectsList
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All") { statusFilter = nil }
                        Button("Active") { statusFilter = "active" }
                        Button("Completed") { statusFilter = "completed" }
                        Button("Archived") { statusFilter = "archived" }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                await viewModel.loadProjects()
            }
            .sheet(isPresented: $showCreateSheet) {
                createProjectSheet
            }
            .navigationDestination(item: $selectedProjectId) { projectId in
                ProjectDetailView(projectId: projectId, viewModel: viewModel)
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
        .task {
            await viewModel.loadProjects()
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Projects", systemImage: "folder")
        } description: {
            Text("Create a project to organize your notes, meetings, and reminders.")
        } actions: {
            Button("Create Project") {
                showCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var projectsList: some View {
        List {
            if let filter = statusFilter {
                Section {
                    ForEach(filteredProjects(status: filter)) { project in
                        projectRow(project)
                    }
                }
            } else {
                if !viewModel.activeProjects.isEmpty {
                    Section("Active") {
                        ForEach(viewModel.activeProjects) { project in
                            projectRow(project)
                        }
                    }
                }

                if !viewModel.completedProjects.isEmpty {
                    Section("Completed") {
                        ForEach(viewModel.completedProjects) { project in
                            projectRow(project)
                        }
                    }
                }

                if !viewModel.archivedProjects.isEmpty {
                    Section("Archived") {
                        ForEach(viewModel.archivedProjects) { project in
                            projectRow(project)
                        }
                    }
                }
            }
        }
    }

    private func filteredProjects(status: String) -> [Project] {
        viewModel.projects.filter { $0.status == status }
    }

    private func projectRow(_ project: Project) -> some View {
        Button {
            selectedProjectId = project.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if project.status != "active" {
                            Image(systemName: project.statusIcon)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        if project.reminderCount > 0 {
                            Label("\(project.reminderCount)", systemImage: "checklist")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if project.noteCount > 0 {
                            Label("\(project.noteCount)", systemImage: "note.text")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if project.meetingCount > 0 {
                            Label("\(project.meetingCount)", systemImage: "person.3")
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if project.status == "active" {
                Button {
                    Task { await viewModel.completeProject(id: project.id) }
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.blue)

                Button {
                    Task { await viewModel.archiveProject(id: project.id) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.gray)
            } else {
                Button {
                    Task { await viewModel.reactivateProject(id: project.id) }
                } label: {
                    Label("Reactivate", systemImage: "arrow.uturn.left")
                }
                .tint(.green)
            }
        }
    }

    private var createProjectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $newProjectName)
                }

                Section("Description (Optional)") {
                    TextEditor(text: $newProjectDescription)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetCreateForm()
                        showCreateSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            let description = newProjectDescription.isEmpty ? nil : newProjectDescription
                            if let project = await viewModel.createProject(
                                name: newProjectName,
                                description: description
                            ) {
                                resetCreateForm()
                                showCreateSheet = false
                                selectedProjectId = project.id
                            }
                        }
                    }
                    .disabled(newProjectName.isEmpty)
                }
            }
        }
    }

    private func resetCreateForm() {
        newProjectName = ""
        newProjectDescription = ""
    }
}

// MARK: - Preview

#Preview {
    ProjectsView()
}
