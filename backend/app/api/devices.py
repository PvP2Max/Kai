"""
Device registration endpoints for push notifications.
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.preferences import DeviceToken
from app.api.deps import get_current_user

router = APIRouter()


class DeviceRegisterRequest:
    def __init__(self, token: str, device_name: str = None):
        self.token = token
        self.device_name = device_name


@router.post("/register")
async def register_device(
    token: str,
    device_name: str = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Register a device for push notifications."""
    # Check if token already exists
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.user_id == current_user.id,
            DeviceToken.token == token,
        )
    )
    existing = result.scalar_one_or_none()

    if existing:
        # Update device name if provided
        if device_name:
            existing.device_name = device_name
            await db.commit()
        return {"message": "Device already registered", "device_id": str(existing.id)}

    device = DeviceToken(
        user_id=current_user.id,
        token=token,
        device_name=device_name,
    )

    db.add(device)
    await db.commit()
    await db.refresh(device)

    return {"message": "Device registered", "device_id": str(device.id)}


@router.delete("/{token}")
async def unregister_device(
    token: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Unregister a device."""
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.user_id == current_user.id,
            DeviceToken.token == token,
        )
    )
    device = result.scalar_one_or_none()

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found",
        )

    await db.delete(device)
    await db.commit()

    return {"message": "Device unregistered"}


@router.get("")
async def list_devices(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List registered devices."""
    result = await db.execute(
        select(DeviceToken).where(DeviceToken.user_id == current_user.id)
    )
    devices = result.scalars().all()

    return {
        "devices": [
            {
                "id": str(d.id),
                "device_name": d.device_name,
                "created_at": d.created_at.isoformat(),
            }
            for d in devices
        ]
    }
