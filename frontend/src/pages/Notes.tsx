import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { notesApi } from '../api/client'
import { Plus, Search, FileText, Tag } from 'lucide-react'
import { format } from 'date-fns'

interface Note {
  id: string
  title: string
  content: string
  tags: string[]
  created_at: string
}

export default function Notes() {
  const queryClient = useQueryClient()
  const [searchQuery, setSearchQuery] = useState('')
  const [isCreating, setIsCreating] = useState(false)
  const [newNote, setNewNote] = useState({ title: '', content: '', tags: '' })
  const [selectedNote, setSelectedNote] = useState<Note | null>(null)

  const { data: searchResults, isLoading } = useQuery({
    queryKey: ['notes', 'search', searchQuery],
    queryFn: () => notesApi.search(searchQuery || '*'),
    enabled: true,
  })

  const createMutation = useMutation({
    mutationFn: notesApi.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notes'] })
      setIsCreating(false)
      setNewNote({ title: '', content: '', tags: '' })
    },
  })

  const handleCreate = () => {
    if (!newNote.content.trim()) return

    createMutation.mutate({
      title: newNote.title || undefined,
      content: newNote.content,
      tags: newNote.tags.split(',').map((t) => t.trim()).filter(Boolean),
    })
  }

  const notes = searchResults?.notes || []

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Notes</h1>
          <p className="text-gray-600">Your personal notes and ideas</p>
        </div>
        <button
          onClick={() => setIsCreating(true)}
          className="btn btn-primary flex items-center"
        >
          <Plus className="w-4 h-4 mr-2" />
          New Note
        </button>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400" />
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Search notes..."
          className="input pl-10"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Notes list */}
        <div className="lg:col-span-1 space-y-3">
          {isLoading ? (
            <div className="animate-pulse space-y-3">
              {[1, 2, 3].map((i) => (
                <div key={i} className="card">
                  <div className="h-4 bg-gray-200 rounded w-3/4" />
                  <div className="h-3 bg-gray-200 rounded w-1/2 mt-2" />
                </div>
              ))}
            </div>
          ) : notes.length > 0 ? (
            notes.map((note: Note) => (
              <button
                key={note.id}
                onClick={() => setSelectedNote(note)}
                className={`card w-full text-left hover:border-primary-300 transition-colors ${
                  selectedNote?.id === note.id ? 'border-primary-500' : ''
                }`}
              >
                <div className="flex items-start">
                  <FileText className="w-5 h-5 text-gray-400 mt-0.5" />
                  <div className="ml-3 flex-1 min-w-0">
                    <p className="font-medium text-gray-900 truncate">
                      {note.title || 'Untitled'}
                    </p>
                    <p className="text-sm text-gray-500 truncate mt-1">
                      {note.content.substring(0, 100)}
                    </p>
                    <div className="flex items-center gap-2 mt-2">
                      <span className="text-xs text-gray-400">
                        {format(new Date(note.created_at), 'MMM d, yyyy')}
                      </span>
                      {note.tags?.length > 0 && (
                        <div className="flex items-center gap-1">
                          <Tag className="w-3 h-3 text-gray-400" />
                          <span className="text-xs text-gray-400">
                            {note.tags.length}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </button>
            ))
          ) : (
            <div className="card text-center py-8">
              <FileText className="w-12 h-12 text-gray-300 mx-auto" />
              <p className="mt-2 text-gray-500">No notes found</p>
            </div>
          )}
        </div>

        {/* Note viewer/editor */}
        <div className="lg:col-span-2">
          {isCreating ? (
            <div className="card">
              <h2 className="text-lg font-semibold mb-4">New Note</h2>
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Title
                  </label>
                  <input
                    type="text"
                    value={newNote.title}
                    onChange={(e) =>
                      setNewNote({ ...newNote, title: e.target.value })
                    }
                    placeholder="Note title (optional)"
                    className="input"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Content
                  </label>
                  <textarea
                    value={newNote.content}
                    onChange={(e) =>
                      setNewNote({ ...newNote, content: e.target.value })
                    }
                    placeholder="Write your note..."
                    rows={10}
                    className="input resize-none"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Tags
                  </label>
                  <input
                    type="text"
                    value={newNote.tags}
                    onChange={(e) =>
                      setNewNote({ ...newNote, tags: e.target.value })
                    }
                    placeholder="Comma-separated tags"
                    className="input"
                  />
                </div>
                <div className="flex justify-end gap-2">
                  <button
                    onClick={() => setIsCreating(false)}
                    className="btn btn-secondary"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleCreate}
                    disabled={createMutation.isPending}
                    className="btn btn-primary"
                  >
                    {createMutation.isPending ? 'Saving...' : 'Save Note'}
                  </button>
                </div>
              </div>
            </div>
          ) : selectedNote ? (
            <div className="card">
              <div className="flex items-start justify-between mb-4">
                <div>
                  <h2 className="text-xl font-semibold text-gray-900">
                    {selectedNote.title || 'Untitled'}
                  </h2>
                  <p className="text-sm text-gray-500">
                    {format(new Date(selectedNote.created_at), 'MMMM d, yyyy h:mm a')}
                  </p>
                </div>
              </div>
              {selectedNote.tags?.length > 0 && (
                <div className="flex flex-wrap gap-2 mb-4">
                  {selectedNote.tags.map((tag) => (
                    <span
                      key={tag}
                      className="px-2 py-1 text-xs bg-gray-100 text-gray-700 rounded"
                    >
                      {tag}
                    </span>
                  ))}
                </div>
              )}
              <div className="prose prose-sm max-w-none">
                <p className="whitespace-pre-wrap">{selectedNote.content}</p>
              </div>
            </div>
          ) : (
            <div className="card text-center py-16">
              <FileText className="w-16 h-16 text-gray-300 mx-auto" />
              <p className="mt-4 text-gray-500">Select a note to view</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
