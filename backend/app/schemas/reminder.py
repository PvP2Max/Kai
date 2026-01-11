"""
Reminder schemas for synced Apple Reminders.
"""
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel
from uuid import UUID


class ReminderBase(BaseModel):
    apple_reminder_id: str
    title: str
    notes: Optional[str] = None
    due_date: Optional[datetime] = None
    priority: int = 0
    is_completed: bool = False
    completed_at: Optional[datetime] = None
    list_name: Optional[str] = None
    tags: Optional[List[str]] = None


class ReminderSync(ReminderBase):
    """Single reminder for sync from iOS."""

    pass


class ReminderSyncRequest(BaseModel):
    """Request to sync reminders from iOS."""

    reminders: List[ReminderSync]


class ReminderResponse(ReminderBase):
    """Response for a single reminder."""

    id: UUID
    user_id: UUID
    project_id: Optional[UUID] = None
    synced_at: datetime
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ReminderSyncResponse(BaseModel):
    """Response after syncing reminders."""

    synced_count: int
    created_count: int
    updated_count: int
    deleted_count: int


class ReminderListResponse(BaseModel):
    """Response for listing reminders."""

    reminders: List[ReminderResponse]
    total: int
    due_today: int
    overdue: int
