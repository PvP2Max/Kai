"""
Pydantic schemas for API request/response validation.
"""
from app.schemas.auth import (
    UserCreate,
    UserLogin,
    UserResponse,
    Token,
    TokenRefresh,
)
from app.schemas.chat import (
    ChatRequest,
    ChatResponse,
    ConversationResponse,
    MessageResponse,
    ActionTaken,
)
from app.schemas.calendar import (
    CalendarEventCreate,
    CalendarEventUpdate,
    CalendarEventResponse,
    OptimizationRequest,
    OptimizationResponse,
    ScheduleChange,
)
from app.schemas.note import (
    NoteCreate,
    NoteUpdate,
    NoteResponse,
)
from app.schemas.meeting import (
    MeetingResponse,
    MeetingSummary,
    ActionItemResponse,
)
from app.schemas.project import (
    ProjectCreate,
    ProjectUpdate,
    ProjectResponse,
)
from app.schemas.activity import (
    ActivityLogResponse,
)
from app.schemas.usage import (
    UsageSummary,
    DailyCost,
    TaskBreakdown,
)
from app.schemas.routing import (
    RoutingSettingsResponse,
    RoutingSettingsUpdate,
    RoutingTestRequest,
    RoutingTestResponse,
    ChainConfig,
)
from app.schemas.preferences import (
    PreferenceResponse,
    PreferenceUpdate,
    LocationCreate,
    LocationResponse,
)
from app.schemas.follow_up import (
    FollowUpCreate,
    FollowUpUpdate,
    FollowUpResponse,
)
from app.schemas.read_later import (
    ReadLaterCreate,
    ReadLaterResponse,
)

__all__ = [
    # Auth
    "UserCreate",
    "UserLogin",
    "UserResponse",
    "Token",
    "TokenRefresh",
    # Chat
    "ChatRequest",
    "ChatResponse",
    "ConversationResponse",
    "MessageResponse",
    "ActionTaken",
    # Calendar
    "CalendarEventCreate",
    "CalendarEventUpdate",
    "CalendarEventResponse",
    "OptimizationRequest",
    "OptimizationResponse",
    "ScheduleChange",
    # Note
    "NoteCreate",
    "NoteUpdate",
    "NoteResponse",
    # Meeting
    "MeetingResponse",
    "MeetingSummary",
    "ActionItemResponse",
    # Project
    "ProjectCreate",
    "ProjectUpdate",
    "ProjectResponse",
    # Activity
    "ActivityLogResponse",
    # Usage
    "UsageSummary",
    "DailyCost",
    "TaskBreakdown",
    # Routing
    "RoutingSettingsResponse",
    "RoutingSettingsUpdate",
    "RoutingTestRequest",
    "RoutingTestResponse",
    "ChainConfig",
    # Preferences
    "PreferenceResponse",
    "PreferenceUpdate",
    "LocationCreate",
    "LocationResponse",
    # Follow-up
    "FollowUpCreate",
    "FollowUpUpdate",
    "FollowUpResponse",
    # Read Later
    "ReadLaterCreate",
    "ReadLaterResponse",
]
