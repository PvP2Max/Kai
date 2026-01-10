"""
Follow-ups endpoints.
"""
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime

from app.database import get_db
from app.models.user import User
from app.models.follow_up import FollowUp
from app.schemas.follow_up import (
    FollowUpCreate,
    FollowUpUpdate,
    FollowUpResponse,
    NudgeResponse,
)
from app.api.deps import get_current_user

router = APIRouter()


@router.get("", response_model=List[FollowUpResponse])
async def list_follow_ups(
    overdue_only: bool = False,
    status_filter: str = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List pending follow-ups."""
    query = select(FollowUp).where(FollowUp.user_id == current_user.id)

    if overdue_only:
        query = query.where(
            FollowUp.follow_up_date < datetime.utcnow(),
            FollowUp.status == "waiting",
        )

    if status_filter:
        query = query.where(FollowUp.status == status_filter)

    query = query.order_by(FollowUp.follow_up_date.asc())

    result = await db.execute(query)
    return result.scalars().all()


@router.post("", response_model=FollowUpResponse, status_code=status.HTTP_201_CREATED)
async def create_follow_up(
    follow_up_data: FollowUpCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a follow-up tracker."""
    follow_up = FollowUp(
        user_id=current_user.id,
        contact_name=follow_up_data.contact_name,
        contact_email=follow_up_data.contact_email,
        context=follow_up_data.context,
        follow_up_date=follow_up_data.follow_up_date,
        last_contact_date=follow_up_data.last_contact_date or datetime.utcnow(),
    )

    db.add(follow_up)
    await db.commit()
    await db.refresh(follow_up)

    return follow_up


@router.put("/{follow_up_id}", response_model=FollowUpResponse)
async def update_follow_up(
    follow_up_id: UUID,
    follow_up_data: FollowUpUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update a follow-up status."""
    result = await db.execute(
        select(FollowUp).where(
            FollowUp.id == follow_up_id,
            FollowUp.user_id == current_user.id,
        )
    )
    follow_up = result.scalar_one_or_none()

    if not follow_up:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Follow-up not found",
        )

    update_data = follow_up_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(follow_up, field, value)

    await db.commit()
    await db.refresh(follow_up)

    return follow_up


@router.post("/{follow_up_id}/nudge", response_model=NudgeResponse)
async def draft_nudge(
    follow_up_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Draft a polite follow-up nudge email."""
    result = await db.execute(
        select(FollowUp).where(
            FollowUp.id == follow_up_id,
            FollowUp.user_id == current_user.id,
        )
    )
    follow_up = result.scalar_one_or_none()

    if not follow_up:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Follow-up not found",
        )

    # Generate nudge email using Claude
    from app.core.chat import ChatHandler

    handler = ChatHandler(db, current_user.id)
    draft = await handler.generate_nudge_email(follow_up)

    return NudgeResponse(
        follow_up_id=follow_up.id,
        draft_email=draft["body"],
        subject=draft["subject"],
    )


@router.delete("/{follow_up_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_follow_up(
    follow_up_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete a follow-up."""
    result = await db.execute(
        select(FollowUp).where(
            FollowUp.id == follow_up_id,
            FollowUp.user_id == current_user.id,
        )
    )
    follow_up = result.scalar_one_or_none()

    if not follow_up:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Follow-up not found",
        )

    await db.delete(follow_up)
    await db.commit()
