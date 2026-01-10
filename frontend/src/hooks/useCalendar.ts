import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { calendarApi } from '../api/client'
import { format, startOfWeek, endOfWeek, startOfMonth, endOfMonth } from 'date-fns'

interface CalendarEvent {
  id: string
  title: string
  start: string
  end: string
  location?: string
  description?: string
  attendees?: string[]
  all_day?: boolean
}

export function useCalendar(view: 'week' | 'month' = 'week', currentDate: Date = new Date()) {
  const queryClient = useQueryClient()

  const dateRange = view === 'week'
    ? {
        start: format(startOfWeek(currentDate), 'yyyy-MM-dd'),
        end: format(endOfWeek(currentDate), 'yyyy-MM-dd'),
      }
    : {
        start: format(startOfMonth(currentDate), 'yyyy-MM-dd'),
        end: format(endOfMonth(currentDate), 'yyyy-MM-dd'),
      }

  const { data, isLoading, error } = useQuery<{ events: CalendarEvent[] }>({
    queryKey: ['calendar', dateRange.start, dateRange.end],
    queryFn: () => calendarApi.getEvents(dateRange.start, dateRange.end),
  })

  const createMutation = useMutation({
    mutationFn: calendarApi.createEvent,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['calendar'] })
    },
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, updates }: { id: string; updates: Record<string, unknown> }) =>
      calendarApi.updateEvent(id, updates),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['calendar'] })
    },
  })

  const deleteMutation = useMutation({
    mutationFn: calendarApi.deleteEvent,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['calendar'] })
    },
  })

  return {
    events: data?.events || [],
    isLoading,
    error,
    dateRange,
    createEvent: createMutation.mutate,
    updateEvent: updateMutation.mutate,
    deleteEvent: deleteMutation.mutate,
    isCreating: createMutation.isPending,
    isUpdating: updateMutation.isPending,
    isDeleting: deleteMutation.isPending,
  }
}
