"""
Note schemas.
"""
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel
from uuid import UUID


class NoteCreate(BaseModel):
    title: Optional[str] = None
    content: str
    project_id: Optional[UUID] = None
    tags: Optional[List[str]] = None
    source: Optional[str] = "manual"


class NoteUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    project_id: Optional[UUID] = None
    tags: Optional[List[str]] = None


class NoteResponse(BaseModel):
    id: UUID
    title: Optional[str] = None
    content: str
    source: Optional[str] = None
    meeting_event_id: Optional[str] = None
    project_id: Optional[UUID] = None
    tags: Optional[List[str]] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
