import { useState, useRef } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { meetingsApi } from '../api/client'
import { format } from 'date-fns'
import { Users, FileText, Clock, CheckCircle, Upload, X, Loader2 } from 'lucide-react'

interface Meeting {
  id: string
  event_title: string | null
  event_start: string | null
  event_end: string | null
  transcript: string | null
  summary: unknown | null
  calendar_event_id: string | null
}

export default function Meetings() {
  const queryClient = useQueryClient()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [showUploadModal, setShowUploadModal] = useState(false)
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [eventTitle, setEventTitle] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['meetings'],
    queryFn: () => meetingsApi.list(),
  })

  const uploadMutation = useMutation({
    mutationFn: async ({ file, title }: { file: File; title: string }) => {
      const formData = new FormData()
      formData.append('audio', file)
      if (title) formData.append('event_title', title)
      return meetingsApi.upload(formData)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['meetings'] })
      setShowUploadModal(false)
      setSelectedFile(null)
      setEventTitle('')
    },
  })

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setSelectedFile(file)
    }
  }

  const handleUpload = () => {
    if (selectedFile) {
      uploadMutation.mutate({ file: selectedFile, title: eventTitle })
    }
  }

  const meetings: Meeting[] = data?.meetings || data || []

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Meetings</h1>
          <p className="text-gray-600">View meeting transcriptions and summaries</p>
        </div>
        <button
          onClick={() => setShowUploadModal(true)}
          className="btn btn-primary flex items-center"
        >
          <Upload className="w-4 h-4 mr-2" />
          Upload Recording
        </button>
      </div>

      {/* Upload Modal */}
      {showUploadModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 w-full max-w-md">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold">Upload Meeting Recording</h2>
              <button onClick={() => setShowUploadModal(false)} className="text-gray-400 hover:text-gray-600">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Meeting Title (optional)
                </label>
                <input
                  type="text"
                  value={eventTitle}
                  onChange={(e) => setEventTitle(e.target.value)}
                  placeholder="e.g., Team Standup"
                  className="input w-full"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Audio File
                </label>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="audio/*,.m4a,.mp3,.wav,.mp4"
                  onChange={handleFileSelect}
                  className="hidden"
                />
                {selectedFile ? (
                  <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span className="text-sm text-gray-700 truncate">{selectedFile.name}</span>
                    <button onClick={() => setSelectedFile(null)} className="text-gray-400 hover:text-gray-600">
                      <X className="w-4 h-4" />
                    </button>
                  </div>
                ) : (
                  <button
                    onClick={() => fileInputRef.current?.click()}
                    className="w-full p-8 border-2 border-dashed border-gray-300 rounded-lg hover:border-primary-400 transition-colors"
                  >
                    <Upload className="w-8 h-8 text-gray-400 mx-auto" />
                    <p className="mt-2 text-sm text-gray-500">Click to select audio file</p>
                    <p className="text-xs text-gray-400">M4A, MP3, WAV supported</p>
                  </button>
                )}
              </div>

              <div className="flex justify-end gap-2 pt-4">
                <button onClick={() => setShowUploadModal(false)} className="btn">
                  Cancel
                </button>
                <button
                  onClick={handleUpload}
                  disabled={!selectedFile || uploadMutation.isPending}
                  className="btn btn-primary flex items-center"
                >
                  {uploadMutation.isPending ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Processing...
                    </>
                  ) : (
                    <>
                      <Upload className="w-4 h-4 mr-2" />
                      Upload & Transcribe
                    </>
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Meetings list */}
      <div className="space-y-4">
        {isLoading ? (
          <div className="animate-pulse space-y-4">
            {[1, 2, 3].map((i) => (
              <div key={i} className="card">
                <div className="h-5 bg-gray-200 rounded w-1/3" />
                <div className="h-4 bg-gray-200 rounded w-1/4 mt-2" />
                <div className="h-4 bg-gray-200 rounded w-1/2 mt-2" />
              </div>
            ))}
          </div>
        ) : meetings.length > 0 ? (
          meetings.map((meeting) => {
            const hasTranscript = !!meeting.transcript
            const hasSummary = !!meeting.summary
            const duration = meeting.event_start && meeting.event_end
              ? Math.round((new Date(meeting.event_end).getTime() - new Date(meeting.event_start).getTime()) / 60000)
              : null

            return (
              <div key={meeting.id} className="card hover:border-primary-300 transition-colors cursor-pointer">
                <div className="flex items-start justify-between">
                  <div className="flex items-start">
                    <div className="p-2 bg-primary-100 rounded-lg">
                      <Users className="w-6 h-6 text-primary-600" />
                    </div>
                    <div className="ml-4">
                      <h3 className="font-semibold text-gray-900">
                        {meeting.event_title || 'Untitled Meeting'}
                      </h3>
                      {meeting.event_start && (
                        <p className="text-sm text-gray-500 mt-1">
                          {format(new Date(meeting.event_start), 'EEEE, MMMM d, yyyy')}
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-4">
                    {duration && (
                      <div className="flex items-center text-sm text-gray-500">
                        <Clock className="w-4 h-4 mr-1" />
                        {duration} min
                      </div>
                    )}
                    <div className="flex items-center gap-2">
                      <span
                        className={`flex items-center text-sm ${
                          hasTranscript ? 'text-green-600' : 'text-gray-400'
                        }`}
                      >
                        <FileText className="w-4 h-4 mr-1" />
                        Transcript
                      </span>
                      <span
                        className={`flex items-center text-sm ${
                          hasSummary ? 'text-green-600' : 'text-gray-400'
                        }`}
                      >
                        <CheckCircle className="w-4 h-4 mr-1" />
                        Summary
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            )
          })
        ) : (
          <div className="card text-center py-12">
            <Users className="w-16 h-16 text-gray-300 mx-auto" />
            <h3 className="mt-4 text-lg font-medium text-gray-900">No meetings yet</h3>
            <p className="mt-2 text-gray-500">
              Meetings will appear here once you have calendar events with transcriptions.
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
