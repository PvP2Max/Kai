import axios from 'axios'

const API_BASE_URL = '/api'

const client = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Add auth token to requests
client.interceptors.request.use((config) => {
  const token = localStorage.getItem('access_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// Handle token refresh
client.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config

    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true

      try {
        const refreshToken = localStorage.getItem('refresh_token')
        if (refreshToken) {
          const response = await axios.post(`${API_BASE_URL}/auth/refresh`, {
            refresh_token: refreshToken,
          })

          const { access_token, refresh_token } = response.data
          localStorage.setItem('access_token', access_token)
          localStorage.setItem('refresh_token', refresh_token)

          originalRequest.headers.Authorization = `Bearer ${access_token}`
          return client(originalRequest)
        }
      } catch {
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')
        window.location.href = '/login'
      }
    }

    return Promise.reject(error)
  }
)

// Auth API
export const authApi = {
  login: async (email: string, password: string) => {
    const response = await client.post('/auth/login', { email, password })
    return response.data
  },
  register: async (email: string, password: string, name: string) => {
    const response = await client.post('/auth/register', { email, password, name })
    return response.data
  },
  me: async () => {
    const response = await client.get('/auth/me')
    return response.data
  },
  updateMe: async (updates: { name?: string; timezone?: string }) => {
    const response = await client.put('/auth/me', updates)
    return response.data
  },
  logout: () => {
    localStorage.removeItem('access_token')
    localStorage.removeItem('refresh_token')
  },
  syncTimezone: async () => {
    const browserTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    try {
      const user = await authApi.me()
      if (user.timezone !== browserTimezone) {
        await authApi.updateMe({ timezone: browserTimezone })
      }
    } catch {
      // Ignore errors - timezone sync is not critical
    }
  },
}

// Location helper for weather and location-based features
let cachedLocation: { latitude: number; longitude: number } | null = null
let locationPromise: Promise<{ latitude: number; longitude: number } | null> | null = null

const getLocation = async (): Promise<{ latitude: number; longitude: number } | null> => {
  // Return cached location if available and recent (within 5 minutes)
  if (cachedLocation) {
    return cachedLocation
  }

  // If already fetching, wait for that promise
  if (locationPromise) {
    return locationPromise
  }

  // Start fetching location
  locationPromise = new Promise((resolve) => {
    if (!navigator.geolocation) {
      resolve(null)
      return
    }

    navigator.geolocation.getCurrentPosition(
      (position) => {
        cachedLocation = {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
        }
        resolve(cachedLocation)
        locationPromise = null
      },
      () => {
        resolve(null)
        locationPromise = null
      },
      { timeout: 5000, maximumAge: 300000 } // 5s timeout, 5min cache
    )
  })

  return locationPromise
}

// Chat API
export const chatApi = {
  send: async (message: string, conversationId?: string) => {
    // Get location for weather and other location-based features
    const location = await getLocation()

    const response = await client.post('/chat', {
      message,
      conversation_id: conversationId,
      source: 'web',
      latitude: location?.latitude,
      longitude: location?.longitude,
    })
    return response.data
  },
  getConversations: async () => {
    const response = await client.get('/conversations')
    return response.data
  },
  getConversation: async (id: string) => {
    const response = await client.get(`/conversations/${id}`)
    return response.data
  },
}

// Calendar API
export const calendarApi = {
  getEvents: async (startDate: string, endDate: string) => {
    const response = await client.get('/calendar/events', {
      params: { start_date: startDate, end_date: endDate },
    })
    return response.data
  },
  createEvent: async (event: {
    title: string
    start: string
    end: string
    location?: string
    description?: string
  }) => {
    const response = await client.post('/calendar/events', event)
    return response.data
  },
  updateEvent: async (eventId: string, updates: Record<string, unknown>) => {
    const response = await client.put(`/calendar/events/${eventId}`, updates)
    return response.data
  },
  deleteEvent: async (eventId: string) => {
    const response = await client.delete(`/calendar/events/${eventId}`)
    return response.data
  },
}

// Notes API
export const notesApi = {
  search: async (query: string) => {
    const response = await client.get('/notes/search', { params: { query } })
    return response.data
  },
  get: async (id: string) => {
    const response = await client.get(`/notes/${id}`)
    return response.data
  },
  create: async (note: { title?: string; content: string; tags?: string[] }) => {
    const response = await client.post('/notes', note)
    return response.data
  },
  update: async (id: string, updates: Record<string, unknown>) => {
    const response = await client.put(`/notes/${id}`, updates)
    return response.data
  },
  delete: async (id: string) => {
    const response = await client.delete(`/notes/${id}`)
    return response.data
  },
}

// Meetings API
export const meetingsApi = {
  list: async (startDate?: string, endDate?: string) => {
    const response = await client.get('/meetings', {
      params: { start_date: startDate, end_date: endDate },
    })
    return response.data
  },
  get: async (id: string) => {
    const response = await client.get(`/meetings/${id}`)
    return response.data
  },
  getSummary: async (id: string) => {
    const response = await client.get(`/meetings/${id}/summary`)
    return response.data
  },
  uploadAudio: async (id: string, file: File) => {
    const formData = new FormData()
    formData.append('audio', file)
    const response = await client.post(`/meetings/${id}/transcribe`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    })
    return response.data
  },
  upload: async (formData: FormData) => {
    const response = await client.post('/meetings/upload', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    })
    return response.data
  },
}

// Analytics API
export const analyticsApi = {
  getUsage: async (period: string = 'week') => {
    const response = await client.get('/usage/summary', { params: { period } })
    return response.data
  },
  getDailyCosts: async (days: number = 30) => {
    const response = await client.get('/usage/daily', { params: { days } })
    return response.data
  },
  getModelDistribution: async () => {
    const response = await client.get('/usage/models')
    return response.data
  },
}

// Briefings API
export const briefingsApi = {
  getDaily: async (date?: string) => {
    const response = await client.get('/briefings/daily', {
      params: date ? { briefing_date: date } : {},
    })
    return response.data
  },
  getWeekly: async (weekStart?: string) => {
    const response = await client.get('/briefings/weekly', {
      params: weekStart ? { week_start: weekStart } : {},
    })
    return response.data
  },
}

// Settings API
export const settingsApi = {
  getPreferences: async () => {
    const response = await client.get('/preferences')
    return response.data
  },
  updatePreference: async (category: string, key: string, value: unknown) => {
    const response = await client.put('/preferences', { category, key, value })
    return response.data
  },
  getRoutingConfig: async () => {
    const response = await client.get('/routing/config')
    return response.data
  },
  updateRoutingConfig: async (config: Record<string, unknown>) => {
    const response = await client.put('/routing/config', config)
    return response.data
  },
}

export default client
