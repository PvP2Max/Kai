"""
Follow-up schemas.
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel
from uuid import UUID


class FollowUpCreate(BaseModel):
    contact_name: str
    contact_email: Optional[str] = None
    context: str
    follow_up_date: Optional[datetime] = None
    last_contact_date: Optional[datetime] = None


class FollowUpUpdate(BaseModel):
    contact_name: Optional[str] = None
    contact_email: Optional[str] = None
    context: Optional[str] = None
    follow_up_date: Optional[datetime] = None
    last_contact_date: Optional[datetime] = None
    status: Optional[str] = None  # 'waiting', 'responded', 'closed'


class FollowUpResponse(BaseModel):
    id: UUID
    contact_name: str
    contact_email: Optional[str] = None
    context: Optional[str] = None
    last_contact_date: Optional[datetime] = None
    follow_up_date: Optional[datetime] = None
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class NudgeResponse(BaseModel):
    follow_up_id: UUID
    draft_email: str
    subject: str
