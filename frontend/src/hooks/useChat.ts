import { useState, useCallback } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { chatApi } from '../api/client'

interface Message {
  id: string
  role: 'user' | 'assistant'
  content: string
  timestamp: string
  model_used?: string
}

interface Conversation {
  id: string
  messages: Message[]
  created_at: string
  source: string
}

export function useChat(conversationId?: string) {
  const queryClient = useQueryClient()
  const [currentConversationId, setCurrentConversationId] = useState<string | undefined>(conversationId)
  const [messages, setMessages] = useState<Message[]>([])

  const { data: conversations } = useQuery({
    queryKey: ['conversations'],
    queryFn: chatApi.getConversations,
  })

  const { data: conversation, isLoading: isLoadingConversation } = useQuery<Conversation>({
    queryKey: ['conversation', currentConversationId],
    queryFn: () => chatApi.getConversation(currentConversationId!),
    enabled: !!currentConversationId,
  })

  const sendMutation = useMutation({
    mutationFn: (message: string) => chatApi.send(message, currentConversationId),
    onMutate: async (message) => {
      const userMessage: Message = {
        id: `temp-${Date.now()}`,
        role: 'user',
        content: message,
        timestamp: new Date().toISOString(),
      }
      setMessages((prev) => [...prev, userMessage])
    },
    onSuccess: (data) => {
      if (!currentConversationId && data.conversation_id) {
        setCurrentConversationId(data.conversation_id)
      }

      const assistantMessage: Message = {
        id: `msg-${Date.now()}`,
        role: 'assistant',
        content: data.response,
        timestamp: new Date().toISOString(),
        model_used: data.model_used,
      }
      setMessages((prev) => [...prev, assistantMessage])
      queryClient.invalidateQueries({ queryKey: ['conversations'] })
    },
    onError: () => {
      // Remove the optimistic user message on error
      setMessages((prev) => prev.slice(0, -1))
    },
  })

  const selectConversation = useCallback((id: string) => {
    setCurrentConversationId(id)
    setMessages([])
  }, [])

  const startNewConversation = useCallback(() => {
    setCurrentConversationId(undefined)
    setMessages([])
  }, [])

  // Sync messages from loaded conversation
  if (conversation?.messages && messages.length === 0) {
    setMessages(conversation.messages)
  }

  return {
    messages,
    conversations: conversations?.conversations || [],
    currentConversationId,
    isLoading: isLoadingConversation,
    isSending: sendMutation.isPending,
    sendMessage: sendMutation.mutate,
    selectConversation,
    startNewConversation,
    error: sendMutation.error,
  }
}
