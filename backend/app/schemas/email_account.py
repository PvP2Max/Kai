"""Pydantic schemas for email account management."""

from datetime import time, datetime
from typing import Optional, List
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class EmailAccountBase(BaseModel):
    """Base schema for email account."""
    provider: str = Field(..., description="Email provider: gmail, outlook, icloud, imap")
    email_address: EmailStr
    display_name: str = Field(..., min_length=1, max_length=100)


class EmailAccountCreate(EmailAccountBase):
    """Schema for creating an email account."""
    # OAuth tokens (from OAuth flow)
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None

    # IMAP settings (for non-OAuth providers)
    imap_host: Optional[str] = None
    imap_port: Optional[int] = None
    imap_username: Optional[str] = None
    imap_password: Optional[str] = None


class EmailAccountUpdate(BaseModel):
    """Schema for updating an email account."""
    display_name: Optional[str] = None
    include_in_briefing: Optional[bool] = None
    briefing_days: Optional[List[str]] = None
    briefing_start_time: Optional[str] = None  # HH:MM format
    briefing_end_time: Optional[str] = None  # HH:MM format
    priority: Optional[int] = None
    max_emails_in_briefing: Optional[int] = None
    categories_to_include: Optional[List[str]] = None
    is_active: Optional[bool] = None


class EmailAccountResponse(EmailAccountBase):
    """Schema for email account response."""
    id: UUID
    include_in_briefing: bool
    briefing_days: Optional[List[str]]
    briefing_start_time: Optional[time]
    briefing_end_time: Optional[time]
    priority: int
    max_emails_in_briefing: int
    categories_to_include: Optional[List[str]]
    is_active: bool
    last_sync: Optional[datetime]
    sync_error: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class EmailAccountListResponse(BaseModel):
    """Schema for list of email accounts."""
    accounts: List[EmailAccountResponse]
    count: int


# Briefing Config Schemas

class EmailBriefingConfigUpdate(BaseModel):
    """Schema for updating email briefing configuration."""
    briefing_enabled: Optional[bool] = None
    morning_briefing_time: Optional[str] = None  # HH:MM format

    # Day-specific account overrides
    weekday_accounts: Optional[List[str]] = None
    weekend_accounts: Optional[List[str]] = None

    # Granular per-day overrides
    monday_accounts: Optional[List[str]] = None
    tuesday_accounts: Optional[List[str]] = None
    wednesday_accounts: Optional[List[str]] = None
    thursday_accounts: Optional[List[str]] = None
    friday_accounts: Optional[List[str]] = None
    saturday_accounts: Optional[List[str]] = None
    sunday_accounts: Optional[List[str]] = None

    # Days to skip
    skip_days: Optional[List[str]] = None


class EmailBriefingConfigResponse(BaseModel):
    """Schema for email briefing configuration response."""
    id: UUID
    briefing_enabled: bool
    morning_briefing_time: Optional[time]
    weekday_accounts: Optional[List[str]]
    weekend_accounts: Optional[List[str]]
    monday_accounts: Optional[List[str]]
    tuesday_accounts: Optional[List[str]]
    wednesday_accounts: Optional[List[str]]
    thursday_accounts: Optional[List[str]]
    friday_accounts: Optional[List[str]]
    saturday_accounts: Optional[List[str]]
    sunday_accounts: Optional[List[str]]
    skip_days: Optional[List[str]]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# OAuth Schemas

class OAuthStartResponse(BaseModel):
    """Response for starting OAuth flow."""
    auth_url: str
    state: str


class OAuthCallbackRequest(BaseModel):
    """Request for OAuth callback."""
    code: str
    state: str
    provider: str


class OAuthCallbackResponse(BaseModel):
    """Response for OAuth callback."""
    success: bool
    account_id: Optional[UUID] = None
    email_address: Optional[str] = None
    error: Optional[str] = None
