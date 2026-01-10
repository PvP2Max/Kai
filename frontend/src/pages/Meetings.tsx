import { useQuery } from '@tanstack/react-query'
import { meetingsApi } from '../api/client'
import { format } from 'date-fns'
import { Users, FileText, Clock, CheckCircle } from 'lucide-react'

interface Meeting {
  id: string
  title: string
  meeting_date: string
  attendees: string[]
  duration_minutes: number
  has_transcription: boolean
  has_summary: boolean
}

export default function Meetings() {
  const { data, isLoading } = useQuery({
    queryKey: ['meetings'],
    queryFn: () => meetingsApi.list(),
  })

  const meetings: Meeting[] = data?.meetings || []

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Meetings</h1>
        <p className="text-gray-600">View meeting transcriptions and summaries</p>
      </div>

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
          meetings.map((meeting) => (
            <div key={meeting.id} className="card hover:border-primary-300 transition-colors cursor-pointer">
              <div className="flex items-start justify-between">
                <div className="flex items-start">
                  <div className="p-2 bg-primary-100 rounded-lg">
                    <Users className="w-6 h-6 text-primary-600" />
                  </div>
                  <div className="ml-4">
                    <h3 className="font-semibold text-gray-900">{meeting.title}</h3>
                    <p className="text-sm text-gray-500 mt-1">
                      {format(new Date(meeting.meeting_date), 'EEEE, MMMM d, yyyy')}
                    </p>
                    {meeting.attendees?.length > 0 && (
                      <p className="text-sm text-gray-500 mt-1">
                        {meeting.attendees.join(', ')}
                      </p>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  <div className="flex items-center text-sm text-gray-500">
                    <Clock className="w-4 h-4 mr-1" />
                    {meeting.duration_minutes} min
                  </div>
                  <div className="flex items-center gap-2">
                    <span
                      className={`flex items-center text-sm ${
                        meeting.has_transcription ? 'text-green-600' : 'text-gray-400'
                      }`}
                    >
                      <FileText className="w-4 h-4 mr-1" />
                      Transcript
                    </span>
                    <span
                      className={`flex items-center text-sm ${
                        meeting.has_summary ? 'text-green-600' : 'text-gray-400'
                      }`}
                    >
                      <CheckCircle className="w-4 h-4 mr-1" />
                      Summary
                    </span>
                  </div>
                </div>
              </div>
            </div>
          ))
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
