import { useState, useEffect, useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { authApi } from '../api/client'

interface User {
  id: string
  email: string
  name: string
  timezone: string
}

export function useAuth() {
  const queryClient = useQueryClient()
  const [isAuthenticated, setIsAuthenticated] = useState(() => {
    return !!localStorage.getItem('access_token')
  })

  const { data: user, isLoading } = useQuery<User>({
    queryKey: ['user'],
    queryFn: authApi.me,
    enabled: isAuthenticated,
    retry: false,
  })

  const loginMutation = useMutation({
    mutationFn: ({ email, password }: { email: string; password: string }) =>
      authApi.login(email, password),
    onSuccess: async (data) => {
      localStorage.setItem('access_token', data.access_token)
      localStorage.setItem('refresh_token', data.refresh_token)
      setIsAuthenticated(true)
      queryClient.invalidateQueries({ queryKey: ['user'] })
      // Sync browser timezone to backend
      await authApi.syncTimezone()
    },
  })

  const registerMutation = useMutation({
    mutationFn: ({ email, password, name }: { email: string; password: string; name: string }) =>
      authApi.register(email, password, name),
    onSuccess: async (data) => {
      localStorage.setItem('access_token', data.access_token)
      localStorage.setItem('refresh_token', data.refresh_token)
      setIsAuthenticated(true)
      queryClient.invalidateQueries({ queryKey: ['user'] })
      // Sync browser timezone to backend
      await authApi.syncTimezone()
    },
  })

  const logout = useCallback(() => {
    authApi.logout()
    setIsAuthenticated(false)
    queryClient.clear()
  }, [queryClient])

  useEffect(() => {
    const token = localStorage.getItem('access_token')
    setIsAuthenticated(!!token)
  }, [])

  // Sync timezone when user data is loaded (for existing sessions)
  useEffect(() => {
    if (user) {
      const browserTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (user.timezone !== browserTimezone) {
        authApi.syncTimezone()
      }
    }
  }, [user])

  return {
    user,
    isAuthenticated,
    isLoading,
    login: loginMutation.mutate,
    register: registerMutation.mutate,
    logout,
    loginError: loginMutation.error,
    registerError: registerMutation.error,
    isLoggingIn: loginMutation.isPending,
    isRegistering: registerMutation.isPending,
  }
}
