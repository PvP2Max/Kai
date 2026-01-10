"""
Preferences and locations schemas.
"""
from datetime import datetime
from typing import Optional, List, Any
from pydantic import BaseModel
from uuid import UUID


class PreferenceResponse(BaseModel):
    id: UUID
    category: str
    key: str
    value: Any
    learned: bool
    confidence: float
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class PreferenceUpdate(BaseModel):
    category: str
    key: str
    value: Any
    learned: bool = False


class PreferencesResponse(BaseModel):
    preferences: List[PreferenceResponse]
    by_category: dict


class LocationCreate(BaseModel):
    name: str
    address: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class LocationResponse(BaseModel):
    id: UUID
    name: str
    address: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    created_at: datetime

    class Config:
        from_attributes = True
