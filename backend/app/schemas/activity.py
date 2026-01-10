"""
Activity log schemas.
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel
from uuid import UUID


class ActivityLogResponse(BaseModel):
    id: UUID
    action_type: str
    action_data: dict
    source: Optional[str] = None
    reversible: bool = False
    reversed: bool = False
    created_at: datetime

    class Config:
        from_attributes = True


class UndoResponse(BaseModel):
    success: bool
    message: str
    activity_id: UUID
