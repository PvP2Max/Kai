"""
Meetings endpoints for meeting management and transcription.
"""
from typing import List, Optional
from uuid import UUID
import os
import aiofiles

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.user import User
from app.models.meeting import Meeting, ActionItem
from app.schemas.meeting import MeetingResponse, MeetingUploadResponse
from app.api.deps import get_current_user
from app.config import settings

router = APIRouter()


@router.get("", response_model=List[MeetingResponse])
async def list_meetings(
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all meetings with summaries."""
    result = await db.execute(
        select(Meeting)
        .options(selectinload(Meeting.action_items))
        .where(Meeting.user_id == current_user.id)
        .order_by(Meeting.event_start.desc())
        .offset(offset)
        .limit(limit)
    )
    return result.scalars().all()


@router.post("/upload", response_model=MeetingUploadResponse)
async def upload_meeting(
    audio: UploadFile = File(...),
    calendar_event_id: Optional[str] = Form(None),
    event_title: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Upload audio for transcription and summary generation."""
    # Validate file type
    allowed_types = ["audio/mpeg", "audio/mp4", "audio/m4a", "audio/wav", "audio/x-wav"]
    if audio.content_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file type. Allowed: {allowed_types}",
        )

    # Save audio file
    os.makedirs(settings.audio_upload_dir, exist_ok=True)
    filename = f"{current_user.id}_{audio.filename}"
    file_path = os.path.join(settings.audio_upload_dir, filename)

    async with aiofiles.open(file_path, "wb") as f:
        content = await audio.read()
        await f.write(content)

    # Create meeting record
    meeting = Meeting(
        user_id=current_user.id,
        calendar_event_id=calendar_event_id,
        event_title=event_title,
        audio_file_path=file_path,
    )
    db.add(meeting)
    await db.commit()
    await db.refresh(meeting)

    # Process transcription asynchronously
    try:
        from app.services.transcription import TranscriptionService

        service = TranscriptionService()
        result = await service.transcribe_and_summarize(
            audio_path=file_path,
            event_context={
                "title": event_title,
                "calendar_event_id": calendar_event_id,
            },
        )

        # Update meeting with transcript and summary
        meeting.transcript = result.transcript
        meeting.summary = result.summary.model_dump() if result.summary else None

        # Create action items
        if result.summary and result.summary.action_items:
            for item in result.summary.action_items:
                action_item = ActionItem(
                    meeting_id=meeting.id,
                    user_id=current_user.id,
                    description=item.get("description", ""),
                    owner=item.get("owner"),
                    due_date=item.get("due_date"),
                    priority=item.get("priority", "medium"),
                )
                db.add(action_item)

        await db.commit()
        await db.refresh(meeting)

        return MeetingUploadResponse(
            id=meeting.id,
            message="Meeting processed successfully",
            transcript=meeting.transcript,
            summary=result.summary,
        )
    except Exception as e:
        return MeetingUploadResponse(
            id=meeting.id,
            message=f"Meeting uploaded but transcription failed: {str(e)}",
            transcript=None,
            summary=None,
        )


@router.get("/{meeting_id}", response_model=MeetingResponse)
async def get_meeting(
    meeting_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get a specific meeting with details and summary."""
    result = await db.execute(
        select(Meeting)
        .options(selectinload(Meeting.action_items))
        .where(
            Meeting.id == meeting_id,
            Meeting.user_id == current_user.id,
        )
    )
    meeting = result.scalar_one_or_none()

    if not meeting:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Meeting not found",
        )

    return meeting


@router.post("/{meeting_id}/reprocess", response_model=MeetingResponse)
async def reprocess_meeting(
    meeting_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Re-generate summary for a meeting."""
    result = await db.execute(
        select(Meeting).where(
            Meeting.id == meeting_id,
            Meeting.user_id == current_user.id,
        )
    )
    meeting = result.scalar_one_or_none()

    if not meeting:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Meeting not found",
        )

    if not meeting.transcript:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Meeting has no transcript to summarize",
        )

    try:
        from app.services.transcription import TranscriptionService

        service = TranscriptionService()
        summary = await service.generate_summary(
            transcript=meeting.transcript,
            event_context={
                "title": meeting.event_title,
                "calendar_event_id": meeting.calendar_event_id,
            },
        )

        meeting.summary = summary.model_dump()
        await db.commit()
        await db.refresh(meeting)

        return meeting
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error reprocessing meeting: {str(e)}",
        )
