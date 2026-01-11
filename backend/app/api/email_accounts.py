"""API endpoints for email account management."""

from datetime import time, datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.api.auth import get_current_user
from app.models.user import User
from app.models.email_account import EmailAccount, EmailBriefingConfig
from app.schemas.email_account import (
    EmailAccountCreate,
    EmailAccountUpdate,
    EmailAccountResponse,
    EmailAccountListResponse,
    EmailBriefingConfigUpdate,
    EmailBriefingConfigResponse,
    OAuthStartResponse,
    OAuthCallbackRequest,
    OAuthCallbackResponse,
)

router = APIRouter(prefix="/email-accounts", tags=["email-accounts"])


def parse_time(time_str: Optional[str]) -> Optional[time]:
    """Parse HH:MM string to time object."""
    if not time_str:
        return None
    try:
        parts = time_str.split(":")
        return time(int(parts[0]), int(parts[1]))
    except (ValueError, IndexError):
        return None


# Email Account Endpoints

@router.get("", response_model=EmailAccountListResponse)
async def list_email_accounts(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all email accounts for the current user."""
    result = await db.execute(
        select(EmailAccount)
        .where(EmailAccount.user_id == current_user.id)
        .order_by(EmailAccount.priority, EmailAccount.created_at)
    )
    accounts = result.scalars().all()

    return EmailAccountListResponse(
        accounts=[EmailAccountResponse.model_validate(a) for a in accounts],
        count=len(accounts),
    )


@router.get("/{account_id}", response_model=EmailAccountResponse)
async def get_email_account(
    account_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get a specific email account."""
    result = await db.execute(
        select(EmailAccount).where(
            EmailAccount.id == account_id,
            EmailAccount.user_id == current_user.id,
        )
    )
    account = result.scalar_one_or_none()

    if not account:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Email account not found",
        )

    return EmailAccountResponse.model_validate(account)


@router.post("", response_model=EmailAccountResponse, status_code=status.HTTP_201_CREATED)
async def create_email_account(
    account_data: EmailAccountCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a new email account (manual or after OAuth)."""
    # Check for duplicate email
    existing = await db.execute(
        select(EmailAccount).where(
            EmailAccount.user_id == current_user.id,
            EmailAccount.email_address == account_data.email_address,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email account already exists",
        )

    account = EmailAccount(
        user_id=current_user.id,
        provider=account_data.provider,
        email_address=account_data.email_address,
        display_name=account_data.display_name,
        access_token=account_data.access_token,
        refresh_token=account_data.refresh_token,
        imap_host=account_data.imap_host,
        imap_port=account_data.imap_port,
        imap_username=account_data.imap_username,
        imap_password=account_data.imap_password,
        briefing_days=["all"],
        categories_to_include=["all"],
    )
    db.add(account)
    await db.commit()
    await db.refresh(account)

    return EmailAccountResponse.model_validate(account)


@router.put("/{account_id}", response_model=EmailAccountResponse)
async def update_email_account(
    account_id: UUID,
    account_data: EmailAccountUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update an email account."""
    result = await db.execute(
        select(EmailAccount).where(
            EmailAccount.id == account_id,
            EmailAccount.user_id == current_user.id,
        )
    )
    account = result.scalar_one_or_none()

    if not account:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Email account not found",
        )

    # Update fields
    if account_data.display_name is not None:
        account.display_name = account_data.display_name
    if account_data.include_in_briefing is not None:
        account.include_in_briefing = account_data.include_in_briefing
    if account_data.briefing_days is not None:
        account.briefing_days = account_data.briefing_days
    if account_data.briefing_start_time is not None:
        account.briefing_start_time = parse_time(account_data.briefing_start_time)
    if account_data.briefing_end_time is not None:
        account.briefing_end_time = parse_time(account_data.briefing_end_time)
    if account_data.priority is not None:
        account.priority = account_data.priority
    if account_data.max_emails_in_briefing is not None:
        account.max_emails_in_briefing = account_data.max_emails_in_briefing
    if account_data.categories_to_include is not None:
        account.categories_to_include = account_data.categories_to_include
    if account_data.is_active is not None:
        account.is_active = account_data.is_active

    account.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(account)

    return EmailAccountResponse.model_validate(account)


