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
    # Validate file type - be lenient with MIME types as browsers vary
    allowed_types = [
        "audio/mpeg", "audio/mp3", "audio/mp4", "audio/m4a", "audio/x-m4a",
        "audio/wav", "audio/x-wav", "audio/wave", "audio/webm", "audio/ogg",
        "video/mp4", "video/webm",  # Some audio files get tagged as video
        "application/octet-stream",  # Generic binary
    ]
    allowed_extensions = [".mp3", ".m4a", ".mp4", ".wav", ".webm", ".ogg", ".aac"]

    filename = audio.filename or ""
    file_ext = os.path.splitext(filename.lower())[1]

    # Accept if MIME type matches OR file extension matches
    if audio.content_type not in allowed_types and file_ext not in allowed_extensions:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file type '{audio.content_type}' for file '{filename}'. Allowed extensions: {allowed_extensions}",
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

    # Process transcription
    try:
        from app.services.transcription import TranscriptionService

        service = TranscriptionService(db, current_user.id)
        result = await service.transcribe_meeting(
            meeting_id=meeting.id,
            audio_path=file_path,
        )

        if result.get("success"):
            await db.refresh(meeting)
            return MeetingUploadResponse(
                id=meeting.id,
                message="Meeting processed successfully",
                transcript=result.get("transcription"),
                summary=result.get("summary"),
            )
        else:
            return MeetingUploadResponse(
                id=meeting.id,
                message=f"Meeting uploaded but transcription failed: {result.get('error', 'Unknown error')}",
                transcript=None,
                summary=None,
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

        service = TranscriptionService(db, current_user.id)
        result = await service.generate_meeting_summary(meeting.id)

        if result.get("success"):
            await db.refresh(meeting)
            return meeting
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Error reprocessing meeting: {result.get('error', 'Unknown error')}",
            )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error reprocessing meeting: {str(e)}",
        )
