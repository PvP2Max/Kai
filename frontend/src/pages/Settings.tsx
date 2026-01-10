import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { settingsApi } from '../api/client'
import { Save, Check } from 'lucide-react'
import clsx from 'clsx'

export default function Settings() {
  const queryClient = useQueryClient()
  const [activeTab, setActiveTab] = useState('preferences')
  const [saved, setSaved] = useState(false)

  const { data: preferences } = useQuery({
    queryKey: ['preferences'],
    queryFn: settingsApi.getPreferences,
  })

  const { data: routingConfig } = useQuery({
    queryKey: ['routing', 'config'],
    queryFn: settingsApi.getRoutingConfig,
  })

  const [localConfig, setLocalConfig] = useState({
    default_model: 'haiku',
    use_smart_routing: true,
    allow_opus: true,
    daily_cost_limit: 10,
  })

  const updateMutation = useMutation({
    mutationFn: (config: Record<string, unknown>) => settingsApi.updateRoutingConfig(config),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['routing'] })
      setSaved(true)
      setTimeout(() => setSaved(false), 2000)
    },
  })

  const handleSave = () => {
    updateMutation.mutate(localConfig)
  }

  const tabs = [
    { id: 'preferences', label: 'Preferences' },
    { id: 'models', label: 'Model Settings' },
    { id: 'integrations', label: 'Integrations' },
  ]

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Settings</h1>
        <p className="text-gray-600">Manage your preferences and configurations</p>
      </div>

      {/* Tabs */}
      <div className="border-b">
        <nav className="flex gap-4">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={clsx(
                'py-2 px-1 border-b-2 font-medium text-sm transition-colors',
                activeTab === tab.id
                  ? 'border-primary-500 text-primary-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              )}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      {activeTab === 'preferences' && (
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">General Preferences</h2>
          <div className="space-y-6">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Preferred Meeting Hours
              </label>
              <p className="text-sm text-gray-500 mb-2">
                Select your preferred hours for scheduling meetings
              </p>
              <div className="grid grid-cols-6 gap-2">
                {Array.from({ length: 12 }, (_, i) => i + 8).map((hour) => (
                  <button
                    key={hour}
                    className={clsx(
                      'py-2 text-sm rounded-lg border',
                      preferences?.scheduling?.preferred_meeting_hours?.includes(hour)
                        ? 'bg-primary-50 border-primary-300 text-primary-700'
                        : 'bg-white border-gray-300 text-gray-700 hover:bg-gray-50'
                    )}
                  >
                    {hour > 12 ? `${hour - 12} PM` : hour === 12 ? '12 PM' : `${hour} AM`}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Default Email Tone
              </label>
              <select className="input">
                <option value="friendly">Friendly</option>
                <option value="casual">Casual</option>
                <option value="formal">Formal</option>
              </select>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900">Avoid back-to-back meetings</p>
                <p className="text-sm text-gray-500">
                  Add buffer time between meetings when scheduling
                </p>
              </div>
              <button
                className={clsx(
                  'relative inline-flex h-6 w-11 items-center rounded-full transition-colors',
                  preferences?.scheduling?.avoid_back_to_back
                    ? 'bg-primary-600'
                    : 'bg-gray-200'
                )}
              >
                <span
                  className={clsx(
                    'inline-block h-4 w-4 transform rounded-full bg-white transition-transform',
                    preferences?.scheduling?.avoid_back_to_back
                      ? 'translate-x-6'
                      : 'translate-x-1'
                  )}
                />
              </button>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'models' && (
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Model Configuration</h2>
          <div className="space-y-6">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Default Model
              </label>
              <select
                value={localConfig.default_model}
                onChange={(e) =>
                  setLocalConfig({ ...localConfig, default_model: e.target.value })
                }
                className="input"
              >
                <option value="haiku">Claude Haiku (Fastest, Cheapest)</option>
                <option value="sonnet">Claude Sonnet (Balanced)</option>
                <option value="opus">Claude Opus (Most Capable)</option>
              </select>
              <p className="mt-1 text-sm text-gray-500">
                Used for simple queries when smart routing is disabled
              </p>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900">Smart Model Routing</p>
                <p className="text-sm text-gray-500">
                  Automatically select the best model based on query complexity
                </p>
              </div>
              <button
                onClick={() =>
                  setLocalConfig({
                    ...localConfig,
                    use_smart_routing: !localConfig.use_smart_routing,
                  })
                }
                className={clsx(
                  'relative inline-flex h-6 w-11 items-center rounded-full transition-colors',
                  localConfig.use_smart_routing ? 'bg-primary-600' : 'bg-gray-200'
                )}
              >
                <span
                  className={clsx(
                    'inline-block h-4 w-4 transform rounded-full bg-white transition-transform',
                    localConfig.use_smart_routing ? 'translate-x-6' : 'translate-x-1'
                  )}
                />
              </button>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900">Allow Opus for Complex Tasks</p>
                <p className="text-sm text-gray-500">
                  Use Claude Opus for highly complex or multi-step tasks
                </p>
              </div>
              <button
                onClick={() =>
                  setLocalConfig({
                    ...localConfig,
                    allow_opus: !localConfig.allow_opus,
                  })
                }
                className={clsx(
                  'relative inline-flex h-6 w-11 items-center rounded-full transition-colors',
                  localConfig.allow_opus ? 'bg-primary-600' : 'bg-gray-200'
                )}
              >
                <span
                  className={clsx(
                    'inline-block h-4 w-4 transform rounded-full bg-white transition-transform',
                    localConfig.allow_opus ? 'translate-x-6' : 'translate-x-1'
                  )}
                />
              </button>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Daily Cost Limit ($)
              </label>
              <input
                type="number"
                value={localConfig.daily_cost_limit}
                onChange={(e) =>
                  setLocalConfig({
                    ...localConfig,
                    daily_cost_limit: parseFloat(e.target.value),
                  })
                }
                min="0"
                step="0.5"
                className="input w-32"
              />
              <p className="mt-1 text-sm text-gray-500">
                Pause requests when daily cost exceeds this limit
              </p>
            </div>

            <div className="pt-4 border-t flex justify-end">
              <button
                onClick={handleSave}
                disabled={updateMutation.isPending}
                className="btn btn-primary flex items-center"
              >
                {saved ? (
                  <>
                    <Check className="w-4 h-4 mr-2" />
                    Saved
                  </>
                ) : (
                  <>
                    <Save className="w-4 h-4 mr-2" />
                    Save Changes
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'integrations' && (
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">External Integrations</h2>
          <div className="space-y-4">
            <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
              <div className="flex items-center">
                <div className="w-10 h-10 bg-white rounded-lg flex items-center justify-center">
                  📅
                </div>
                <div className="ml-4">
                  <p className="font-medium text-gray-900">Apple Calendar (CalDAV)</p>
                  <p className="text-sm text-gray-500">Sync with iCloud Calendar</p>
                </div>
              </div>
              <span className="px-2 py-1 text-xs bg-yellow-100 text-yellow-800 rounded">
                Not Configured
              </span>
            </div>

            <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
              <div className="flex items-center">
                <div className="w-10 h-10 bg-white rounded-lg flex items-center justify-center">
                  ✉️
                </div>
                <div className="ml-4">
                  <p className="font-medium text-gray-900">Gmail</p>
                  <p className="text-sm text-gray-500">Read and draft emails</p>
                </div>
              </div>
              <span className="px-2 py-1 text-xs bg-yellow-100 text-yellow-800 rounded">
                Not Configured
              </span>
            </div>

            <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
              <div className="flex items-center">
                <div className="w-10 h-10 bg-white rounded-lg flex items-center justify-center">
                  📱
                </div>
                <div className="ml-4">
                  <p className="font-medium text-gray-900">Push Notifications (APNs)</p>
                  <p className="text-sm text-gray-500">iOS and Apple Watch notifications</p>
                </div>
              </div>
              <span className="px-2 py-1 text-xs bg-yellow-100 text-yellow-800 rounded">
                Not Configured
              </span>
            </div>

            <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
              <div className="flex items-center">
                <div className="w-10 h-10 bg-white rounded-lg flex items-center justify-center">
                  🗺️
                </div>
                <div className="ml-4">
                  <p className="font-medium text-gray-900">Google Maps</p>
                  <p className="text-sm text-gray-500">Travel time and directions</p>
                </div>
              </div>
              <span className="px-2 py-1 text-xs bg-yellow-100 text-yellow-800 rounded">
                Not Configured
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
