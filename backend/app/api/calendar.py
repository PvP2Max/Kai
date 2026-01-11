"""
Calendar endpoints for event management.
Uses database storage for cross-platform sync (iOS/Mac EventKit + Web).
"""
from datetime import datetime
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.database import get_db
from app.models.user import User
from app.models.calendar_event import CalendarEvent
from app.schemas.calendar import (
    CalendarEventCreate,
    CalendarEventUpdate,
    CalendarEventResponse,
    OptimizationRequest,
    OptimizationResponse,
    ApplyOptimizationRequest,
)
from app.api.deps import get_current_user

router = APIRouter()


@router.get("/events", response_model=List[CalendarEventResponse])
async def list_events(
    start_date: str = Query(None, description="Start date (ISO format)"),
    end_date: str = Query(None, description="End date (ISO format)"),
    start: datetime = Query(None, description="Start datetime (ISO format)"),
    end: datetime = Query(None, description="End datetime (ISO format)"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    List calendar events for a date range.
    Returns events from the database for the authenticated user.
    """
    # Handle both start_date/end_date (string) and start/end (datetime) params
    start_dt = None
    end_dt = None

    if start_date:
        start_dt = datetime.fromisoformat(start_date.replace("Z", "+00:00"))
    elif start:
        start_dt = start

    if end_date:
        end_dt = datetime.fromisoformat(end_date.replace("Z", "+00:00"))
    elif end:
        end_dt = end

    if not start_dt or not end_dt:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="start_date and end_date are required",
        )

    # Query database for user's events in date range
    result = await db.execute(
        select(CalendarEvent)
        .where(
            and_(
                CalendarEvent.user_id == current_user.id,
                CalendarEvent.start >= start_dt,
                CalendarEvent.start <= end_dt,
            )
        )
        .order_by(CalendarEvent.start)
    )
    events = result.scalars().all()

    return [
        CalendarEventResponse(
            id=str(event.id),
            title=event.title,
            start=event.start.isoformat(),
            end=event.end.isoformat(),
            is_all_day=event.is_all_day,
            location=event.location,
            notes=event.notes,
            attendees=[],
            calendar_color=event.calendar_color,
            calendar_name=event.calendar_name,
            recurrence_rule=event.recurrence_rule,
            is_protected=False,
            eventkit_id=event.eventkit_id,
        )
        for event in events
    ]


@router.post("/events", response_model=CalendarEventResponse, status_code=status.HTTP_201_CREATED)
async def create_event(
    event_data: CalendarEventCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Create a new calendar event.
    Stores in database for cross-platform sync.
    """
    # Parse datetime strings
    start_dt = datetime.fromisoformat(event_data.start.replace("Z", "+00:00"))
    end_dt = datetime.fromisoformat(event_data.end.replace("Z", "+00:00"))

    # Create event in database
    event = CalendarEvent(
        user_id=current_user.id,
        title=event_data.title,
        start=start_dt,
        end=end_dt,
        is_all_day=getattr(event_data, 'is_all_day', False),
        location=event_data.location,
        notes=event_data.description,
        calendar_name=event_data.calendar_name,
        source=getattr(event_data, 'source', 'web'),
        eventkit_id=getattr(event_data, 'eventkit_id', None),
    )

    db.add(event)
    await db.commit()
    await db.refresh(event)

    return CalendarEventResponse(
        id=str(event.id),
        title=event.title,
        start=event.start.isoformat(),
        end=event.end.isoformat(),
        is_all_day=event.is_all_day,
        location=event.location,
        notes=event.notes,
        attendees=[],
        calendar_color=event.calendar_color,
        calendar_name=event.calendar_name,
        recurrence_rule=event.recurrence_rule,
        is_protected=False,
        eventkit_id=event.eventkit_id,
    )


@router.get("/events/{event_id}", response_model=CalendarEventResponse)
async def get_event(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get a single calendar event by ID."""
    try:
        event_uuid = UUID(event_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    result = await db.execute(
        select(CalendarEvent).where(
            and_(
                CalendarEvent.id == event_uuid,
                CalendarEvent.user_id == current_user.id,
            )
        )
    )
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    return CalendarEventResponse(
        id=str(event.id),
        title=event.title,
        start=event.start.isoformat(),
        end=event.end.isoformat(),
        is_all_day=event.is_all_day,
        location=event.location,
        notes=event.notes,
        attendees=[],
        calendar_color=event.calendar_color,
        calendar_name=event.calendar_name,
        recurrence_rule=event.recurrence_rule,
        is_protected=False,
        eventkit_id=event.eventkit_id,
    )


@router.put("/events/{event_id}", response_model=CalendarEventResponse)
async def update_event(
    event_id: str,
    event_data: CalendarEventUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update a calendar event."""
    try:
        event_uuid = UUID(event_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    result = await db.execute(
        select(CalendarEvent).where(
            and_(
                CalendarEvent.id == event_uuid,
                CalendarEvent.user_id == current_user.id,
            )
        )
    )
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    # Update fields
    update_data = event_data.model_dump(exclude_unset=True)

    if "title" in update_data:
        event.title = update_data["title"]
    if "start" in update_data and update_data["start"]:
        event.start = datetime.fromisoformat(update_data["start"].replace("Z", "+00:00"))
    if "end" in update_data and update_data["end"]:
        event.end = datetime.fromisoformat(update_data["end"].replace("Z", "+00:00"))
    if "location" in update_data:
        event.location = update_data["location"]
    if "description" in update_data:
        event.notes = update_data["description"]
    if "is_all_day" in update_data:
        event.is_all_day = update_data["is_all_day"]
    if "eventkit_id" in update_data:
        event.eventkit_id = update_data["eventkit_id"]

    await db.commit()
    await db.refresh(event)

    return CalendarEventResponse(
        id=str(event.id),
        title=event.title,
        start=event.start.isoformat(),
        end=event.end.isoformat(),
        is_all_day=event.is_all_day,
        location=event.location,
        notes=event.notes,
        attendees=[],
        calendar_color=event.calendar_color,
        calendar_name=event.calendar_name,
        recurrence_rule=event.recurrence_rule,
        is_protected=False,
        eventkit_id=event.eventkit_id,
    )


@router.delete("/events/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_event(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete a calendar event."""
    try:
        event_uuid = UUID(event_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    result = await db.execute(
        select(CalendarEvent).where(
            and_(
                CalendarEvent.id == event_uuid,
                CalendarEvent.user_id == current_user.id,
            )
        )
    )
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    await db.delete(event)
    await db.commit()


@router.post("/events/sync", response_model=List[CalendarEventResponse])
async def sync_events(
    events: List[CalendarEventCreate],
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Sync events from iOS/Mac EventKit to the database.
    Used by mobile/desktop apps to push local calendar events to the server.
    Returns events that were created or updated.
    """
    synced_events = []

    for event_data in events:
        eventkit_id = getattr(event_data, 'eventkit_id', None)

        # Check if event already exists (by eventkit_id)
        existing = None
        if eventkit_id:
            result = await db.execute(
                select(CalendarEvent).where(
                    and_(
                        CalendarEvent.user_id == current_user.id,
                        CalendarEvent.eventkit_id == eventkit_id,
                    )
                )
            )
            existing = result.scalar_one_or_none()

        start_dt = datetime.fromisoformat(event_data.start.replace("Z", "+00:00"))
        end_dt = datetime.fromisoformat(event_data.end.replace("Z", "+00:00"))

        if existing:
            # Update existing event
            existing.title = event_data.title
            existing.start = start_dt
            existing.end = end_dt
            existing.is_all_day = getattr(event_data, 'is_all_day', False)
            existing.location = event_data.location
            existing.notes = event_data.description
            existing.calendar_name = event_data.calendar_name
            await db.commit()
            await db.refresh(existing)
            synced_events.append(existing)
        else:
            # Create new event
            event = CalendarEvent(
                user_id=current_user.id,
                title=event_data.title,
                start=start_dt,
                end=end_dt,
                is_all_day=getattr(event_data, 'is_all_day', False),
                location=event_data.location,
                notes=event_data.description,
                calendar_name=event_data.calendar_name,
                source=getattr(event_data, 'source', 'ios'),
                eventkit_id=eventkit_id,
            )
            db.add(event)
            await db.commit()
            await db.refresh(event)
            synced_events.append(event)

    return [
        CalendarEventResponse(
            id=str(event.id),
            title=event.title,
            start=event.start.isoformat(),
            end=event.end.isoformat(),
            is_all_day=event.is_all_day,
            location=event.location,
            notes=event.notes,
            attendees=[],
            calendar_color=event.calendar_color,
            calendar_name=event.calendar_name,
            recurrence_rule=event.recurrence_rule,
            is_protected=False,
            eventkit_id=event.eventkit_id,
        )
        for event in synced_events
    ]


@router.post("/optimize", response_model=OptimizationResponse)
async def optimize_schedule(
    request: OptimizationRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get schedule optimization suggestions."""
    # For now, return empty suggestions
    # TODO: Implement AI-powered schedule optimization
    return OptimizationResponse(
        suggestions=[],
        reasoning="Schedule optimization is being developed.",
        affected_events=[],
    )


@router.post("/optimize/apply", status_code=status.HTTP_200_OK)
async def apply_optimization(
    request: ApplyOptimizationRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Apply approved schedule changes."""
    # TODO: Implement when optimization is ready
    return {
        "applied": [],
        "errors": [],
        "message": "No changes applied",
    }
