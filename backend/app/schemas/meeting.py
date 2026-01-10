"""
Meeting schemas.
"""
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel
from uuid import UUID


class ActionItemResponse(BaseModel):
    id: UUID
    description: str
    owner: Optional[str] = None
    due_date: Optional[datetime] = None
    priority: str = "medium"
    status: str = "pending"
    reminder_id: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class MeetingSummary(BaseModel):
    discussion_summary: str
    key_points: List[str]
    decisions_made: List[str]
    action_items: List[dict]
    follow_ups: List[dict]
    delegation_detected: List[dict] = []


class MeetingResponse(BaseModel):
    id: UUID
    calendar_event_id: Optional[str] = None
    event_title: Optional[str] = None
    event_start: Optional[datetime] = None
    event_end: Optional[datetime] = None
    transcript: Optional[str] = None
    summary: Optional[MeetingSummary] = None
    project_id: Optional[UUID] = None
    action_items: List[ActionItemResponse] = []
    created_at: datetime

    class Config:
        from_attributes = True


class MeetingUploadResponse(BaseModel):
    id: UUID
    message: str
    transcript: Optional[str] = None
    summary: Optional[MeetingSummary] = None
