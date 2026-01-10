"""
Calendar schemas.
"""
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel


class CalendarEventCreate(BaseModel):
    title: str
    start: datetime
    end: datetime
    location: Optional[str] = None
    description: Optional[str] = None
    attendees: Optional[List[str]] = None
    calendar_name: Optional[str] = None


class CalendarEventUpdate(BaseModel):
    title: Optional[str] = None
    start: Optional[datetime] = None
    end: Optional[datetime] = None
    location: Optional[str] = None
    description: Optional[str] = None


class CalendarEventResponse(BaseModel):
    id: str
    title: str
    start: datetime
    end: datetime
    location: Optional[str] = None
    description: Optional[str] = None
    attendees: List[str] = []
    calendar_name: Optional[str] = None
    is_protected: bool = False


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
