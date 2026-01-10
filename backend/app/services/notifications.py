"""
Push notification service using Apple Push Notification Service (APNs).
"""
import json
from typing import Optional, Dict, Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.preferences import DeviceToken


class PushNotificationService:
    """
    Apple Push Notification Service integration.
    Sends notifications to iOS devices and Apple Watch.
    """

    def __init__(
        self,
        cert_path: str,
        bundle_id: str,
        use_sandbox: bool = False,
    ):
        self.cert_path = cert_path
        self.bundle_id = bundle_id
        self.use_sandbox = use_sandbox
        self._client = None

    async def _get_client(self):
        """Get or create APNs client."""
        if self._client is None:
            try:
                from apns2.client import APNsClient
                from apns2.credentials import TokenCredentials

                # Use token-based authentication (recommended)
                self._client = APNsClient(
                    credentials=self.cert_path,
                    use_sandbox=self.use_sandbox,
                )
            except ImportError:
                # Fallback to simpler implementation
                self._client = "mock"

        return self._client

    async def send_notification(
        self,
        user_id: str,
        title: str,
        body: str,
        category: str = "info",
        data: Optional[Dict[str, Any]] = None,
        db: Optional[AsyncSession] = None,
    ) -> Dict[str, Any]:
        """
        Send a push notification to all user devices.

        Args:
            user_id: User ID to send notification to
            title: Notification title
            body: Notification body text
            category: Notification category (reminder, briefing, alert, info)
            data: Optional custom data payload
            db: Database session for fetching device tokens

        Returns:
            Send result with success count
        """
        if not db:
            return {"error": "Database session required", "success": False}

        # Get user's device tokens
        result = await db.execute(
            select(DeviceToken).where(DeviceToken.user_id == user_id)
        )
        devices = result.scalars().all()

        if not devices:
            return {
                "success": False,
                "error": "No registered devices",
                "sent": 0,
            }

        client = await self._get_client()

        if client == "mock":
            # Mock mode for testing
            return {
                "success": True,
                "sent": len(devices),
                "mock": True,
            }

        sent = 0
        failed = 0
        errors = []

        for device in devices:
            try:
                from apns2.payload import Payload, PayloadAlert

                alert = PayloadAlert(title=title, body=body)
                payload = Payload(
                    alert=alert,
                    category=category,
                    custom=data or {},
                    sound="default",
                )

                client.send_notification(
                    device.token,
                    payload,
                    self.bundle_id,
                )
                sent += 1

            except Exception as e:
                failed += 1
                errors.append({
                    "device": device.device_name or "Unknown",
                    "error": str(e),
                })

        return {
            "success": sent > 0,
            "sent": sent,
            "failed": failed,
            "errors": errors if errors else None,
        }

    async def send_silent_notification(
        self,
        user_id: str,
        data: Dict[str, Any],
        db: Optional[AsyncSession] = None,
    ) -> Dict[str, Any]:
        """
        Send a silent push notification for background updates.

        Args:
            user_id: User ID
            data: Data payload
            db: Database session

        Returns:
            Send result
        """
        if not db:
            return {"error": "Database session required", "success": False}

        result = await db.execute(
            select(DeviceToken).where(DeviceToken.user_id == user_id)
        )
        devices = result.scalars().all()

        if not devices:
            return {"success": False, "error": "No registered devices"}

        client = await self._get_client()

        if client == "mock":
            return {"success": True, "sent": len(devices), "mock": True}

        sent = 0

        for device in devices:
            try:
                from apns2.payload import Payload

                payload = Payload(
                    content_available=True,
                    custom=data,
                )

                client.send_notification(
                    device.token,
                    payload,
                    self.bundle_id,
                )
                sent += 1

            except Exception:
                continue

        return {"success": sent > 0, "sent": sent}

    async def register_device(
        self,
        user_id: str,
        token: str,
        device_name: Optional[str] = None,
        db: Optional[AsyncSession] = None,
    ) -> Dict[str, Any]:
        """
        Register a device for push notifications.

        Args:
            user_id: User ID
            token: Device token from APNs
            device_name: Optional device name
            db: Database session

        Returns:
            Registration result
        """
        if not db:
            return {"error": "Database session required", "success": False}

        # Check if token already exists
        result = await db.execute(
            select(DeviceToken).where(
                DeviceToken.user_id == user_id,
                DeviceToken.token == token,
            )
        )
        existing = result.scalar_one_or_none()

        if existing:
            if device_name:
                existing.device_name = device_name
                await db.commit()
            return {"success": True, "device_id": str(existing.id), "existing": True}

        device = DeviceToken(
            user_id=user_id,
            token=token,
            device_name=device_name,
        )
        db.add(device)
        await db.commit()
        await db.refresh(device)

        return {"success": True, "device_id": str(device.id), "existing": False}

    async def unregister_device(
        self,
        user_id: str,
        token: str,
        db: Optional[AsyncSession] = None,
    ) -> Dict[str, Any]:
        """
        Unregister a device.

        Args:
            user_id: User ID
            token: Device token
            db: Database session

        Returns:
            Unregistration result
        """
        if not db:
            return {"error": "Database session required", "success": False}

        result = await db.execute(
            select(DeviceToken).where(
                DeviceToken.user_id == user_id,
                DeviceToken.token == token,
            )
        )
        device = result.scalar_one_or_none()

        if not device:
            return {"success": False, "error": "Device not found"}

        await db.delete(device)
        await db.commit()

        return {"success": True}
