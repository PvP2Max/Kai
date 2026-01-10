"""
Activity log endpoints.
"""
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.activity import ActivityLog
from app.schemas.activity import ActivityLogResponse, UndoResponse
from app.api.deps import get_current_user

router = APIRouter()


@router.get("", response_model=List[ActivityLogResponse])
async def list_activity(
    limit: int = 50,
    offset: int = 0,
    action_type: Optional[str] = Query(None, alias="type"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List activity log (paginated)."""
    query = select(ActivityLog).where(ActivityLog.user_id == current_user.id)

    if action_type:
        query = query.where(ActivityLog.action_type == action_type)

    query = query.order_by(ActivityLog.created_at.desc()).offset(offset).limit(limit)

    result = await db.execute(query)
    return result.scalars().all()


@router.post("/{activity_id}/undo", response_model=UndoResponse)
async def undo_action(
    activity_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Undo a reversible action."""
    result = await db.execute(
        select(ActivityLog).where(
            ActivityLog.id == activity_id,
            ActivityLog.user_id == current_user.id,
        )
    )
    activity = result.scalar_one_or_none()

    if not activity:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Activity not found",
        )

    if not activity.reversible:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This action is not reversible",
        )

    if activity.reversed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This action has already been reversed",
        )

    # Perform undo based on action type
    try:
        from app.core.undo import perform_undo

        await perform_undo(activity, db)

        activity.reversed = True
        await db.commit()

        return UndoResponse(
            success=True,
            message=f"Successfully undid {activity.action_type}",
            activity_id=activity.id,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error undoing action: {str(e)}",
        )
