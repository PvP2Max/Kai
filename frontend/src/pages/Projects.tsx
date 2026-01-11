import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Folder, Plus, ChevronRight, FileText, Users, CheckSquare } from 'lucide-react'
import { format } from 'date-fns'

interface Project {
  id: string
  name: string
  description: string | null
  status: string
  created_at: string
  updated_at: string
  note_count: number
  meeting_count: number
  reminder_count: number
}

interface ProjectDetail extends Project {
  notes: { id: string; title: string; created_at: string }[]
  meetings: { id: string; title: string; date: string | null }[]
  reminders: { id: string; title: string; due_date: string | null; priority: number }[]
}

const API_BASE = import.meta.env.VITE_API_URL || 'https://kai.pvp2max.com'

async function fetchProjects(): Promise<Project[]> {
  const token = localStorage.getItem('kai_access_token')
  const res = await fetch(`${API_BASE}/api/projects`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error('Failed to fetch projects')
  return res.json()
}

async function fetchProjectDetail(id: string): Promise<ProjectDetail> {
  const token = localStorage.getItem('kai_access_token')
  const res = await fetch(`${API_BASE}/api/projects/${id}`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!res.ok) throw new Error('Failed to fetch project')
  return res.json()
}

async function createProject(data: { name: string; description?: string }): Promise<Project> {
  const token = localStorage.getItem('kai_access_token')
  const res = await fetch(`${API_BASE}/api/projects`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error('Failed to create project')
  return res.json()
}

async function updateProject(id: string, data: { name?: string; description?: string; status?: string }): Promise<Project> {
  const token = localStorage.getItem('kai_access_token')
  const res = await fetch(`${API_BASE}/api/projects/${id}`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error('Failed to update project')
  return res.json()
}

export default function Projects() {
  const queryClient = useQueryClient()
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null)
  const [isCreating, setIsCreating] = useState(false)
  const [newProject, setNewProject] = useState({ name: '', description: '' })
  const [statusFilter, setStatusFilter] = useState<string | null>(null)

  const { data: projects, isLoading } = useQuery({
    queryKey: ['projects'],
    queryFn: fetchProjects,
  })

  const { data: selectedProject, isLoading: isLoadingDetail } = useQuery({
    queryKey: ['project', selectedProjectId],
    queryFn: () => fetchProjectDetail(selectedProjectId!),
    enabled: !!selectedProjectId,
  })

  const createMutation = useMutation({
    mutationFn: createProject,
    onSuccess: (project) => {
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      setIsCreating(false)
      setNewProject({ name: '', description: '' })
      setSelectedProjectId(project.id)
    },
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: { status?: string } }) => updateProject(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      queryClient.invalidateQueries({ queryKey: ['project', selectedProjectId] })
    },
  })

  const handleCreate = () => {
    if (!newProject.name.trim()) return
    createMutation.mutate({
      name: newProject.name,
      description: newProject.description || undefined,
    })
  }

  const filteredProjects = projects?.filter((p) => {
    if (!statusFilter) return true
    return p.status === statusFilter
  }) || []

  const activeProjects = filteredProjects.filter((p) => p.status === 'active')
  const completedProjects = filteredProjects.filter((p) => p.status === 'completed')
  const archivedProjects = filteredProjects.filter((p) => p.status === 'archived')

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Projects</h1>
          <p className="text-gray-600">Organize your work by project</p>
        </div>
        <button
          onClick={() => setIsCreating(true)}
          className="btn btn-primary flex items-center"
        >
          <Plus className="w-4 h-4 mr-2" />
          New Project
        </button>
      </div>

      {/* Filter */}
      <div className="flex gap-2">
        <button
          onClick={() => setStatusFilter(null)}
          className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
            !statusFilter ? 'bg-primary-100 text-primary-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
          }`}
        >
          All
        </button>
        <button
          onClick={() => setStatusFilter('active')}
          className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
            statusFilter === 'active' ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
          }`}
        >
          Active
        </button>
        <button
          onClick={() => setStatusFilter('completed')}
          className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
            statusFilter === 'completed' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
          }`}
        >
          Completed
        </button>
        <button
          onClick={() => setStatusFilter('archived')}
          className={`px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
            statusFilter === 'archived' ? 'bg-gray-200 text-gray-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
          }`}
        >
          Archived
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Projects list */}
        <div className="lg:col-span-1 space-y-4">
          {isLoading ? (
            <div className="animate-pulse space-y-3">
              {[1, 2, 3].map((i) => (
                <div key={i} className="card">
                  <div className="h-4 bg-gray-200 rounded w-3/4" />
                  <div className="h-3 bg-gray-200 rounded w-1/2 mt-2" />
                </div>
              ))}
            </div>
          ) : filteredProjects.length > 0 ? (
            <>
              {!statusFilter && activeProjects.length > 0 && (
                <div className="space-y-2">
                  <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider">Active</h3>
                  {activeProjects.map((project) => (
                    <ProjectCard
                      key={project.id}
                      project={project}
                      isSelected={selectedProjectId === project.id}
                      onClick={() => setSelectedProjectId(project.id)}
                    />
                  ))}
                </div>
              )}
              {!statusFilter && completedProjects.length > 0 && (
                <div className="space-y-2">
                  <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider">Completed</h3>
                  {completedProjects.map((project) => (
                    <ProjectCard
                      key={project.id}
                      project={project}
                      isSelected={selectedProjectId === project.id}
                      onClick={() => setSelectedProjectId(project.id)}
                    />
                  ))}
                </div>
              )}
              {!statusFilter && archivedProjects.length > 0 && (
                <div className="space-y-2">
                  <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider">Archived</h3>
                  {archivedProjects.map((project) => (
                    <ProjectCard
                      key={project.id}
                      project={project}
                      isSelected={selectedProjectId === project.id}
                      onClick={() => setSelectedProjectId(project.id)}
                    />
                  ))}
                </div>
              )}
              {statusFilter && filteredProjects.map((project) => (
                <ProjectCard
                  key={project.id}
                  project={project}
                  isSelected={selectedProjectId === project.id}
                  onClick={() => setSelectedProjectId(project.id)}
                />
              ))}
            </>
          ) : (
            <div className="card text-center py-8">
              <Folder className="w-12 h-12 text-gray-300 mx-auto mb-3" />
              <p className="text-gray-500">No projects yet</p>
              <button
                onClick={() => setIsCreating(true)}
                className="text-primary-600 hover:text-primary-700 text-sm mt-2"
              >
                Create your first project
              </button>
            </div>
          )}
        </div>

        {/* Project detail */}
        <div className="lg:col-span-2">
          {selectedProjectId ? (
            isLoadingDetail ? (
              <div className="card animate-pulse">
                <div className="h-6 bg-gray-200 rounded w-1/3 mb-4" />
                <div className="h-4 bg-gray-200 rounded w-2/3" />
              </div>
            ) : selectedProject ? (
              <div className="card space-y-6">
                {/* Project header */}
                <div className="flex items-start justify-between">
                  <div>
                    <h2 className="text-xl font-bold text-gray-900">{selectedProject.name}</h2>
                    {selectedProject.description && (
                      <p className="text-gray-600 mt-1">{selectedProject.description}</p>
                    )}
                  </div>
                  <div className="flex gap-2">
                    {selectedProject.status === 'active' ? (
                      <>
                        <button
                          onClick={() => updateMutation.mutate({ id: selectedProject.id, data: { status: 'completed' } })}
                          className="text-sm px-3 py-1.5 bg-blue-50 text-blue-600 rounded-lg hover:bg-blue-100"
                        >
                          Complete
                        </button>
                        <button
                          onClick={() => updateMutation.mutate({ id: selectedProject.id, data: { status: 'archived' } })}
                          className="text-sm px-3 py-1.5 bg-gray-50 text-gray-600 rounded-lg hover:bg-gray-100"
                        >
                          Archive
                        </button>
                      </>
                    ) : (
                      <button
                        onClick={() => updateMutation.mutate({ id: selectedProject.id, data: { status: 'active' } })}
                        className="text-sm px-3 py-1.5 bg-green-50 text-green-600 rounded-lg hover:bg-green-100"
                      >
                        Reactivate
                      </button>
                    )}
                  </div>
                </div>

                {/* Stats */}
                <div className="grid grid-cols-3 gap-4">
                  <div className="bg-gray-50 rounded-lg p-4 text-center">
                    <CheckSquare className="w-6 h-6 text-blue-500 mx-auto mb-1" />
                    <div className="text-2xl font-bold text-gray-900">{selectedProject.reminder_count}</div>
                    <div className="text-xs text-gray-500">Reminders</div>
                  </div>
                  <div className="bg-gray-50 rounded-lg p-4 text-center">
                    <FileText className="w-6 h-6 text-yellow-500 mx-auto mb-1" />
                    <div className="text-2xl font-bold text-gray-900">{selectedProject.note_count}</div>
                    <div className="text-xs text-gray-500">Notes</div>
                  </div>
                  <div className="bg-gray-50 rounded-lg p-4 text-center">
                    <Users className="w-6 h-6 text-purple-500 mx-auto mb-1" />
                    <div className="text-2xl font-bold text-gray-900">{selectedProject.meeting_count}</div>
                    <div className="text-xs text-gray-500">Meetings</div>
                  </div>
                </div>

                {/* Reminders */}
                {selectedProject.reminders.length > 0 && (
                  <div>
                    <h3 className="text-sm font-semibold text-gray-700 mb-3">Reminders</h3>
                    <div className="space-y-2">
                      {selectedProject.reminders.map((reminder) => (
                        <div key={reminder.id} className="flex items-center p-3 bg-gray-50 rounded-lg">
                          <div className="w-4 h-4 border-2 border-blue-400 rounded mr-3" />
                          <div className="flex-1">
                            <div className="text-sm font-medium text-gray-900">{reminder.title}</div>
                            {reminder.due_date && (
                              <div className="text-xs text-gray-500">
                                Due: {format(new Date(reminder.due_date), 'MMM d, yyyy')}
                              </div>
                            )}
                          </div>
                          {reminder.priority > 0 && (
                            <span className="text-orange-500 text-xs font-medium">
                              {reminder.priority >= 9 ? 'High' : reminder.priority >= 5 ? 'Medium' : 'Low'}
                            </span>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Notes */}
                {selectedProject.notes.length > 0 && (
                  <div>
                    <h3 className="text-sm font-semibold text-gray-700 mb-3">Notes</h3>
                    <div className="space-y-2">
                      {selectedProject.notes.map((note) => (
                        <div key={note.id} className="flex items-center p-3 bg-gray-50 rounded-lg">
                          <FileText className="w-4 h-4 text-yellow-500 mr-3" />
                          <div className="flex-1">
                            <div className="text-sm font-medium text-gray-900">{note.title || 'Untitled'}</div>
                            <div className="text-xs text-gray-500">
                              {format(new Date(note.created_at), 'MMM d, yyyy')}
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Meetings */}
                {selectedProject.meetings.length > 0 && (
                  <div>
                    <h3 className="text-sm font-semibold text-gray-700 mb-3">Meetings</h3>
                    <div className="space-y-2">
                      {selectedProject.meetings.map((meeting) => (
                        <div key={meeting.id} className="flex items-center p-3 bg-gray-50 rounded-lg">
                          <Users className="w-4 h-4 text-purple-500 mr-3" />
                          <div className="flex-1">
                            <div className="text-sm font-medium text-gray-900">{meeting.title || 'Untitled'}</div>
                            {meeting.date && (
                              <div className="text-xs text-gray-500">
                                {format(new Date(meeting.date), 'MMM d, yyyy')}
                              </div>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Empty state */}
                {selectedProject.reminders.length === 0 &&
                  selectedProject.notes.length === 0 &&
                  selectedProject.meetings.length === 0 && (
                    <div className="text-center py-8 text-gray-500">
                      <p>No items linked to this project yet.</p>
                      <p className="text-sm mt-1">Items will appear here when synced from your devices.</p>
                    </div>
                  )}
              </div>
            ) : null
          ) : (
            <div className="card text-center py-12">
              <Folder className="w-16 h-16 text-gray-200 mx-auto mb-4" />
              <h3 className="text-lg font-medium text-gray-700 mb-2">Select a project</h3>
              <p className="text-gray-500">Choose a project from the list to view its details</p>
            </div>
          )}
        </div>
      </div>

      {/* Create project modal */}
      {isCreating && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl p-6 w-full max-w-md shadow-xl">
            <h2 className="text-lg font-bold text-gray-900 mb-4">New Project</h2>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Name</label>
                <input
                  type="text"
                  value={newProject.name}
                  onChange={(e) => setNewProject({ ...newProject, name: e.target.value })}
                  className="input"
                  placeholder="Project name"
                  autoFocus
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Description (optional)</label>
                <textarea
                  value={newProject.description}
                  onChange={(e) => setNewProject({ ...newProject, description: e.target.value })}
                  className="input min-h-[100px]"
                  placeholder="Brief description of the project"
                />
              </div>
            </div>
            <div className="flex justify-end gap-3 mt-6">
              <button
                onClick={() => {
                  setIsCreating(false)
                  setNewProject({ name: '', description: '' })
                }}
                className="btn"
              >
                Cancel
              </button>
              <button
                onClick={handleCreate}
                disabled={!newProject.name.trim() || createMutation.isPending}
                className="btn btn-primary"
              >
                {createMutation.isPending ? 'Creating...' : 'Create'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function ProjectCard({
  project,
  isSelected,
  onClick,
}: {
  project: Project
  isSelected: boolean
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className={`card w-full text-left hover:border-primary-300 transition-colors ${
        isSelected ? 'border-primary-500 ring-1 ring-primary-500' : ''
      }`}
    >
      <div className="flex items-center">
        <Folder className={`w-5 h-5 mr-3 ${
          project.status === 'active' ? 'text-green-500' :
          project.status === 'completed' ? 'text-blue-500' : 'text-gray-400'
        }`} />
        <div className="flex-1 min-w-0">
          <div className="font-medium text-gray-900 truncate">{project.name}</div>
          <div className="flex items-center gap-3 text-xs text-gray-500 mt-1">
            {project.reminder_count > 0 && (
              <span className="flex items-center">
                <CheckSquare className="w-3 h-3 mr-1" />
                {project.reminder_count}
              </span>
            )}
            {project.note_count > 0 && (
              <span className="flex items-center">
                <FileText className="w-3 h-3 mr-1" />
                {project.note_count}
              </span>
            )}
            {project.meeting_count > 0 && (
              <span className="flex items-center">
                <Users className="w-3 h-3 mr-1" />
                {project.meeting_count}
              </span>
            )}
          </div>
        </div>
        <ChevronRight className="w-4 h-4 text-gray-400" />
      </div>
    </button>
  )
}
