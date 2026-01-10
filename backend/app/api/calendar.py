"""
Calendar endpoints for event management.
"""
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.calendar import (
    CalendarEventCreate,
    CalendarEventUpdate,
    CalendarEventResponse,
    OptimizationRequest,
    OptimizationResponse,
    ApplyOptimizationRequest,
)
from app.api.deps import get_current_user
from app.services.calendar import CalendarService
from app.config import settings

router = APIRouter()


def get_calendar_service() -> Optional[CalendarService]:
    """Get calendar service if configured."""
    if not all([settings.caldav_url, settings.caldav_username, settings.caldav_password]):
        return None
    return CalendarService(
        caldav_url=settings.caldav_url,
        username=settings.caldav_username,
        password=settings.caldav_password,
    )


@router.get("/events", response_model=List[CalendarEventResponse])
async def list_events(
    start: datetime = Query(..., description="Start date (ISO format)"),
    end: datetime = Query(..., description="End date (ISO format)"),
    calendar_name: Optional[str] = None,
    current_user: User = Depends(get_current_user),
):
    """List calendar events for a date range."""
    service = get_calendar_service()
    if not service:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Calendar service not configured",
        )

    try:
        events = service.get_events(start, end, calendar_name)
        return events
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error fetching calendar events: {str(e)}",
        )


@router.post("/events", response_model=CalendarEventResponse, status_code=status.HTTP_201_CREATED)
async def create_event(
    event_data: CalendarEventCreate,
    current_user: User = Depends(get_current_user),
):
    """Create a new calendar event."""
    service = get_calendar_service()
    if not service:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Calendar service not configured",
        )

    try:
        event = service.create_event(event_data)
        return event
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error creating calendar event: {str(e)}",
        )


@router.put("/events/{event_id}", response_model=CalendarEventResponse)
async def update_event(
    event_id: str,
    event_data: CalendarEventUpdate,
    current_user: User = Depends(get_current_user),
):
    """Update a calendar event."""
    service = get_calendar_service()
    if not service:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Calendar service not configured",
        )

    try:
        updates = event_data.model_dump(exclude_unset=True)
        event = service.update_event(event_id, updates)
        return event
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error updating calendar event: {str(e)}",
        )


@router.delete("/events/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_event(
    event_id: str,
    current_user: User = Depends(get_current_user),
):
    """Delete a calendar event."""
    service = get_calendar_service()
    if not service:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Calendar service not configured",
        )

    try:
        service.delete_event(event_id)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error deleting calendar event: {str(e)}",
        )


@router.post("/optimize", response_model=OptimizationResponse)
async def optimize_schedule(
    request: OptimizationRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get schedule optimization suggestions."""
    service = get_calendar_service()
    if not service:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Calendar service not configured",
        )

    # Import here to avoid circular dependency
    from app.services.optimizer import ScheduleOptimizer

    try:
        optimizer = ScheduleOptimizer(service, db, current_user.id)
        proposal = await optimizer.propose_optimization(
            start=request.date_range_start,
            end=request.date_range_end,
            protected_ids=request.protected_event_ids,
            goal=request.optimization_goal,
        )
        return proposal
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error optimizing schedule: {str(e)}",
        )


@router.post("/optimize/apply", status_code=status.HTTP_200_OK)
async def apply_optimization(
    request: ApplyOptimizationRequest,
    current_user: User = Depends(get_current_user),
):
    """Apply approved schedule changes."""
    service = get_calendar_service()
    if not service:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Calendar service not configured",
        )

    applied = []
    errors = []

    for change in request.approved_changes:
        try:
            if change.change_type == "move":
                service.update_event(
                    change.event_id,
                    {"start": change.new_start, "end": change.new_end},
                )
                applied.append(change.event_id)
            elif change.change_type == "remove":
                service.delete_event(change.event_id)
                applied.append(change.event_id)
        except Exception as e:
            errors.append({"event_id": change.event_id, "error": str(e)})

    return {
        "applied": applied,
        "errors": errors,
        "message": f"Applied {len(applied)} changes, {len(errors)} errors",
    }
