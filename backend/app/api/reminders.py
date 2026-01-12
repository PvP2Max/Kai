"""
Reminders endpoints for syncing Apple Reminders from iOS.
"""
from typing import List, Optional
from datetime import datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_

from app.database import get_db
from app.models.user import User
from app.models.synced_reminder import SyncedReminder
from app.models.project import Project
from app.schemas.reminder import (
    ReminderSyncRequest,
    ReminderSyncResponse,
    ReminderResponse,
    ReminderListResponse,
)
from app.api.deps import get_current_user

router = APIRouter()


def to_naive_utc(dt: Optional[datetime]) -> Optional[datetime]:
    """
    Convert a datetime to timezone-naive UTC.
    PostgreSQL TIMESTAMP WITHOUT TIME ZONE expects naive datetimes.
    """
    if dt is None:
        return None
    if dt.tzinfo is not None:
        # Convert to UTC and strip timezone info
        from datetime import timezone
        utc_dt = dt.astimezone(timezone.utc)
        return utc_dt.replace(tzinfo=None)
    return dt


@router.post("/sync", response_model=ReminderSyncResponse)
async def sync_reminders(
    sync_data: ReminderSyncRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Sync reminders from iOS Apple Reminders.
    Creates new reminders, updates existing ones, and marks missing ones as completed.
    """
    created_count = 0
    updated_count = 0

    # Get all existing apple_reminder_ids for this user
    existing_result = await db.execute(
        select(SyncedReminder.apple_reminder_id, SyncedReminder.id).where(
            SyncedReminder.user_id == current_user.id
        )
    )
    existing_map = {row[0]: row[1] for row in existing_result.all()}

    incoming_ids = {r.apple_reminder_id for r in sync_data.reminders}

    for reminder_data in sync_data.reminders:
        # Try to match reminder to a project based on list name or tags
        project_id = await _match_project(
            db, current_user.id, reminder_data.list_name, reminder_data.tags
        )

        if reminder_data.apple_reminder_id in existing_map:
            # Update existing reminder
            result = await db.execute(
                select(SyncedReminder).where(
                    SyncedReminder.id == existing_map[reminder_data.apple_reminder_id]
                )
            )
            reminder = result.scalar_one()

            reminder.title = reminder_data.title
            reminder.notes = reminder_data.notes
            reminder.due_date = to_naive_utc(reminder_data.due_date)
            reminder.priority = reminder_data.priority
            reminder.is_completed = reminder_data.is_completed
            reminder.completed_at = to_naive_utc(reminder_data.completed_at)
            reminder.list_name = reminder_data.list_name
            reminder.tags = reminder_data.tags
            reminder.project_id = project_id
            reminder.synced_at = datetime.utcnow()

            updated_count += 1
        else:
            # Create new reminder
            reminder = SyncedReminder(
                user_id=current_user.id,
                apple_reminder_id=reminder_data.apple_reminder_id,
                title=reminder_data.title,
                notes=reminder_data.notes,
                due_date=to_naive_utc(reminder_data.due_date),
                priority=reminder_data.priority,
                is_completed=reminder_data.is_completed,
                completed_at=to_naive_utc(reminder_data.completed_at),
                list_name=reminder_data.list_name,
                tags=reminder_data.tags,
                project_id=project_id,
                synced_at=datetime.utcnow(),
            )
            db.add(reminder)
            created_count += 1

    # Mark reminders not in incoming list as completed (if they weren't already)
    deleted_count = 0
    for apple_id, db_id in existing_map.items():
        if apple_id not in incoming_ids:
            result = await db.execute(
                select(SyncedReminder).where(SyncedReminder.id == db_id)
            )
            reminder = result.scalar_one_or_none()
            if reminder and not reminder.is_completed:
                reminder.is_completed = True
                reminder.completed_at = datetime.utcnow()
                deleted_count += 1

    await db.commit()

    return ReminderSyncResponse(
        synced_count=len(sync_data.reminders),
        created_count=created_count,
        updated_count=updated_count,
        deleted_count=deleted_count,
    )


@router.get("", response_model=ReminderListResponse)
async def list_reminders(
    include_completed: bool = Query(False, description="Include completed reminders"),
    project_id: Optional[UUID] = Query(None, description="Filter by project"),
    list_name: Optional[str] = Query(None, description="Filter by Apple Reminders list"),
    due_before: Optional[datetime] = Query(None, description="Filter by due date"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List synced reminders with optional filters."""
    query = select(SyncedReminder).where(SyncedReminder.user_id == current_user.id)

    if not include_completed:
        query = query.where(SyncedReminder.is_completed == False)

    if project_id:
        query = query.where(SyncedReminder.project_id == project_id)

    if list_name:
        query = query.where(SyncedReminder.list_name == list_name)

    if due_before:
        query = query.where(SyncedReminder.due_date <= due_before)

    query = query.order_by(SyncedReminder.due_date.asc().nullslast())

    result = await db.execute(query)
    reminders = result.scalars().all()

    # Calculate counts
    now = datetime.utcnow()
    today_end = now.replace(hour=23, minute=59, second=59)

    due_today = sum(
        1
        for r in reminders
        if r.due_date and r.due_date <= today_end and not r.is_completed
    )
    overdue = sum(
        1 for r in reminders if r.due_date and r.due_date < now and not r.is_completed
    )

    return ReminderListResponse(
        reminders=reminders,
        total=len(reminders),
        due_today=due_today,
        overdue=overdue,
    )


@router.get("/due-today", response_model=List[ReminderResponse])
async def get_reminders_due_today(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get all incomplete reminders due today."""
    now = datetime.utcnow()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_end = now.replace(hour=23, minute=59, second=59, microsecond=999999)

    result = await db.execute(
        select(SyncedReminder)
        .where(
            SyncedReminder.user_id == current_user.id,
            SyncedReminder.is_completed == False,
            or_(
                and_(
                    SyncedReminder.due_date >= today_start,
                    SyncedReminder.due_date <= today_end,
                ),
                SyncedReminder.due_date < today_start,  # Include overdue
            ),
        )
        .order_by(SyncedReminder.due_date.asc().nullslast())
    )

    return result.scalars().all()


@router.get("/by-project", response_model=dict)
async def get_reminders_by_project(
    include_completed: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get reminders grouped by project for briefings."""
    query = select(SyncedReminder).where(SyncedReminder.user_id == current_user.id)

    if not include_completed:
        query = query.where(SyncedReminder.is_completed == False)

    result = await db.execute(query)
    reminders = result.scalars().all()

    # Get project names
    project_ids = {r.project_id for r in reminders if r.project_id}
    project_result = await db.execute(
        select(Project).where(Project.id.in_(project_ids))
    )
    projects = {p.id: p.name for p in project_result.scalars().all()}

    # Group by project
    grouped = {"General": []}
    for reminder in reminders:
        if reminder.project_id and reminder.project_id in projects:
            project_name = projects[reminder.project_id]
            if project_name not in grouped:
                grouped[project_name] = []
            grouped[project_name].append(
                {
                    "id": str(reminder.id),
                    "title": reminder.title,
                    "due_date": reminder.due_date.isoformat() if reminder.due_date else None,
                    "priority": reminder.priority,
                    "list_name": reminder.list_name,
                }
            )
        else:
            grouped["General"].append(
                {
                    "id": str(reminder.id),
                    "title": reminder.title,
                    "due_date": reminder.due_date.isoformat() if reminder.due_date else None,
                    "priority": reminder.priority,
                    "list_name": reminder.list_name,
                }
            )

    # Remove empty General if no items
    if not grouped["General"]:
        del grouped["General"]

    return grouped


@router.put("/{reminder_id}/complete", response_model=ReminderResponse)
async def complete_reminder(
    reminder_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Mark a reminder as completed."""
    result = await db.execute(
        select(SyncedReminder).where(
            SyncedReminder.id == reminder_id,
            SyncedReminder.user_id == current_user.id,
        )
    )
    reminder = result.scalar_one_or_none()

    if not reminder:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Reminder not found",
        )

    reminder.is_completed = True
    reminder.completed_at = datetime.utcnow()

    await db.commit()
    await db.refresh(reminder)

    return reminder


@router.put("/{reminder_id}/project", response_model=ReminderResponse)
async def assign_reminder_to_project(
    reminder_id: UUID,
    project_id: Optional[UUID] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Assign a reminder to a project."""
    result = await db.execute(
        select(SyncedReminder).where(
            SyncedReminder.id == reminder_id,
            SyncedReminder.user_id == current_user.id,
        )
    )
    reminder = result.scalar_one_or_none()

    if not reminder:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Reminder not found",
        )

    if project_id:
        # Verify project exists and belongs to user
        project_result = await db.execute(
            select(Project).where(
                Project.id == project_id,
                Project.user_id == current_user.id,
            )
        )
        if not project_result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Project not found",
            )

    reminder.project_id = project_id

    await db.commit()
    await db.refresh(reminder)

    return reminder


async def _match_project(
    db: AsyncSession,
    user_id: UUID,
    list_name: Optional[str],
    tags: Optional[List[str]],
) -> Optional[UUID]:
    """
    Try to match a reminder to a project based on list name or tags.
    Returns the project_id if found, None otherwise.
    """
    if not list_name and not tags:
        return None

    # Try exact match on project name with list name
    if list_name:
        result = await db.execute(
            select(Project).where(
                Project.user_id == user_id,
                func.lower(Project.name) == func.lower(list_name),
            )
        )
        project = result.scalar_one_or_none()
        if project:
            return project.id

    # Try matching tags to project names
    if tags:
        for tag in tags:
            result = await db.execute(
                select(Project).where(
                    Project.user_id == user_id,
                    func.lower(Project.name) == func.lower(tag),
                )
            )
            project = result.scalar_one_or_none()
            if project:
                return project.id

    return None
