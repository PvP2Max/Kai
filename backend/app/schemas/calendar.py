"""
Calendar schemas for cross-platform sync (iOS/Mac EventKit + Web).
"""
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel


class CalendarEventCreate(BaseModel):
    title: str
    start: str  # ISO datetime string
    end: str    # ISO datetime string
    is_all_day: bool = False
    location: Optional[str] = None
    description: Optional[str] = None
    attendees: Optional[List[str]] = None
    calendar_name: Optional[str] = None
    calendar_color: Optional[str] = None
    source: Optional[str] = None  # 'ios', 'mac', 'web', 'siri'
    eventkit_id: Optional[str] = None  # EventKit identifier for sync


class CalendarEventUpdate(BaseModel):
    title: Optional[str] = None
    start: Optional[str] = None  # ISO datetime string
    end: Optional[str] = None    # ISO datetime string
    is_all_day: Optional[bool] = None
    location: Optional[str] = None
    description: Optional[str] = None
    eventkit_id: Optional[str] = None


class CalendarEventResponse(BaseModel):
    id: str
    title: str
    start: str  # ISO datetime string
    end: str    # ISO datetime string
    is_all_day: bool = False
    location: Optional[str] = None
    notes: Optional[str] = None  # Maps to 'description' on create
    attendees: List[str] = []
    calendar_name: Optional[str] = None
    calendar_color: Optional[str] = None
    recurrence_rule: Optional[str] = None
    is_protected: bool = False
    eventkit_id: Optional[str] = None  # EventKit identifier for sync


class ScheduleChange(BaseModel):
    event_id: str
    event_title: str
    change_type: str  # 'move', 'shorten', 'remove'
    original_start: datetime
    original_end: datetime
    new_start: Optional[datetime] = None
    new_end: Optional[datetime] = None
    reason: str


class OptimizationRequest(BaseModel):
    date_range_start: datetime
    date_range_end: datetime
    protected_event_ids: List[str] = []
    optimization_goal: str = "efficiency"  # 'efficiency', 'focus_time', 'balance'


class OptimizationResponse(BaseModel):
    suggestions: List[ScheduleChange]
    reasoning: str
    affected_events: List[str]


class ApplyOptimizationRequest(BaseModel):
    approved_changes: List[ScheduleChange]
