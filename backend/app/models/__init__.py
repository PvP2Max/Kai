"""
SQLAlchemy models for Kai database.
"""
from app.models.user import User
from app.models.conversation import Conversation, Message
from app.models.activity import ActivityLog
from app.models.note import Note
from app.models.meeting import Meeting, ActionItem
from app.models.project import Project
from app.models.preferences import (
    Preference,
    Location,
    DeviceToken,
    ScheduledTask,
    ModelUsage,
    RoutingSettings,
)
from app.models.follow_up import FollowUp
from app.models.read_later import ReadLater
from app.models.calendar_event import CalendarEvent
from app.models.synced_reminder import SyncedReminder
from app.models.user_knowledge import UserKnowledge
from app.models.email_account import EmailAccount, EmailBriefingConfig

__all__ = [
    "User",
    "Conversation",
    "Message",
    "ActivityLog",
    "Note",
    "Meeting",
    "ActionItem",
    "Project",
    "Preference",
    "Location",
    "DeviceToken",
    "ScheduledTask",
    "ModelUsage",
    "RoutingSettings",
    "FollowUp",
    "ReadLater",
    "CalendarEvent",
    "SyncedReminder",
    "UserKnowledge",
    "EmailAccount",
    "EmailBriefingConfig",
]
