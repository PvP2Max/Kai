import { useQuery } from '@tanstack/react-query'
import { analyticsApi } from '../api/client'

interface UsageSummary {
  period: string
  total_cost: number
  total_input_tokens: number
  total_output_tokens: number
  request_count: number
  model_breakdown: Record<string, {
    cost: number
    input_tokens: number
    output_tokens: number
    count: number
  }>
}

interface DailyCost {
  date: string
  total_cost: number
  request_count: number
}

export function useAnalytics(period: string = 'week') {
  const { data: usage, isLoading: isLoadingUsage } = useQuery<UsageSummary>({
    queryKey: ['analytics', 'usage', period],
    queryFn: () => analyticsApi.getUsage(period),
  })

  const { data: dailyCosts, isLoading: isLoadingDaily } = useQuery<{ costs: DailyCost[] }>({
    queryKey: ['analytics', 'daily'],
    queryFn: () => analyticsApi.getDailyCosts(30),
  })

  const { data: modelDist } = useQuery({
    queryKey: ['analytics', 'models'],
    queryFn: analyticsApi.getModelDistribution,
  })

  return {
    usage,
    dailyCosts: dailyCosts?.costs || [],
    modelDistribution: modelDist?.distribution || {},
    isLoading: isLoadingUsage || isLoadingDaily,
  }
}
