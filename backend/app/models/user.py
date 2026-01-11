"""
User model for authentication and user management.
"""
from datetime import datetime
from typing import TYPE_CHECKING
from sqlalchemy import String, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
import uuid

from app.database import Base

if TYPE_CHECKING:
    from app.models.conversation import Conversation
    from app.models.note import Note
    from app.models.project import Project
    from app.models.calendar_event import CalendarEvent
    from app.models.synced_reminder import SyncedReminder
    from app.models.user_knowledge import UserKnowledge
    from app.models.email_account import EmailAccount, EmailBriefingConfig


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    timezone: Mapped[str] = mapped_column(String(50), nullable=False, default="America/Chicago")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relationships
    conversations: Mapped[list["Conversation"]] = relationship(
        "Conversation", back_populates="user", cascade="all, delete-orphan"
    )
    notes: Mapped[list["Note"]] = relationship(
        "Note", back_populates="user", cascade="all, delete-orphan"
    )
    projects: Mapped[list["Project"]] = relationship(
        "Project", back_populates="user", cascade="all, delete-orphan"
    )
    calendar_events: Mapped[list["CalendarEvent"]] = relationship(
        "CalendarEvent", back_populates="user", cascade="all, delete-orphan"
    )
    synced_reminders: Mapped[list["SyncedReminder"]] = relationship(
        "SyncedReminder", back_populates="user", cascade="all, delete-orphan"
    )
    knowledge: Mapped[list["UserKnowledge"]] = relationship(
        "UserKnowledge", back_populates="user", cascade="all, delete-orphan"
    )
    email_accounts: Mapped[list["EmailAccount"]] = relationship(
        "EmailAccount", back_populates="user", cascade="all, delete-orphan"
    )
    email_briefing_config: Mapped["EmailBriefingConfig"] = relationship(
        "EmailBriefingConfig", back_populates="user", cascade="all, delete-orphan", uselist=False
    )
