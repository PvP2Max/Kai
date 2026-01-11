"""
CalendarEvent model for storing user calendar events.
Enables cross-platform sync between iOS/Mac (EventKit) and Web.
"""
from datetime import datetime
from typing import TYPE_CHECKING, Optional
from sqlalchemy import String, DateTime, Text, ForeignKey, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
import uuid

from app.database import Base

if TYPE_CHECKING:
    from app.models.user import User


class CalendarEvent(Base):
    __tablename__ = "calendar_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Event details
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    start: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    end: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    is_all_day: Mapped[bool] = mapped_column(Boolean, default=False)
    location: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Sync tracking - stores the EventKit identifier when synced from iOS/Mac
    eventkit_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)

    # Source of creation: 'ios', 'mac', 'web', 'siri'
    source: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)

    # Calendar metadata
    calendar_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    calendar_color: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)

    # Recurrence (stored as RRULE string if recurring)
    recurrence_rule: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="calendar_events")
