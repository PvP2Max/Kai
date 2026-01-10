import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useCalendar } from '../hooks/useCalendar'
import { calendarApi } from '../api/client'
import { format, addWeeks, subWeeks, startOfWeek, addDays } from 'date-fns'
import { ChevronLeft, ChevronRight, Plus, X, Loader2 } from 'lucide-react'
import clsx from 'clsx'

export default function Calendar() {
  const queryClient = useQueryClient()
  const [currentDate, setCurrentDate] = useState(new Date())
  const [showAddModal, setShowAddModal] = useState(false)
  const [newEvent, setNewEvent] = useState({
    title: '',
    date: format(new Date(), 'yyyy-MM-dd'),
    startTime: '09:00',
    endTime: '10:00',
    location: '',
    description: '',
  })

  const { events, isLoading, dateRange } = useCalendar('week', currentDate)

  const createMutation = useMutation({
    mutationFn: (event: { title: string; start: string; end: string; location?: string; description?: string }) =>
      calendarApi.createEvent(event),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['calendar'] })
      setShowAddModal(false)
      setNewEvent({
        title: '',
        date: format(new Date(), 'yyyy-MM-dd'),
        startTime: '09:00',
        endTime: '10:00',
        location: '',
        description: '',
      })
    },
  })

  const handleCreateEvent = () => {
    const start = `${newEvent.date}T${newEvent.startTime}:00`
    const end = `${newEvent.date}T${newEvent.endTime}:00`
    createMutation.mutate({
      title: newEvent.title,
      start,
      end,
      location: newEvent.location || undefined,
      description: newEvent.description || undefined,
    })
  }

  const weekStart = startOfWeek(currentDate)
  const weekDays = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i))
  const hours = Array.from({ length: 12 }, (_, i) => i + 8) // 8 AM to 7 PM

  const goToPreviousWeek = () => setCurrentDate(subWeeks(currentDate, 1))
  const goToNextWeek = () => setCurrentDate(addWeeks(currentDate, 1))
  const goToToday = () => setCurrentDate(new Date())

  const getEventsForDay = (day: Date) => {
    const dayStr = format(day, 'yyyy-MM-dd')
    return events.filter((event) => event.start?.startsWith(dayStr))
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Calendar</h1>
          <p className="text-gray-600">
            {format(weekStart, 'MMMM d')} - {format(addDays(weekStart, 6), 'MMMM d, yyyy')}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={goToToday} className="btn btn-secondary">
            Today
          </button>
          <div className="flex items-center">
            <button
              onClick={goToPreviousWeek}
              className="p-2 hover:bg-gray-100 rounded-lg"
            >
              <ChevronLeft className="w-5 h-5" />
            </button>
            <button
              onClick={goToNextWeek}
              className="p-2 hover:bg-gray-100 rounded-lg"
            >
              <ChevronRight className="w-5 h-5" />
            </button>
          </div>
          <button onClick={() => setShowAddModal(true)} className="btn btn-primary flex items-center">
            <Plus className="w-4 h-4 mr-2" />
            Add Event
          </button>
        </div>
      </div>

      {/* Add Event Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 w-full max-w-md">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold">Add Event</h2>
              <button onClick={() => setShowAddModal(false)} className="text-gray-400 hover:text-gray-600">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Title</label>
                <input
                  type="text"
                  value={newEvent.title}
                  onChange={(e) => setNewEvent({ ...newEvent, title: e.target.value })}
                  placeholder="Event title"
                  className="input w-full"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Date</label>
                <input
                  type="date"
                  value={newEvent.date}
                  onChange={(e) => setNewEvent({ ...newEvent, date: e.target.value })}
                  className="input w-full"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">Start Time</label>
                  <input
                    type="time"
                    value={newEvent.startTime}
                    onChange={(e) => setNewEvent({ ...newEvent, startTime: e.target.value })}
                    className="input w-full"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">End Time</label>
                  <input
                    type="time"
                    value={newEvent.endTime}
                    onChange={(e) => setNewEvent({ ...newEvent, endTime: e.target.value })}
                    className="input w-full"
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Location (optional)</label>
                <input
                  type="text"
                  value={newEvent.location}
                  onChange={(e) => setNewEvent({ ...newEvent, location: e.target.value })}
                  placeholder="Location"
                  className="input w-full"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Description (optional)</label>
                <textarea
                  value={newEvent.description}
                  onChange={(e) => setNewEvent({ ...newEvent, description: e.target.value })}
                  placeholder="Description"
                  rows={3}
                  className="input w-full"
                />
              </div>

              <div className="flex justify-end gap-2 pt-4">
                <button onClick={() => setShowAddModal(false)} className="btn">
                  Cancel
                </button>
                <button
                  onClick={handleCreateEvent}
                  disabled={!newEvent.title || createMutation.isPending}
                  className="btn btn-primary flex items-center"
                >
                  {createMutation.isPending ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Creating...
                    </>
                  ) : (
                    'Create Event'
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Calendar Grid */}
      <div className="card p-0 overflow-hidden">
        {isLoading ? (
          <div className="h-96 flex items-center justify-center">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600" />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <div className="min-w-[800px]">
              {/* Day headers */}
              <div className="grid grid-cols-8 border-b">
                <div className="p-3 text-sm text-gray-500" />
                {weekDays.map((day) => (
                  <div
                    key={day.toISOString()}
                    className={clsx(
                      'p-3 text-center border-l',
                      format(day, 'yyyy-MM-dd') === format(new Date(), 'yyyy-MM-dd')
                        ? 'bg-primary-50'
                        : ''
                    )}
                  >
                    <p className="text-sm text-gray-500">{format(day, 'EEE')}</p>
                    <p
                      className={clsx(
                        'text-lg font-semibold',
                        format(day, 'yyyy-MM-dd') === format(new Date(), 'yyyy-MM-dd')
                          ? 'text-primary-600'
                          : 'text-gray-900'
                      )}
                    >
                      {format(day, 'd')}
                    </p>
                  </div>
                ))}
              </div>

              {/* Time grid */}
              <div className="grid grid-cols-8">
                {/* Time labels */}
                <div className="border-r">
                  {hours.map((hour) => (
                    <div
                      key={hour}
                      className="h-16 px-2 py-1 text-xs text-gray-500 text-right"
                    >
                      {format(new Date().setHours(hour, 0), 'h a')}
                    </div>
                  ))}
                </div>

                {/* Day columns */}
                {weekDays.map((day) => {
                  const dayEvents = getEventsForDay(day)

                  return (
                    <div key={day.toISOString()} className="border-l relative">
                      {hours.map((hour) => (
                        <div key={hour} className="h-16 border-b border-gray-100" />
                      ))}

                      {/* Events */}
                      {dayEvents.map((event) => {
                        const startTime = new Date(event.start)
                        const endTime = new Date(event.end)
                        const startHour = startTime.getHours()
                        const startMinutes = startTime.getMinutes()
                        const duration =
                          (endTime.getTime() - startTime.getTime()) / (1000 * 60)

                        const top = ((startHour - 8) * 64) + ((startMinutes / 60) * 64)
                        const height = (duration / 60) * 64

                        if (startHour < 8 || startHour >= 20) return null

                        return (
                          <div
                            key={event.id}
                            className="absolute left-0 right-0 mx-1 bg-primary-100 border-l-2 border-primary-600 rounded-r px-2 py-1 overflow-hidden cursor-pointer hover:bg-primary-200"
                            style={{
                              top: `${top}px`,
                              height: `${Math.max(height, 24)}px`,
                            }}
                          >
                            <p className="text-xs font-medium text-primary-900 truncate">
                              {event.title}
                            </p>
                            <p className="text-xs text-primary-700">
                              {format(startTime, 'h:mm a')}
                            </p>
                          </div>
                        )
                      })}
                    </div>
                  )
                })}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