@router.delete("/{account_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_email_account(
    account_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete an email account."""
    result = await db.execute(
        select(EmailAccount).where(
            EmailAccount.id == account_id,
            EmailAccount.user_id == current_user.id,
        )
    )
    account = result.scalar_one_or_none()

    if not account:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Email account not found",
        )

    await db.delete(account)
    await db.commit()


# Briefing Config Endpoints

@router.get("/briefing/config", response_model=EmailBriefingConfigResponse)
async def get_briefing_config(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get email briefing configuration."""
    result = await db.execute(
        select(EmailBriefingConfig).where(
            EmailBriefingConfig.user_id == current_user.id
        )
    )
    config = result.scalar_one_or_none()

    if not config:
        # Create default config
        config = EmailBriefingConfig(
            user_id=current_user.id,
            briefing_enabled=True,
        )
        db.add(config)
        await db.commit()
        await db.refresh(config)

    return EmailBriefingConfigResponse.model_validate(config)


@router.put("/briefing/config", response_model=EmailBriefingConfigResponse)
async def update_briefing_config(
    config_data: EmailBriefingConfigUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update email briefing configuration."""
    result = await db.execute(
        select(EmailBriefingConfig).where(
            EmailBriefingConfig.user_id == current_user.id
        )
    )
    config = result.scalar_one_or_none()

    if not config:
        config = EmailBriefingConfig(user_id=current_user.id)
        db.add(config)

    # Update fields
    if config_data.briefing_enabled is not None:
        config.briefing_enabled = config_data.briefing_enabled
    if config_data.morning_briefing_time is not None:
        config.morning_briefing_time = parse_time(config_data.morning_briefing_time)
    if config_data.weekday_accounts is not None:
        config.weekday_accounts = config_data.weekday_accounts
    if config_data.weekend_accounts is not None:
        config.weekend_accounts = config_data.weekend_accounts
    if config_data.monday_accounts is not None:
        config.monday_accounts = config_data.monday_accounts
    if config_data.tuesday_accounts is not None:
        config.tuesday_accounts = config_data.tuesday_accounts
    if config_data.wednesday_accounts is not None:
        config.wednesday_accounts = config_data.wednesday_accounts
    if config_data.thursday_accounts is not None:
        config.thursday_accounts = config_data.thursday_accounts
    if config_data.friday_accounts is not None:
        config.friday_accounts = config_data.friday_accounts
    if config_data.saturday_accounts is not None:
        config.saturday_accounts = config_data.saturday_accounts
    if config_data.sunday_accounts is not None:
        config.sunday_accounts = config_data.sunday_accounts
    if config_data.skip_days is not None:
        config.skip_days = config_data.skip_days

    config.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(config)

    return EmailBriefingConfigResponse.model_validate(config)


# OAuth Endpoints

@router.get("/oauth/{provider}/start", response_model=OAuthStartResponse)
async def start_oauth(
    provider: str,
    current_user: User = Depends(get_current_user),
):
    """Start OAuth flow for an email provider."""
    import secrets
    from app.config import settings

    state = secrets.token_urlsafe(32)

    if provider == "gmail":
        # Gmail OAuth
        from urllib.parse import urlencode

        params = {
            "client_id": settings.google_client_id,
            "redirect_uri": f"{settings.frontend_url}/settings/email/callback",
            "response_type": "code",
            "scope": "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.compose",
            "access_type": "offline",
            "prompt": "consent",
            "state": f"{provider}:{state}",
        }
        auth_url = f"https://accounts.google.com/o/oauth2/v2/auth?{urlencode(params)}"

    elif provider == "outlook":
        # Microsoft OAuth
        from urllib.parse import urlencode

        params = {
            "client_id": settings.microsoft_client_id if hasattr(settings, 'microsoft_client_id') else "",
            "redirect_uri": f"{settings.frontend_url}/settings/email/callback",
            "response_type": "code",
            "scope": "openid profile email Mail.Read Mail.Send offline_access",
            "state": f"{provider}:{state}",
        }
        auth_url = f"https://login.microsoftonline.com/common/oauth2/v2.0/authorize?{urlencode(params)}"

    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported OAuth provider: {provider}",
        )

    return OAuthStartResponse(auth_url=auth_url, state=state)


@router.post("/oauth/callback", response_model=OAuthCallbackResponse)
async def oauth_callback(
    callback_data: OAuthCallbackRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Handle OAuth callback and create email account."""
    import httpx
    from app.config import settings

    provider = callback_data.provider

    try:
        if provider == "gmail":
            # Exchange code for tokens
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    "https://oauth2.googleapis.com/token",
                    data={
                        "client_id": settings.google_client_id,
                        "client_secret": settings.google_client_secret,
                        "code": callback_data.code,
                        "redirect_uri": f"{settings.frontend_url}/settings/email/callback",
                        "grant_type": "authorization_code",
                    },
                )
                tokens = response.json()

            if "error" in tokens:
                return OAuthCallbackResponse(
                    success=False,
                    error=tokens.get("error_description", tokens["error"]),
                )

            # Get user email from Gmail API
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    "https://www.googleapis.com/gmail/v1/users/me/profile",
                    headers={"Authorization": f"Bearer {tokens['access_token']}"},
                )
                profile = response.json()

            email_address = profile.get("emailAddress")

            # Create account
            account = EmailAccount(
                user_id=current_user.id,
                provider="gmail",
                email_address=email_address,
                display_name=email_address.split("@")[0].title(),
                access_token=tokens["access_token"],
                refresh_token=tokens.get("refresh_token"),
                token_expiry=datetime.utcnow() if tokens.get("expires_in") else None,
                briefing_days=["all"],
                categories_to_include=["all"],
            )

        elif provider == "outlook":
            # Similar flow for Outlook
            # ... (implementation would follow same pattern)
            return OAuthCallbackResponse(
                success=False,
                error="Outlook OAuth not yet implemented",
            )

        else:
            return OAuthCallbackResponse(
                success=False,
                error=f"Unknown provider: {provider}",
            )

        # Check for existing account
        existing = await db.execute(
            select(EmailAccount).where(
                EmailAccount.user_id == current_user.id,
                EmailAccount.email_address == email_address,
            )
        )
        existing_account = existing.scalar_one_or_none()

        if existing_account:
            # Update tokens
            existing_account.access_token = account.access_token
            existing_account.refresh_token = account.refresh_token
            existing_account.token_expiry = account.token_expiry
            existing_account.sync_error = None
            await db.commit()
            return OAuthCallbackResponse(
                success=True,
                account_id=existing_account.id,
                email_address=email_address,
            )

        db.add(account)
        await db.commit()
        await db.refresh(account)

        return OAuthCallbackResponse(
            success=True,
            account_id=account.id,
            email_address=email_address,
        )

    except Exception as e:
        return OAuthCallbackResponse(
            success=False,
            error=str(e),
        )


@router.post("/{account_id}/sync")
async def sync_email_account(
    account_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Manually trigger sync for an email account."""
    result = await db.execute(
        select(EmailAccount).where(
            EmailAccount.id == account_id,
            EmailAccount.user_id == current_user.id,
        )
    )
    account = result.scalar_one_or_none()

    if not account:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Email account not found",
        )

    try:
        # Update last sync time
        account.last_sync = datetime.utcnow()
        account.sync_error = None
        await db.commit()

        return {"success": True, "last_sync": account.last_sync}

    except Exception as e:
        account.sync_error = str(e)
        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Sync failed: {str(e)}",
        )
