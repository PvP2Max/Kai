"""
Usage analytics endpoints.
"""
from typing import List
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.database import get_db
from app.models.user import User
from app.models.preferences import ModelUsage
from app.schemas.usage import UsageSummary, DailyCost, TaskBreakdown, CostResponse
from app.api.deps import get_current_user
from app.core.model_router import CostTracker

router = APIRouter()


@router.get("/summary", response_model=UsageSummary)
async def get_usage_summary(
    period: str = Query("day", enum=["day", "week", "month"]),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get usage summary (tokens, costs by model)."""
    tracker = CostTracker(db, str(current_user.id))
    summary = await tracker.get_usage_summary(period)
    return summary


@router.get("/history")
async def get_usage_history(
    limit: int = 100,
    offset: int = 0,
    model_tier: str = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get detailed usage history."""
    query = select(ModelUsage).where(ModelUsage.user_id == current_user.id)

    if model_tier:
        query = query.where(ModelUsage.model_tier == model_tier)

    # Get total count
    count_result = await db.execute(
        select(func.count(ModelUsage.id)).where(ModelUsage.user_id == current_user.id)
    )
    total = count_result.scalar()

    # Get items
    query = query.order_by(ModelUsage.created_at.desc()).offset(offset).limit(limit)
    result = await db.execute(query)
    items = result.scalars().all()

    return {
        "items": [
            {
                "id": str(item.id),
                "model_tier": item.model_tier,
                "model_version": item.model_version,
                "input_tokens": item.input_tokens,
                "output_tokens": item.output_tokens,
                "task_type": item.task_type,
                "routing_reason": item.routing_reason,
                "latency_ms": item.latency_ms,
                "created_at": item.created_at.isoformat(),
            }
            for item in items
        ],
        "total": total,
    }


@router.get("/cost", response_model=CostResponse)
async def get_cost_breakdown(
    period: str = Query("day", enum=["day", "week", "month"]),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get estimated cost breakdown."""
    tracker = CostTracker(db, str(current_user.id))

    # Get current period cost
    summary = await tracker.get_usage_summary(period)
    current_cost = summary["totals"]["cost"]

    # Get daily costs for the period
    if period == "day":
        days = 1
    elif period == "week":
        days = 7
    else:
        days = 30

    daily_costs = await tracker.get_daily_costs(days)

    # Project monthly cost based on current usage
    if daily_costs:
        avg_daily = sum(d["total"] for d in daily_costs) / len(daily_costs)
        projected_month = avg_daily * 30
    else:
        projected_month = 0.0

    return CostResponse(
        current_period=current_cost,
        projected_month=projected_month,
        by_day=daily_costs,
    )


@router.get("/daily-costs", response_model=List[DailyCost])
async def get_daily_costs(
    days: int = Query(30, ge=1, le=90),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get daily cost data for charts."""
    tracker = CostTracker(db, str(current_user.id))
    return await tracker.get_daily_costs(days)


@router.get("/task-breakdown")
async def get_task_breakdown(
    period: str = Query("week", enum=["day", "week", "month"]),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get usage breakdown by task type."""
    if period == "day":
        start = datetime.utcnow() - timedelta(days=1)
    elif period == "week":
        start = datetime.utcnow() - timedelta(weeks=1)
    else:
        start = datetime.utcnow() - timedelta(days=30)

    # Get usage grouped by task type
    result = await db.execute(
        select(
            ModelUsage.task_type,
            func.count(ModelUsage.id).label("requests"),
            func.sum(ModelUsage.input_tokens).label("input_tokens"),
            func.sum(ModelUsage.output_tokens).label("output_tokens"),
            func.avg(ModelUsage.latency_ms).label("avg_latency"),
        )
        .where(
            ModelUsage.user_id == current_user.id,
            ModelUsage.created_at >= start,
        )
        .group_by(ModelUsage.task_type)
    )

    tasks = []
    for row in result.all():
        task_type = row[0] or "unknown"
        requests = row[1]
        input_tokens = row[2] or 0
        output_tokens = row[3] or 0
        avg_latency = int(row[4] or 0)

        # Estimate cost (using sonnet rates as default)
        cost = (input_tokens / 1000) * 0.003 + (output_tokens / 1000) * 0.015

        tasks.append({
            "task_type": task_type,
            "requests": requests,
            "cost": round(cost, 4),
            "avg_latency_ms": avg_latency,
        })

    return {"tasks": sorted(tasks, key=lambda x: x["cost"], reverse=True)}
