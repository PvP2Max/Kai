"""User knowledge model for storing learned facts about the user."""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import ForeignKey, Index, String, Text, Float, Integer, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class UserKnowledge(Base):
    """
    Stores categorical knowledge about the user for personalized responses.

    Categories:
    - personal: name, birthday, timezone, location, etc.
    - relationships: spouse, kids, boss, coworkers, friends
    - work: job_title, company, projects, schedule
    - preferences: meeting_time, communication_style, food, etc.
    - facts: allergies, important_dates, routines, etc.

    Knowledge is retrieved selectively based on query relevance to keep
    context small and costs low.
    """

    __tablename__ = "user_knowledge"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True,
        default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True
    )

    # Knowledge categorization
    category: Mapped[str] = mapped_column(
        String(50),
        index=True
    )  # personal, relationships, work, preferences, facts

    topic: Mapped[str] = mapped_column(
        String(100),
        index=True
    )  # spouse_name, job_title, preferred_meeting_time, etc.

    value: Mapped[str] = mapped_column(Text)  # The actual knowledge

    context: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True
    )  # How/when this was learned

    # Confidence and source tracking
    confidence: Mapped[float] = mapped_column(
        Float,
        default=0.5
    )  # 0-1, higher = more confident

    source: Mapped[str] = mapped_column(
        String(50),
        default="conversation"
    )  # explicit, inferred, conversation

    # Usage tracking for relevance
    last_used: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True
    )
    use_count: Mapped[int] = mapped_column(Integer, default=0)

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
    user: Mapped["User"] = relationship(back_populates="knowledge")

    __table_args__ = (
        # Composite index for efficient category + topic lookups
        Index("ix_user_knowledge_category_topic", "user_id", "category", "topic"),
        # Index for finding high-confidence knowledge
        Index("ix_user_knowledge_confidence", "user_id", "confidence"),
    )

    def __repr__(self) -> str:
        return f"<UserKnowledge {self.category}:{self.topic}={self.value[:50]}>"
