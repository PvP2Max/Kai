"""
Preferences and locations endpoints.
"""
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.preferences import Preference, Location
from app.schemas.preferences import (
    PreferenceResponse,
    PreferenceUpdate,
    PreferencesResponse,
    LocationCreate,
    LocationResponse,
)
from app.api.deps import get_current_user

router = APIRouter()


@router.get("", response_model=PreferencesResponse)
async def get_preferences(
    category: str = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get all preferences."""
    query = select(Preference).where(Preference.user_id == current_user.id)

    if category and category != "all":
        query = query.where(Preference.category == category)

    result = await db.execute(query)
    preferences = result.scalars().all()

    # Group by category
    by_category = {}
    for pref in preferences:
        if pref.category not in by_category:
            by_category[pref.category] = []
        by_category[pref.category].append(pref)

    return PreferencesResponse(
        preferences=preferences,
        by_category=by_category,
    )


@router.put("")
async def update_preferences(
    pref_data: PreferenceUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update or create a preference."""
    result = await db.execute(
        select(Preference).where(
            Preference.user_id == current_user.id,
            Preference.category == pref_data.category,
            Preference.key == pref_data.key,
        )
    )
    pref = result.scalar_one_or_none()

    if pref:
        pref.value = pref_data.value
        pref.learned = pref_data.learned
    else:
        pref = Preference(
            user_id=current_user.id,
            category=pref_data.category,
            key=pref_data.key,
            value=pref_data.value,
            learned=pref_data.learned,
        )
        db.add(pref)

    await db.commit()
    await db.refresh(pref)

    return pref


@router.get("/locations", response_model=List[LocationResponse])
async def get_locations(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get saved locations."""
    result = await db.execute(
        select(Location).where(Location.user_id == current_user.id)
    )
    return result.scalars().all()


@router.post("/locations", response_model=LocationResponse, status_code=status.HTTP_201_CREATED)
async def create_location(
    location_data: LocationCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Add a saved location."""
    location = Location(
        user_id=current_user.id,
        name=location_data.name,
        address=location_data.address,
        latitude=location_data.latitude,
        longitude=location_data.longitude,
    )

    db.add(location)
    await db.commit()
    await db.refresh(location)

    return location


@router.delete("/locations/{location_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_location(
    location_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Remove a saved location."""
    result = await db.execute(
        select(Location).where(
            Location.id == location_id,
            Location.user_id == current_user.id,
        )
    )
    location = result.scalar_one_or_none()

    if not location:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Location not found",
        )

    await db.delete(location)
    await db.commit()
