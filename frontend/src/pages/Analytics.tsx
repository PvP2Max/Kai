import { useState } from 'react'
import { useAnalytics } from '../hooks/useAnalytics'
import {
  LineChart,
  Line,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
} from 'recharts'
import { format } from 'date-fns'
import clsx from 'clsx'

const COLORS = ['#0ea5e9', '#10b981', '#8b5cf6', '#f59e0b']

export default function Analytics() {
  const [period, setPeriod] = useState('week')
  const { usage, dailyCosts, modelDistribution, isLoading } = useAnalytics(period)

  const formatCost = (value: number | undefined | null) => `$${(value ?? 0).toFixed(4)}`

  const pieData = Object.entries(modelDistribution || {}).map(([name, value]) => ({
    name: name.includes('haiku') ? 'Haiku' : name.includes('sonnet') ? 'Sonnet' : 'Opus',
    value: value as number,
  }))

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Analytics</h1>
          <p className="text-gray-600">Usage metrics and cost tracking</p>
        </div>
        <div className="flex items-center gap-2">
          {['day', 'week', 'month'].map((p) => (
            <button
              key={p}
              onClick={() => setPeriod(p)}
              className={clsx(
                'px-3 py-1.5 text-sm font-medium rounded-lg',
                period === p
                  ? 'bg-primary-100 text-primary-700'
                  : 'text-gray-600 hover:bg-gray-100'
              )}
            >
              {p.charAt(0).toUpperCase() + p.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="card">
          <p className="text-sm text-gray-500">Total Cost</p>
          <p className="text-2xl font-bold text-gray-900">
            {usage ? formatCost(usage.total_cost) : '$0.00'}
          </p>
          <p className="text-xs text-gray-400 mt-1">This {period}</p>
        </div>
        <div className="card">
          <p className="text-sm text-gray-500">Requests</p>
          <p className="text-2xl font-bold text-gray-900">
            {usage?.request_count || 0}
          </p>
          <p className="text-xs text-gray-400 mt-1">API calls</p>
        </div>
        <div className="card">
          <p className="text-sm text-gray-500">Input Tokens</p>
          <p className="text-2xl font-bold text-gray-900">
            {(usage?.total_input_tokens || 0).toLocaleString()}
          </p>
          <p className="text-xs text-gray-400 mt-1">Processed</p>
        </div>
        <div className="card">
          <p className="text-sm text-gray-500">Output Tokens</p>
          <p className="text-2xl font-bold text-gray-900">
            {(usage?.total_output_tokens || 0).toLocaleString()}
          </p>
          <p className="text-xs text-gray-400 mt-1">Generated</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Daily Costs Chart */}
        <div className="lg:col-span-2 card">
          <h2 className="text-lg font-semibold mb-4">Daily Costs</h2>
          {isLoading ? (
            <div className="h-64 flex items-center justify-center">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600" />
            </div>
          ) : (
            <ResponsiveContainer width="100%" height={256}>
              <LineChart data={dailyCosts}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis
                  dataKey="date"
                  tickFormatter={(value) => format(new Date(value), 'MMM d')}
                  stroke="#9ca3af"
                  fontSize={12}
                />
                <YAxis
                  tickFormatter={(value) => `$${value.toFixed(2)}`}
                  stroke="#9ca3af"
                  fontSize={12}
                />
                <Tooltip
                  formatter={(value: number) => [formatCost(value), 'Cost']}
                  labelFormatter={(label) => format(new Date(label), 'MMM d, yyyy')}
                />
                <Line
                  type="monotone"
                  dataKey="total_cost"
                  stroke="#0ea5e9"
                  strokeWidth={2}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          )}
        </div>

        {/* Model Distribution */}
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Model Usage</h2>
          {pieData.length > 0 ? (
            <ResponsiveContainer width="100%" height={200}>
              <PieChart>
                <Pie
                  data={pieData}
                  cx="50%"
                  cy="50%"
                  innerRadius={50}
                  outerRadius={80}
                  paddingAngle={2}
                  dataKey="value"
                >
                  {pieData.map((_, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <div className="h-48 flex items-center justify-center text-gray-500">
              No data available
            </div>
          )}
          <div className="flex justify-center gap-4 mt-4">
            {pieData.map((entry, index) => (
              <div key={entry.name} className="flex items-center">
                <div
                  className="w-3 h-3 rounded-full mr-2"
                  style={{ backgroundColor: COLORS[index % COLORS.length] }}
                />
                <span className="text-sm text-gray-600">{entry.name}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Model Breakdown Table */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Model Breakdown</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b">
                <th className="text-left py-2 font-medium text-gray-500">Model</th>
                <th className="text-right py-2 font-medium text-gray-500">Requests</th>
                <th className="text-right py-2 font-medium text-gray-500">Input Tokens</th>
                <th className="text-right py-2 font-medium text-gray-500">Output Tokens</th>
                <th className="text-right py-2 font-medium text-gray-500">Cost</th>
              </tr>
            </thead>
            <tbody>
              {usage?.model_breakdown &&
                Object.entries(usage.model_breakdown).map(([model, data]) => (
                  <tr key={model} className="border-b last:border-0">
                    <td className="py-3 font-medium">
                      {model.includes('haiku')
                        ? 'Claude Haiku'
                        : model.includes('sonnet')
                        ? 'Claude Sonnet'
                        : 'Claude Opus'}
                    </td>
                    <td className="py-3 text-right text-gray-600">{data.count}</td>
                    <td className="py-3 text-right text-gray-600">
                      {data.input_tokens.toLocaleString()}
                    </td>
                    <td className="py-3 text-right text-gray-600">
                      {data.output_tokens.toLocaleString()}
                    </td>
                    <td className="py-3 text-right font-medium">{formatCost(data.cost)}</td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
