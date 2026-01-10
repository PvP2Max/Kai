"""
Usage analytics schemas.
"""
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel


class ModelUsageStats(BaseModel):
    requests: int
    input_tokens: int
    output_tokens: int
    cost: float


class TaskUsageStats(BaseModel):
    requests: int
    cost: float


class UsageTotals(BaseModel):
    requests: int
    input_tokens: int
    output_tokens: int
    cost: float
    avg_latency_ms: int


class UsageSummary(BaseModel):
    period: str
    start: str
    end: str
    by_model: dict[str, ModelUsageStats]
    by_task: dict[str, TaskUsageStats]
    totals: UsageTotals


class DailyCost(BaseModel):
    date: str
    haiku: float
    sonnet: float
    opus: float
    total: float


class TaskBreakdown(BaseModel):
    task_type: str
    requests: int
    cost: float
    avg_latency_ms: int
    primary_model: str


class CostResponse(BaseModel):
    current_period: float
    projected_month: float
    by_day: List[DailyCost]
