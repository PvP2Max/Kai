"""
Kai - Kamron's Adaptive Intelligence
FastAPI Application Entry Point
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.config import settings
from app.database import async_engine, Base
from app.api import auth, chat, calendar, meetings, notes, activity, usage, routing
from app.api import projects, follow_ups, read_later, preferences, briefings, devices, reminders, email_accounts


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    # Startup
    async with async_engine.begin() as conn:
        # Create tables if they don't exist (for development)
        # In production, use Alembic migrations
        await conn.run_sync(Base.metadata.create_all)
    yield
    # Shutdown
    await async_engine.dispose()


app = FastAPI(
    title="Kai API",
    description="Kamron's Adaptive Intelligence - Personal AI Assistant",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",  # Vite dev server
        "http://localhost:3000",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:3000",
        "https://kai.pvp2max.com",  # Production
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(chat.router, prefix="/api", tags=["Chat"])
app.include_router(calendar.router, prefix="/api/calendar", tags=["Calendar"])
app.include_router(meetings.router, prefix="/api/meetings", tags=["Meetings"])
app.include_router(notes.router, prefix="/api/notes", tags=["Notes"])
app.include_router(activity.router, prefix="/api/activity", tags=["Activity"])
app.include_router(usage.router, prefix="/api/usage", tags=["Usage Analytics"])
app.include_router(routing.router, prefix="/api/routing", tags=["Model Routing"])
app.include_router(projects.router, prefix="/api/projects", tags=["Projects"])
app.include_router(follow_ups.router, prefix="/api/follow-ups", tags=["Follow-ups"])
app.include_router(read_later.router, prefix="/api/read-later", tags=["Read Later"])
app.include_router(preferences.router, prefix="/api/preferences", tags=["Preferences"])
app.include_router(briefings.router, prefix="/api/briefings", tags=["Briefings"])
app.include_router(devices.router, prefix="/api/devices", tags=["Devices"])
app.include_router(reminders.router, prefix="/api/reminders", tags=["Reminders"])
app.include_router(email_accounts.router, prefix="/api", tags=["Email Accounts"])


@app.get("/")
async def root():
    """Health check endpoint."""
    return {"status": "healthy", "service": "Kai API", "version": "1.0.0"}


@app.get("/health")
async def health_check():
    """Detailed health check."""
    return {
        "status": "healthy",
        "database": "connected",
        "anthropic_configured": bool(settings.anthropic_api_key),
        "caldav_configured": bool(settings.caldav_url),
        "gmail_configured": bool(settings.google_client_id),
    }
