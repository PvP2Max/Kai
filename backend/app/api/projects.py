"""
Projects endpoints.
"""
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.user import User
from app.models.project import Project
from app.models.note import Note
from app.models.meeting import Meeting
from app.schemas.project import (
    ProjectCreate,
    ProjectUpdate,
    ProjectResponse,
    ProjectDetailResponse,
    ProjectStatusResponse,
)
from app.api.deps import get_current_user

router = APIRouter()


@router.get("", response_model=List[ProjectResponse])
async def list_projects(
    status_filter: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all projects."""
    query = select(
        Project,
        func.count(Note.id.distinct()).label("note_count"),
        func.count(Meeting.id.distinct()).label("meeting_count"),
    ).outerjoin(Note).outerjoin(Meeting).where(Project.user_id == current_user.id)

    if status_filter:
        query = query.where(Project.status == status_filter)

    query = query.group_by(Project.id).order_by(Project.updated_at.desc())

    result = await db.execute(query)
    projects = []
    for row in result.all():
        project = row[0]
        projects.append(
            ProjectResponse(
                id=project.id,
                name=project.name,
                description=project.description,
                status=project.status,
                created_at=project.created_at,
                updated_at=project.updated_at,
                note_count=row[1],
                meeting_count=row[2],
            )
        )

    return projects


@router.post("", response_model=ProjectResponse, status_code=status.HTTP_201_CREATED)
async def create_project(
    project_data: ProjectCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a new project."""
    project = Project(
        user_id=current_user.id,
        name=project_data.name,
        description=project_data.description,
    )

    db.add(project)
    await db.commit()
    await db.refresh(project)

    return ProjectResponse(
        id=project.id,
        name=project.name,
        description=project.description,
        status=project.status,
        created_at=project.created_at,
        updated_at=project.updated_at,
        note_count=0,
        meeting_count=0,
    )


@router.get("/{project_id}", response_model=ProjectDetailResponse)
async def get_project(
    project_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get a project with all related items."""
    result = await db.execute(
        select(Project)
        .options(selectinload(Project.notes), selectinload(Project.meetings))
        .where(
            Project.id == project_id,
            Project.user_id == current_user.id,
        )
    )
    project = result.scalar_one_or_none()

    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found",
        )

    return ProjectDetailResponse(
        id=project.id,
        name=project.name,
        description=project.description,
        status=project.status,
        created_at=project.created_at,
        updated_at=project.updated_at,
        note_count=len(project.notes),
        meeting_count=len(project.meetings),
        notes=[
            {"id": str(n.id), "title": n.title, "created_at": n.created_at.isoformat()}
            for n in project.notes
        ],
        meetings=[
            {"id": str(m.id), "title": m.event_title, "date": m.event_start.isoformat() if m.event_start else None}
            for m in project.meetings
        ],
    )


@router.put("/{project_id}", response_model=ProjectResponse)
async def update_project(
    project_id: UUID,
    project_data: ProjectUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update a project."""
    result = await db.execute(
        select(Project).where(
            Project.id == project_id,
            Project.user_id == current_user.id,
        )
    )
    project = result.scalar_one_or_none()

    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found",
        )

    update_data = project_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(project, field, value)

    await db.commit()
    await db.refresh(project)

    return project


@router.get("/{project_id}/status", response_model=ProjectStatusResponse)
async def get_project_status(
    project_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get AI-generated project status summary."""
    result = await db.execute(
        select(Project)
        .options(selectinload(Project.notes), selectinload(Project.meetings))
        .where(
            Project.id == project_id,
            Project.user_id == current_user.id,
        )
    )
    project = result.scalar_one_or_none()

    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found",
        )

    # Generate AI summary
    from app.core.chat import ChatHandler

    handler = ChatHandler(db, current_user.id)
    summary = await handler.generate_project_summary(project)

    return ProjectStatusResponse(
        project=ProjectResponse(
            id=project.id,
            name=project.name,
            description=project.description,
            status=project.status,
            created_at=project.created_at,
            updated_at=project.updated_at,
            note_count=len(project.notes),
            meeting_count=len(project.meetings),
        ),
        summary=summary,
        recent_activity=[],
        pending_action_items=[],
        upcoming_meetings=[],
    )
