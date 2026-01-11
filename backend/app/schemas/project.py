"""
Project schemas.
"""
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel
from uuid import UUID


class ProjectCreate(BaseModel):
    name: str
    description: Optional[str] = None


class ProjectUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None  # 'active', 'completed', 'archived'


class ProjectResponse(BaseModel):
    id: UUID
    name: str
    description: Optional[str] = None
    status: str = "active"
    created_at: datetime
    updated_at: datetime
    note_count: int = 0
    meeting_count: int = 0
    reminder_count: int = 0

    class Config:
        from_attributes = True


class ProjectDetailResponse(ProjectResponse):
    notes: List[dict] = []
    meetings: List[dict] = []
    action_items: List[dict] = []
    reminders: List[dict] = []


class ProjectStatusResponse(BaseModel):
    project: ProjectResponse
    summary: str
    recent_activity: List[dict]
    pending_action_items: List[dict]
    upcoming_meetings: List[dict]
