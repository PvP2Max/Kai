import { useQuery } from '@tanstack/react-query'
import { briefingsApi, calendarApi } from '../api/client'
import { format } from 'date-fns'
import { Calendar, CheckCircle, Clock, Sun } from 'lucide-react'

export default function Dashboard() {
  const today = format(new Date(), 'yyyy-MM-dd')

  const { data: briefing, isLoading: isLoadingBriefing } = useQuery({
    queryKey: ['briefing', 'daily', today],
    queryFn: () => briefingsApi.getDaily(today),
  })

  const { data: events } = useQuery({
    queryKey: ['calendar', today, today],
    queryFn: () => calendarApi.getEvents(today, today),
  })

  const upcomingEvents = events?.events?.slice(0, 5) || []

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Good morning!</h1>
        <p className="text-gray-600">{format(new Date(), 'EEEE, MMMM d, yyyy')}</p>
      </div>

      {/* Quick Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="card">
          <div className="flex items-center">
            <div className="p-2 bg-blue-100 rounded-lg">
              <Calendar className="w-6 h-6 text-blue-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-500">Today's Events</p>
              <p className="text-2xl font-semibold">{upcomingEvents.length}</p>
            </div>
          </div>
        </div>

        <div className="card">
          <div className="flex items-center">
            <div className="p-2 bg-green-100 rounded-lg">
              <CheckCircle className="w-6 h-6 text-green-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-500">Tasks Due</p>
              <p className="text-2xl font-semibold">3</p>
            </div>
          </div>
        </div>

        <div className="card">
          <div className="flex items-center">
            <div className="p-2 bg-yellow-100 rounded-lg">
              <Clock className="w-6 h-6 text-yellow-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-500">Focus Time</p>
              <p className="text-2xl font-semibold">2h</p>
            </div>
          </div>
        </div>

        <div className="card">
          <div className="flex items-center">
            <div className="p-2 bg-orange-100 rounded-lg">
              <Sun className="w-6 h-6 text-orange-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-500">Weather</p>
              <p className="text-2xl font-semibold">72°F</p>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Daily Briefing */}
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Daily Briefing</h2>
          {isLoadingBriefing ? (
            <div className="animate-pulse space-y-3">
              <div className="h-4 bg-gray-200 rounded w-3/4" />
              <div className="h-4 bg-gray-200 rounded w-1/2" />
              <div className="h-4 bg-gray-200 rounded w-5/6" />
            </div>
          ) : briefing?.briefing?.summary ? (
            <div className="prose prose-sm text-gray-600">
              <p>{briefing.briefing.summary}</p>
            </div>
          ) : (
            <p className="text-gray-500">No briefing available yet.</p>
          )}
        </div>

        {/* Today's Schedule */}
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Today's Schedule</h2>
          {upcomingEvents.length > 0 ? (
            <div className="space-y-3">
              {upcomingEvents.map((event: { id: string; title: string; start: string; location?: string }) => (
                <div
                  key={event.id}
                  className="flex items-start p-3 bg-gray-50 rounded-lg"
                >
                  <div className="flex-shrink-0 w-16 text-sm text-gray-500">
                    {format(new Date(event.start), 'h:mm a')}
                  </div>
                  <div className="ml-3">
                    <p className="font-medium text-gray-900">{event.title}</p>
                    {event.location && (
                      <p className="text-sm text-gray-500">{event.location}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-gray-500">No events scheduled for today.</p>
          )}
        </div>
      </div>

      {/* Quick Actions */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Quick Actions</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <a
            href="/chat"
            className="p-4 text-center bg-primary-50 rounded-lg hover:bg-primary-100 transition-colors"
          >
            <span className="block text-primary-700 font-medium">Chat with Kai</span>
          </a>
          <a
            href="/calendar"
            className="p-4 text-center bg-blue-50 rounded-lg hover:bg-blue-100 transition-colors"
          >
            <span className="block text-blue-700 font-medium">View Calendar</span>
          </a>
          <a
            href="/notes"
            className="p-4 text-center bg-green-50 rounded-lg hover:bg-green-100 transition-colors"
          >
            <span className="block text-green-700 font-medium">Create Note</span>
          </a>
          <a
            href="/analytics"
            className="p-4 text-center bg-purple-50 rounded-lg hover:bg-purple-100 transition-colors"
          >
            <span className="block text-purple-700 font-medium">View Analytics</span>
          </a>
        </div>
      </div>
    </div>
  )
}
