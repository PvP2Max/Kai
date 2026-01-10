"""
Read later schemas.
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, HttpUrl
from uuid import UUID


class ReadLaterCreate(BaseModel):
    url: str
    title: Optional[str] = None


class ReadLaterUpdate(BaseModel):
    is_read: Optional[bool] = None
    title: Optional[str] = None


class ReadLaterResponse(BaseModel):
    id: UUID
    url: str
    title: Optional[str] = None
    summary: Optional[str] = None
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True
