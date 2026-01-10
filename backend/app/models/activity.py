"""
Activity log model for tracking all Kai actions.
"""
from datetime import datetime
from typing import Optional
from sqlalchemy import String, DateTime, Boolean, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID, JSONB
import uuid

from app.database import Base


class ActivityLog(Base):
    __tablename__ = "activity_log"

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
    action_type: Mapped[str] = mapped_column(
        String(100), nullable=False, index=True
    )  # 'calendar_create', 'reminder_create', etc.
    action_data: Mapped[dict] = mapped_column(JSONB, nullable=False)
    source: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)  # 'siri', 'web', 'proactive'
    reversible: Mapped[bool] = mapped_column(Boolean, default=False)
    reversed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
