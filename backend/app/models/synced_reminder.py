"""
SyncedReminder model for storing reminders synced from Apple Reminders.
"""
from datetime import datetime
from typing import TYPE_CHECKING, Optional
from sqlalchemy import String, DateTime, Text, ForeignKey, Boolean, ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
import uuid

from app.database import Base

if TYPE_CHECKING:
    from app.models.user import User
    from app.models.project import Project


class SyncedReminder(Base):
    __tablename__ = "synced_reminders"

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
    apple_reminder_id: Mapped[str] = mapped_column(
        String(255), nullable=False, index=True
    )  # EKReminder calendarItemIdentifier
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    due_date: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    priority: Mapped[int] = mapped_column(default=0)  # 0=none, 1=low, 5=medium, 9=high
    is_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    list_name: Mapped[Optional[str]] = mapped_column(
        String(255), nullable=True
    )  # Apple Reminders list name
    project_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="SET NULL"),
        nullable=True,
    )
    tags: Mapped[Optional[list[str]]] = mapped_column(ARRAY(Text), nullable=True)
    synced_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="synced_reminders")
    project: Mapped[Optional["Project"]] = relationship(
        "Project", back_populates="synced_reminders"
    )
