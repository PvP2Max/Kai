import { useState, useRef, useEffect } from 'react'
import { useChat } from '../hooks/useChat'
import { Send, Plus, MessageSquare } from 'lucide-react'
import clsx from 'clsx'

export default function Chat() {
  const [input, setInput] = useState('')
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)

  const {
    messages,
    conversations,
    isSending,
    sendMessage,
    selectConversation,
    startNewConversation,
    currentConversationId,
  } = useChat()

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim() || isSending) return

    sendMessage(input.trim())
    setInput('')
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSubmit(e)
    }
  }

  return (
    <div className="flex h-[calc(100vh-8rem)]">
      {/* Sidebar */}
      <div className="w-64 border-r bg-white hidden md:block">
        <div className="p-4">
          <button
            onClick={startNewConversation}
            className="w-full btn btn-primary flex items-center justify-center"
          >
            <Plus className="w-4 h-4 mr-2" />
            New Chat
          </button>
        </div>
        <div className="px-2 space-y-1 overflow-y-auto max-h-[calc(100vh-12rem)]">
          {conversations.map((conv: { id: string; title?: string; created_at: string }) => (
            <button
              key={conv.id}
              onClick={() => selectConversation(conv.id)}
              className={clsx(
                'w-full flex items-center px-3 py-2 text-sm rounded-lg text-left',
                currentConversationId === conv.id
                  ? 'bg-primary-50 text-primary-700'
                  : 'text-gray-700 hover:bg-gray-100'
              )}
            >
              <MessageSquare className="w-4 h-4 mr-2 flex-shrink-0" />
              <span className="truncate">
                {conv.title || 'Conversation'}
              </span>
            </button>
          ))}
        </div>
      </div>

      {/* Chat area */}
      <div className="flex-1 flex flex-col bg-white">
        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.length === 0 ? (
            <div className="flex items-center justify-center h-full">
              <div className="text-center">
                <h2 className="text-xl font-semibold text-gray-900">
                  Hello! I'm Kai, your personal assistant.
                </h2>
                <p className="mt-2 text-gray-600">
                  How can I help you today?
                </p>
                <div className="mt-6 grid grid-cols-1 md:grid-cols-2 gap-3 max-w-lg mx-auto">
                  {[
                    "What's on my calendar today?",
                    "Help me prepare for my next meeting",
                    "Draft a follow-up email",
                    "Show me my pending tasks",
                  ].map((suggestion) => (
                    <button
                      key={suggestion}
                      onClick={() => {
                        setInput(suggestion)
                        inputRef.current?.focus()
                      }}
                      className="p-3 text-sm text-left bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
                    >
                      {suggestion}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          ) : (
            messages.map((message) => (
              <div
                key={message.id}
                className={clsx(
                  'flex',
                  message.role === 'user' ? 'justify-end' : 'justify-start'
                )}
              >
                <div
                  className={clsx(
                    'max-w-[80%] rounded-2xl px-4 py-2',
                    message.role === 'user'
                      ? 'bg-primary-600 text-white'
                      : 'bg-gray-100 text-gray-900'
                  )}
                >
                  <p className="whitespace-pre-wrap">{message.content}</p>
                  {message.model_used && message.role === 'assistant' && (
                    <p className="mt-1 text-xs opacity-60">
                      {message.model_used.includes('haiku')
                        ? 'Haiku'
                        : message.model_used.includes('sonnet')
                        ? 'Sonnet'
                        : 'Opus'}
                    </p>
                  )}
                </div>
              </div>
            ))
          )}
          {isSending && (
            <div className="flex justify-start">
              <div className="bg-gray-100 rounded-2xl px-4 py-2">
                <div className="flex space-x-2">
                  <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" />
                  <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce delay-100" />
                  <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce delay-200" />
                </div>
              </div>
            </div>
          )}
          <div ref={messagesEndRef} />
        </div>

        {/* Input */}
        <div className="border-t p-4">
          <form onSubmit={handleSubmit} className="flex items-end gap-2">
            <textarea
              ref={inputRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Message Kai..."
              rows={1}
              className="flex-1 input resize-none max-h-32"
              style={{
                height: 'auto',
                minHeight: '44px',
              }}
            />
            <button
              type="submit"
              disabled={!input.trim() || isSending}
              className="btn btn-primary p-3"
            >
              <Send className="w-5 h-5" />
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}
