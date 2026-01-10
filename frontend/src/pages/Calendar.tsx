import { useState } from 'react'
import { useCalendar } from '../hooks/useCalendar'
import { format, addWeeks, subWeeks, startOfWeek, addDays } from 'date-fns'
import { ChevronLeft, ChevronRight, Plus } from 'lucide-react'
import clsx from 'clsx'

export default function Calendar() {
  const [currentDate, setCurrentDate] = useState(new Date())
  const { events, isLoading, dateRange } = useCalendar('week', currentDate)

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
          <button className="btn btn-primary flex items-center">
            <Plus className="w-4 h-4 mr-2" />
            Add Event
          </button>
        </div>
      </div>

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
