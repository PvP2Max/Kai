"""
Briefings endpoints for daily and weekly briefings.
"""
from datetime import datetime, date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.api.deps import get_current_user

router = APIRouter()


@router.get("/daily")
async def get_daily_briefing(
    briefing_date: date = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get today's briefing."""
    if briefing_date is None:
        briefing_date = date.today()

    from app.core.chat import ChatHandler

    handler = ChatHandler(db, current_user.id)
    briefing = await handler.generate_daily_briefing(briefing_date)

    return {
        "date": briefing_date.isoformat(),
        "briefing": briefing,
        "generated_at": datetime.utcnow().isoformat(),
    }


@router.get("/weekly")
async def get_weekly_review(
    week_start: date = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get weekly review."""
    if week_start is None:
        today = date.today()
        week_start = today - timedelta(days=today.weekday())

    from app.core.chat import ChatHandler
    from datetime import timedelta

    handler = ChatHandler(db, current_user.id)
    review = await handler.generate_weekly_review(week_start)

    return {
        "week_start": week_start.isoformat(),
        "week_end": (week_start + timedelta(days=6)).isoformat(),
        "review": review,
        "generated_at": datetime.utcnow().isoformat(),
    }


@router.post("/daily/send")
async def send_daily_briefing(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Trigger daily briefing push notification."""
    from app.core.chat import ChatHandler
    from app.services.notifications import PushNotificationService
    from app.config import settings

    handler = ChatHandler(db, current_user.id)
    briefing = await handler.generate_daily_briefing(date.today())

    # Send push notification if configured
    if settings.apns_cert_path and settings.apns_bundle_id:
        notification_service = PushNotificationService(
            cert_path=settings.apns_cert_path,
            bundle_id=settings.apns_bundle_id,
        )

        await notification_service.send_notification(
            user_id=str(current_user.id),
            title="Good morning! Here's your daily briefing",
            body=briefing.get("summary", "Your day at a glance"),
            category="briefing",
            db=db,
        )

        return {"message": "Daily briefing sent", "pushed": True}

    return {"message": "Daily briefing generated (push not configured)", "pushed": False}
