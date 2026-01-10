"""
Model routing settings endpoints.
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.preferences import RoutingSettings
from app.schemas.routing import (
    RoutingSettingsResponse,
    RoutingSettingsUpdate,
    RoutingTestRequest,
    RoutingTestResponse,
    RoutingDefaultsResponse,
    ResetRoutingRequest,
    ChainConfig,
)
from app.api.deps import get_current_user
from app.core.model_router import (
    ModelRouter,
    RoutingConfig,
    DEFAULT_TASK_ROUTING,
    DEFAULT_TOOL_ROUTING,
    DEFAULT_PATTERNS,
    DEFAULT_CHAINS,
)

router = APIRouter()


@router.get("/settings", response_model=RoutingSettingsResponse)
async def get_routing_settings(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get current routing configuration."""
    config = RoutingConfig(db, str(current_user.id))
    return config.get_config()


@router.put("/settings", response_model=RoutingSettingsResponse)
async def update_routing_settings(
    settings_data: RoutingSettingsUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update routing configuration."""
    config = RoutingConfig(db, str(current_user.id))
    updates = settings_data.model_dump(exclude_unset=True)
    return await config.update_config(updates)


@router.get("/defaults", response_model=RoutingDefaultsResponse)
async def get_routing_defaults(
    current_user: User = Depends(get_current_user),
):
    """Get default routing rules (for reference/reset)."""
    return RoutingDefaultsResponse(
        task_routing=DEFAULT_TASK_ROUTING,
        tool_routing=DEFAULT_TOOL_ROUTING,
        patterns=DEFAULT_PATTERNS,
        chains=DEFAULT_CHAINS,
    )


@router.post("/reset")
async def reset_routing(
    request: ResetRoutingRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Reset routing settings to defaults."""
    result = await db.execute(
        select(RoutingSettings).where(RoutingSettings.user_id == current_user.id)
    )
    settings = result.scalar_one_or_none()

    if not settings:
        return {"message": "No custom settings to reset"}

    for section in request.sections:
        if section == "task_routing":
            settings.task_routing = {}
        elif section == "tool_routing":
            settings.tool_routing = {}
        elif section == "patterns":
            settings.custom_patterns = {"haiku": [], "opus": []}
        elif section == "chains":
            settings.chain_configs = {}

    await db.commit()

    return {"message": f"Reset sections: {', '.join(request.sections)}"}


@router.get("/chains")
async def get_chains(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get available chain configurations."""
    result = await db.execute(
        select(RoutingSettings).where(RoutingSettings.user_id == current_user.id)
    )
    settings = result.scalar_one_or_none()

    custom_chains = settings.chain_configs if settings else {}

    return {
        "default_chains": DEFAULT_CHAINS,
        "custom_chains": custom_chains,
    }


@router.post("/chains")
async def create_chain(
    chain: ChainConfig,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a custom chain configuration."""
    result = await db.execute(
        select(RoutingSettings).where(RoutingSettings.user_id == current_user.id)
    )
    settings = result.scalar_one_or_none()

    if not settings:
        settings = RoutingSettings(user_id=current_user.id)
        db.add(settings)

    if settings.chain_configs is None:
        settings.chain_configs = {}

    settings.chain_configs[chain.name] = {
        "description": chain.description,
        "steps": [step.model_dump() for step in chain.steps],
    }

    await db.commit()

    return {"message": f"Created chain: {chain.name}"}


@router.put("/chains/{chain_name}")
async def update_chain(
    chain_name: str,
    chain: ChainConfig,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update a custom chain configuration."""
    result = await db.execute(
        select(RoutingSettings).where(RoutingSettings.user_id == current_user.id)
    )
    settings = result.scalar_one_or_none()

    if not settings or chain_name not in (settings.chain_configs or {}):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Chain '{chain_name}' not found",
        )

    settings.chain_configs[chain.name] = {
        "description": chain.description,
        "steps": [step.model_dump() for step in chain.steps],
    }

    # Remove old name if renamed
    if chain.name != chain_name:
        del settings.chain_configs[chain_name]

    await db.commit()

    return {"message": f"Updated chain: {chain.name}"}


@router.delete("/chains/{chain_name}")
async def delete_chain(
    chain_name: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete a custom chain configuration."""
    result = await db.execute(
        select(RoutingSettings).where(RoutingSettings.user_id == current_user.id)
    )
    settings = result.scalar_one_or_none()

    if not settings or chain_name not in (settings.chain_configs or {}):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Chain '{chain_name}' not found",
        )

    del settings.chain_configs[chain_name]
    await db.commit()

    return {"message": f"Deleted chain: {chain_name}"}


@router.post("/test", response_model=RoutingTestResponse)
async def test_routing(
    request: RoutingTestRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Test routing for a message (doesn't execute)."""
    config = RoutingConfig(db, str(current_user.id))
    router_instance = ModelRouter(config)

    model_tier = router_instance.select_model(
        message=request.message,
        task_type=request.task_type,
    )

    chain_name = router_instance.should_use_chain(
        request.message,
        request.task_type or "unknown",
    )

    reasoning = f"Selected {model_tier.name} based on "
    if request.task_type:
        reasoning += f"task type '{request.task_type}'"
    else:
        reasoning += "message pattern matching"

    if chain_name:
        reasoning += f" (will use chain: {chain_name})"

    return RoutingTestResponse(
        selected_model=model_tier.name,
        would_chain=chain_name is not None,
        chain_name=chain_name,
        reasoning=reasoning,
    )
