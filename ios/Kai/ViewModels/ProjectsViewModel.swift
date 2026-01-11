//
//  ProjectsViewModel.swift
//  Kai
//
//  View model for managing projects.
//

import Foundation

// MARK: - Projects View Model

@MainActor
final class ProjectsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var projects: [Project] = []
    @Published private(set) var selectedProject: ProjectDetail?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingDetail: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var showCreateSheet: Bool = false

    // MARK: - Private Properties

    private let apiClient = APIClient.shared

    // MARK: - Computed Properties

    var activeProjects: [Project] {
        projects.filter { $0.status == "active" }
    }

    var completedProjects: [Project] {
        projects.filter { $0.status == "completed" }
    }

    var archivedProjects: [Project] {
        projects.filter { $0.status == "archived" }
    }

    var totalReminderCount: Int {
        projects.reduce(0) { $0 + $1.reminderCount }
    }

    // MARK: - Public Methods

    /// Loads all projects
    func loadProjects() async {
        isLoading = true
        errorMessage = nil

        do {
            projects = try await apiClient.request(.projects, method: .get)
        } catch let error as APIError {
            if case .notFound = error {
                projects = []
            } else {
                handleError(error)
            }
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    /// Loads a specific project with all its items
    func loadProjectDetail(id: UUID) async {
        isLoadingDetail = true
        errorMessage = nil

        do {
            selectedProject = try await apiClient.request(
                .project(id: id.uuidString),
                method: .get
            )
        } catch {
            handleError(error)
        }

        isLoadingDetail = false
    }

    /// Creates a new project
    func createProject(name: String, description: String? = nil) async -> Project? {
        errorMessage = nil

        let request = ProjectCreateRequest(name: name, description: description)

        do {
            let newProject: Project = try await apiClient.request(
                .projects,
                method: .post,
                body: request
            )
            projects.insert(newProject, at: 0)
            return newProject
        } catch {
            handleError(error)
            return nil
        }
    }

    /// Updates a project
    func updateProject(id: UUID, name: String? = nil, description: String? = nil, status: String? = nil) async -> Bool {
        errorMessage = nil

        let request = ProjectUpdateRequest(name: name, description: description, status: status)

        do {
            let updatedProject: Project = try await apiClient.request(
                .project(id: id.uuidString),
                method: .put,
                body: request
            )

            if let index = projects.firstIndex(where: { $0.id == id }) {
                projects[index] = updatedProject
            }

            return true
        } catch {
            handleError(error)
            return false
        }
    }

    /// Archives a project
    func archiveProject(id: UUID) async -> Bool {
        return await updateProject(id: id, status: "archived")
    }

    /// Marks a project as completed
    func completeProject(id: UUID) async -> Bool {
        return await updateProject(id: id, status: "completed")
    }

    /// Reactivates an archived or completed project
    func reactivateProject(id: UUID) async -> Bool {
        return await updateProject(id: id, status: "active")
    }

    /// Clears the selected project
    func clearSelectedProject() {
        selectedProject = nil
    }

    /// Refreshes both projects list and selected project detail
    func refresh() async {
        await loadProjects()
        if let selectedId = selectedProject?.id {
            await loadProjectDetail(id: selectedId)
        }
    }

    // MARK: - Private Methods

    private func handleError(_ error: Error) {
        if let apiError = error as? APIError {
            errorMessage = apiError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
        showError = true
    }
}
