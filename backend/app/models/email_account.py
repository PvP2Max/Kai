"""Email account models for multi-account email integration."""

import uuid
from datetime import datetime, time
from typing import Optional, List

from sqlalchemy import ForeignKey, Index, String, Text, Boolean, Integer, Time, DateTime
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class EmailAccount(Base):
    """
    Stores email account configurations for multi-account support.

    Supports Gmail, Outlook, iCloud, and generic IMAP providers.
    Each account has its own OAuth tokens and briefing schedule.
    """

    __tablename__ = "email_accounts"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True,
        default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True
    )

    # Account identification
    provider: Mapped[str] = mapped_column(
        String(50)
    )  # gmail, outlook, icloud, imap

    email_address: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(100))  # "Work Email", "Personal"

    # OAuth tokens (should be encrypted in production)
    access_token: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    refresh_token: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    token_expiry: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True
    )

    # IMAP settings (for non-OAuth providers)
    imap_host: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    imap_port: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    imap_username: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    imap_password: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # Should be encrypted

    # Briefing configuration
    include_in_briefing: Mapped[bool] = mapped_column(Boolean, default=True)
    briefing_days: Mapped[Optional[List[str]]] = mapped_column(
        ARRAY(String),
        nullable=True,
        default=list
    )  # ['monday', 'tuesday', ...] or ['all']

    briefing_start_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    briefing_end_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)

    # Preferences
    priority: Mapped[int] = mapped_column(Integer, default=0)  # Order in briefing
    max_emails_in_briefing: Mapped[int] = mapped_column(Integer, default=10)
    categories_to_include: Mapped[Optional[List[str]]] = mapped_column(
        ARRAY(String),
        nullable=True,
        default=list
    )  # ['urgent', 'action_needed'] or ['all']

    # Status
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_sync: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True
    )
    sync_error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )

    # Relationships
    user: Mapped["User"] = relationship(back_populates="email_accounts")

    __table_args__ = (
        Index("ix_email_accounts_user_provider", "user_id", "provider"),
    )

    def __repr__(self) -> str:
        return f"<EmailAccount {self.display_name} ({self.email_address})>"

    def is_token_expired(self) -> bool:
        """Check if the OAuth token is expired."""
        if not self.token_expiry:
            return True
        return datetime.utcnow() > self.token_expiry

    def should_include_today(self) -> bool:
        """Check if this account should be included in today's briefing."""
        if not self.include_in_briefing or not self.is_active:
            return False

        if not self.briefing_days:
            return True  # Include all days by default

        today = datetime.now().strftime("%A").lower()  # 'monday', 'tuesday', etc.

        if "all" in self.briefing_days:
            return True
        if "weekdays" in self.briefing_days and today in ["monday", "tuesday", "wednesday", "thursday", "friday"]:
            return True
        if "weekends" in self.briefing_days and today in ["saturday", "sunday"]:
            return True

        return today in self.briefing_days


class EmailBriefingConfig(Base):
    """
    Global email briefing configuration per user.

    Allows day-specific account selection and timing preferences.
    """

    __tablename__ = "email_briefing_config"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True,
        default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        index=True
    )

    # Global settings
    briefing_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    morning_briefing_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)

    # Day-specific account overrides (stores account IDs as strings)
    weekday_accounts: Mapped[Optional[List[str]]] = mapped_column(
        ARRAY(String),
        nullable=True
    )  # Account IDs for Mon-Fri

    weekend_accounts: Mapped[Optional[List[str]]] = mapped_column(
        ARRAY(String),
        nullable=True
    )  # Account IDs for Sat-Sun

    # Granular per-day overrides (if set, overrides weekday/weekend)
    monday_accounts: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String), nullable=True)
    tuesday_accounts: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String), nullable=True)
    wednesday_accounts: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String), nullable=True)
    thursday_accounts: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String), nullable=True)
    friday_accounts: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String), nullable=True)
    saturday_accounts: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String), nullable=True)
    sunday_accounts: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String), nullable=True)

    # Days to skip entirely
    skip_days: Mapped[Optional[List[str]]] = mapped_column(
        ARRAY(String),
        nullable=True,
        default=list
    )  # ['saturday', 'sunday']

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )

    # Relationships
    user: Mapped["User"] = relationship(back_populates="email_briefing_config")

    def __repr__(self) -> str:
        return f"<EmailBriefingConfig user={self.user_id} enabled={self.briefing_enabled}>"

    def get_accounts_for_today(self) -> Optional[List[str]]:
        """Get the account IDs that should be included in today's briefing."""
        if not self.briefing_enabled:
            return []

        today = datetime.now().strftime("%A").lower()

        if self.skip_days and today in self.skip_days:
            return []

        # Check for per-day override first
        day_accounts = getattr(self, f"{today}_accounts", None)
        if day_accounts is not None:
            return day_accounts

        # Fall back to weekday/weekend
        if today in ["saturday", "sunday"]:
            return self.weekend_accounts or []
        else:
            return self.weekday_accounts or []
