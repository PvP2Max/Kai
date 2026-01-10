"""
API routers for Kai.
"""
from app.api import auth, chat, calendar, meetings, notes, activity
from app.api import usage, routing, projects, follow_ups, read_later
from app.api import preferences, briefings, devices

__all__ = [
    "auth",
    "chat",
    "calendar",
    "meetings",
    "notes",
    "activity",
    "usage",
    "routing",
    "projects",
    "follow_ups",
    "read_later",
    "preferences",
    "briefings",
    "devices",
]
