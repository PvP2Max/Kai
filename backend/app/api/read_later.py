"""
Read Later queue endpoints.
"""
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.read_later import ReadLater
from app.schemas.read_later import (
    ReadLaterCreate,
    ReadLaterUpdate,
    ReadLaterResponse,
)
from app.api.deps import get_current_user

router = APIRouter()


@router.get("", response_model=List[ReadLaterResponse])
async def list_read_later(
    unread_only: bool = True,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List read-later queue."""
    query = select(ReadLater).where(ReadLater.user_id == current_user.id)

    if unread_only:
        query = query.where(ReadLater.is_read == False)

    query = query.order_by(ReadLater.created_at.desc())

    result = await db.execute(query)
    return result.scalars().all()


@router.post("", response_model=ReadLaterResponse, status_code=status.HTTP_201_CREATED)
async def add_to_read_later(
    item_data: ReadLaterCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Add URL to read-later queue."""
    item = ReadLater(
        user_id=current_user.id,
        url=item_data.url,
        title=item_data.title,
    )

    db.add(item)
    await db.commit()
    await db.refresh(item)

    # Optionally fetch and summarize the content
    try:
        import httpx
        from app.core.chat import ChatHandler

        async with httpx.AsyncClient() as client:
            response = await client.get(item_data.url, follow_redirects=True, timeout=10)
            if response.status_code == 200:
                # Generate summary
                handler = ChatHandler(db, current_user.id)
                summary = await handler.summarize_url_content(response.text[:10000])
                item.summary = summary
                await db.commit()
                await db.refresh(item)
    except Exception:
        pass  # Summarization is optional

    return item


@router.put("/{item_id}", response_model=ReadLaterResponse)
async def update_read_later(
    item_id: UUID,
    item_data: ReadLaterUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update read-later item (mark as read)."""
    result = await db.execute(
        select(ReadLater).where(
            ReadLater.id == item_id,
            ReadLater.user_id == current_user.id,
        )
    )
    item = result.scalar_one_or_none()

    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Item not found",
        )

    update_data = item_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(item, field, value)

    await db.commit()
    await db.refresh(item)

    return item


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_read_later(
    item_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Remove item from read-later queue."""
    result = await db.execute(
        select(ReadLater).where(
            ReadLater.id == item_id,
            ReadLater.user_id == current_user.id,
        )
    )
    item = result.scalar_one_or_none()

    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Item not found",
        )

    await db.delete(item)
    await db.commit()
