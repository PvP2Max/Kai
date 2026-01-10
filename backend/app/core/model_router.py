"""
Intelligent model selection based on task complexity and type.
Supports configurable routing rules, multi-model chains, and usage analytics.
"""
from enum import Enum
from typing import Optional, List, Dict, Any, Tuple
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal
import re
import json

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select


class ModelTier(Enum):
    HAIKU = "claude-3-5-haiku-20241022"
    SONNET = "claude-sonnet-4-20250514"
    OPUS = "claude-opus-4-20250514"


@dataclass
class ModelStep:
    """A single step in a multi-model chain."""
    tier: ModelTier
    purpose: str
    input_tokens: int = 0
    output_tokens: int = 0
    latency_ms: int = 0


@dataclass
class ChainResult:
    """Result of a multi-model chain execution."""
    steps: List[ModelStep]
    final_response: str
    total_cost: float
    total_latency_ms: int


# Default task-to-model mappings
DEFAULT_TASK_ROUTING = {
    "greeting": "haiku",
    "simple_lookup": "haiku",
    "confirmation": "haiku",
    "basic_crud": "haiku",
    "status_check": "haiku",
    "calendar_query": "haiku",
    "reminder_query": "haiku",

    "calendar_create": "sonnet",
    "reminder_create": "sonnet",
    "note_create": "sonnet",
    "email_draft": "sonnet",
    "standard_tool_use": "sonnet",
    "daily_briefing": "sonnet",
    "travel_time": "sonnet",

    "schedule_optimization": "opus",
    "weekly_review": "opus",
    "meeting_summary": "opus",
    "complex_analysis": "opus",
    "decision_support": "opus",
    "pattern_learning": "opus",
    "conflict_resolution": "opus",
    "email_triage": "opus",
    "project_status": "opus",
    "explain_reasoning": "opus",
}

# Default tool-to-model mappings
DEFAULT_TOOL_ROUTING = {
    "get_calendar_events": "haiku",
    "get_reminders": "haiku",
    "get_note": "haiku",
    "search_notes": "haiku",
    "get_read_later_list": "haiku",
    "get_weather": "haiku",
    "complete_reminder": "haiku",
    "get_travel_time": "haiku",

    "create_calendar_event": "sonnet",
    "update_calendar_event": "sonnet",
    "create_reminder": "sonnet",
    "create_note": "sonnet",
    "draft_email_reply": "sonnet",
    "save_for_later": "sonnet",
    "create_follow_up": "sonnet",
    "send_push_notification": "sonnet",

    "propose_schedule_optimization": "opus",
    "generate_weekly_review": "opus",
    "generate_daily_briefing": "sonnet",
    "explain_reasoning": "opus",
    "triage_emails": "opus",
    "get_project_status": "opus",
    "get_meeting_prep": "opus",
    "get_meeting_summary": "opus",
}

# Default pattern matching
DEFAULT_PATTERNS = {
    "haiku": [
        r"what time",
        r"what'?s on my calendar",
        r"do i have any (meetings|events|reminders)",
        r"read (back|me) (the|my)",
        r"list my",
        r"show me",
        r"how many",
        r"is there a",
        r"when is",
        r"where is",
        r"confirm",
        r"yes|no|ok|okay|sure|thanks|thank you",
        r"cancel that",
        r"never\s?mind",
        r"^(hi|hey|hello|good morning|good afternoon)$",
    ],
    "opus": [
        r"optimi[zs]e my (schedule|calendar|day|week)",
        r"reorgani[zs]e",
        r"what should i prioriti[zs]e",
        r"help me (decide|think through|figure out)",
        r"analy[zs]e",
        r"why did you",
        r"explain your reasoning",
        r"what patterns",
        r"review my (week|month|progress)",
        r"suggest.*(strategy|approach|plan)",
        r"complex|complicated|nuanced",
        r"trade.?offs?",
        r"compare.*(options|approaches)",
        r"what do you think",
        r"advice",
    ],
}

# Pre-defined multi-model chains
DEFAULT_CHAINS = {
    "classify_execute_synthesize_chain": {
        "description": "Haiku classifies intent, Sonnet executes tools, Opus synthesizes response",
        "steps": [
            {"model": "haiku", "purpose": "classify", "prompt_template": "classify_intent"},
            {"model": "sonnet", "purpose": "execute", "prompt_template": "execute_tools"},
            {"model": "opus", "purpose": "synthesize", "prompt_template": "synthesize_response"},
        ]
    },
    "transcribe_summarize_chain": {
        "description": "Process meeting: Sonnet structures transcript, Opus generates insights",
        "steps": [
            {"model": "sonnet", "purpose": "structure", "prompt_template": "structure_transcript"},
            {"model": "opus", "purpose": "synthesize", "prompt_template": "meeting_insights"},
        ]
    },
    "analyze_optimize_chain": {
        "description": "Haiku gathers data, Opus analyzes and optimizes",
        "steps": [
            {"model": "haiku", "purpose": "gather", "prompt_template": "gather_schedule_data"},
            {"model": "opus", "purpose": "analyze", "prompt_template": "optimize_schedule"},
        ]
    },
    "classify_triage_chain": {
        "description": "Haiku does initial sort, Sonnet categorizes, Opus prioritizes",
        "steps": [
            {"model": "haiku", "purpose": "classify", "prompt_template": "initial_email_sort"},
            {"model": "sonnet", "purpose": "categorize", "prompt_template": "categorize_emails"},
            {"model": "opus", "purpose": "prioritize", "prompt_template": "prioritize_actions"},
        ]
    },
}


class RoutingConfig:
    """User-configurable routing settings."""

    def __init__(self, db: AsyncSession, user_id: str):
        self.db = db
        self.user_id = user_id
        self._cache = None
        self._cache_time = None
        self._cache_ttl = timedelta(minutes=5)

    def get_config(self) -> dict:
        """Get current routing configuration (sync version for compatibility)."""
        # Return defaults if not cached
        if not self._cache:
            self._cache = {
                "task_routing": DEFAULT_TASK_ROUTING,
                "tool_routing": DEFAULT_TOOL_ROUTING,
                "patterns": DEFAULT_PATTERNS,
                "default_model": "sonnet",
                "enable_chaining": True,
                "chain_configs": {},
                "cost_limit_daily": None,
                "prefer_speed": False,
                "prefer_quality": False,
            }
        return self._cache

    async def get_config_async(self) -> dict:
        """Get current routing configuration."""
        if self._cache and self._cache_time and datetime.utcnow() - self._cache_time < self._cache_ttl:
            return self._cache

        from app.models.preferences import RoutingSettings

        result = await self.db.execute(
            select(RoutingSettings).where(RoutingSettings.user_id == self.user_id)
        )
        config = result.scalar_one_or_none()

        if config:
            self._cache = {
                "task_routing": {**DEFAULT_TASK_ROUTING, **(config.task_routing or {})},
                "tool_routing": {**DEFAULT_TOOL_ROUTING, **(config.tool_routing or {})},
                "patterns": {
                    "haiku": DEFAULT_PATTERNS["haiku"] + (config.custom_patterns or {}).get("haiku", []),
                    "opus": DEFAULT_PATTERNS["opus"] + (config.custom_patterns or {}).get("opus", []),
                },
                "default_model": config.default_model or "sonnet",
                "enable_chaining": config.enable_chaining,
                "chain_configs": config.chain_configs or {},
                "cost_limit_daily": float(config.cost_limit_daily) if config.cost_limit_daily else None,
                "prefer_speed": config.prefer_speed,
                "prefer_quality": config.prefer_quality,
            }
        else:
            self._cache = {
                "task_routing": DEFAULT_TASK_ROUTING,
                "tool_routing": DEFAULT_TOOL_ROUTING,
                "patterns": DEFAULT_PATTERNS,
                "default_model": "sonnet",
                "enable_chaining": True,
                "chain_configs": {},
                "cost_limit_daily": None,
                "prefer_speed": False,
                "prefer_quality": False,
            }

        self._cache_time = datetime.utcnow()
        return self._cache

    async def update_config(self, updates: dict) -> dict:
        """Update routing configuration."""
        from app.models.preferences import RoutingSettings

        result = await self.db.execute(
            select(RoutingSettings).where(RoutingSettings.user_id == self.user_id)
        )
        config = result.scalar_one_or_none()

        if not config:
            config = RoutingSettings(user_id=self.user_id)
            self.db.add(config)

        for key, value in updates.items():
            if hasattr(config, key):
                setattr(config, key, value)

        await self.db.commit()
        self._cache = None
        return await self.get_config_async()


class ModelRouter:
    """Intelligent model selection with configurable rules."""

    def __init__(self, config: RoutingConfig):
        self.config = config
        self._compiled_patterns = {}

    def _get_patterns(self) -> dict:
        """Get compiled regex patterns."""
        cfg = self.config.get_config()
        cache_key = str(cfg["patterns"])

        if cache_key not in self._compiled_patterns:
            self._compiled_patterns[cache_key] = {
                "haiku": [re.compile(p, re.IGNORECASE) for p in cfg["patterns"]["haiku"]],
                "opus": [re.compile(p, re.IGNORECASE) for p in cfg["patterns"]["opus"]],
            }

        return self._compiled_patterns[cache_key]

    def select_model(
        self,
        message: str,
        conversation_history: list = None,
        pending_tools: list = None,
        task_type: Optional[str] = None,
        force_tier: Optional[ModelTier] = None
    ) -> ModelTier:
        """Select the appropriate model based on multiple signals."""
        cfg = self.config.get_config()

        if force_tier:
            return force_tier

        if cfg.get("prefer_speed"):
            return self._select_with_speed_bias(message, task_type, pending_tools)
        if cfg.get("prefer_quality"):
            return self._select_with_quality_bias(message, task_type, pending_tools)

        if task_type and task_type in cfg["task_routing"]:
            tier_name = cfg["task_routing"][task_type].upper()
            return ModelTier[tier_name]

        if pending_tools:
            tool_tier = self._route_by_tools(pending_tools, cfg)
            if tool_tier:
                return tool_tier

        patterns = self._get_patterns()
        message_lower = message.lower().strip()

        for pattern in patterns["opus"]:
            if pattern.search(message_lower):
                return ModelTier.OPUS

        for pattern in patterns["haiku"]:
            if pattern.search(message_lower):
                return ModelTier.HAIKU

        if conversation_history and self._should_escalate(conversation_history):
            return ModelTier.OPUS

        default = cfg.get("default_model", "sonnet").upper()
        return ModelTier[default]

    def _route_by_tools(self, tools: list, cfg: dict) -> Optional[ModelTier]:
        """Route based on tools being used."""
        tool_routing = cfg["tool_routing"]
        tiers_needed = set()

        for tool in tools:
            if tool in tool_routing:
                tiers_needed.add(tool_routing[tool])

        if "opus" in tiers_needed:
            return ModelTier.OPUS
        if "sonnet" in tiers_needed:
            return ModelTier.SONNET
        if "haiku" in tiers_needed:
            return ModelTier.HAIKU

        return None

    def _select_with_speed_bias(self, message: str, task_type: str, tools: list) -> ModelTier:
        """Prefer faster models."""
        base = self._select_base(message, task_type, tools)
        if base == ModelTier.OPUS:
            critical_tasks = ["schedule_optimization", "decision_support", "meeting_summary"]
            if task_type not in critical_tasks:
                return ModelTier.SONNET
        return base

    def _select_with_quality_bias(self, message: str, task_type: str, tools: list) -> ModelTier:
        """Prefer better models."""
        base = self._select_base(message, task_type, tools)
        if base == ModelTier.HAIKU:
            return ModelTier.SONNET
        if base == ModelTier.SONNET:
            upgrade_tasks = ["email_draft", "note_create", "daily_briefing"]
            if task_type in upgrade_tasks:
                return ModelTier.OPUS
        return base

    def _select_base(self, message: str, task_type: str, tools: list) -> ModelTier:
        """Base model selection without bias."""
        cfg = self.config.get_config()

        if task_type and task_type in cfg["task_routing"]:
            return ModelTier[cfg["task_routing"][task_type].upper()]

        if tools:
            tool_tier = self._route_by_tools(tools, cfg)
            if tool_tier:
                return tool_tier

        return ModelTier.SONNET

    def _should_escalate(self, history: list) -> bool:
        """Check if conversation suggests escalation."""
        escalation_triggers = [
            r"i'm not sure",
            r"it's complicated",
            r"there's a conflict",
            r"multiple options",
            r"what would you recommend",
            r"this is important",
            r"high priority",
            r"urgent",
        ]
        patterns = [re.compile(p, re.IGNORECASE) for p in escalation_triggers]

        recent = history[-4:] if len(history) > 4 else history
        for msg in recent:
            if msg.get("role") == "user":
                content = msg.get("content", "").lower()
                for pattern in patterns:
                    if pattern.search(content):
                        return True
        return False

    def should_use_chain(self, message: str, task_type: Optional[str] = None) -> Optional[str]:
        """Determine if request should use a multi-model chain."""
        cfg = self.config.get_config()

        if not cfg.get("enable_chaining", True):
            return None

        chain_tasks = {
            "meeting_summary": "transcribe_summarize_chain",
            "schedule_optimization": "analyze_optimize_chain",
            "email_triage": "classify_triage_chain",
            "complex_query": "classify_execute_synthesize_chain",
        }

        if task_type and task_type in chain_tasks:
            chain_name = chain_tasks[task_type]
            if chain_name in cfg.get("chain_configs", {}) or chain_name in DEFAULT_CHAINS:
                return chain_name

        return None


class CostTracker:
    """Track model usage for cost awareness and analytics."""

    COSTS = {
        ModelTier.HAIKU: {"input": 0.00025, "output": 0.00125},
        ModelTier.SONNET: {"input": 0.003, "output": 0.015},
        ModelTier.OPUS: {"input": 0.015, "output": 0.075},
    }

    def __init__(self, db: AsyncSession, user_id: str):
        self.db = db
        self.user_id = user_id

    async def record_usage(
        self,
        tier: ModelTier,
        input_tokens: int,
        output_tokens: int,
        conversation_id: str = None,
        task_type: str = None,
        routing_reason: str = None,
        latency_ms: int = None
    ):
        """Record model usage to database."""
        from app.models.preferences import ModelUsage
        from uuid import UUID

        usage = ModelUsage(
            user_id=UUID(self.user_id),
            conversation_id=UUID(conversation_id) if conversation_id else None,
            model_tier=tier.name.lower(),
            model_version=tier.value,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            task_type=task_type,
            routing_reason=routing_reason,
            latency_ms=latency_ms,
        )
        self.db.add(usage)
        await self.db.commit()

    async def get_usage_summary(self, period: str = "day") -> dict:
        """Get usage summary for a time period."""
        from app.models.preferences import ModelUsage

        if period == "day":
            start = datetime.utcnow() - timedelta(days=1)
        elif period == "week":
            start = datetime.utcnow() - timedelta(weeks=1)
        elif period == "month":
            start = datetime.utcnow() - timedelta(days=30)
        else:
            start = datetime.utcnow() - timedelta(days=1)

        result = await self.db.execute(
            select(ModelUsage).where(
                ModelUsage.user_id == self.user_id,
                ModelUsage.created_at >= start
            )
        )
        usages = result.scalars().all()

        summary = {
            "period": period,
            "start": start.isoformat(),
            "end": datetime.utcnow().isoformat(),
            "by_model": {},
            "by_task": {},
            "totals": {
                "requests": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "cost": 0.0,
                "avg_latency_ms": 0
            }
        }

        latencies = []

        for usage in usages:
            tier = ModelTier[usage.model_tier.upper()]

            if tier.name not in summary["by_model"]:
                summary["by_model"][tier.name] = {
                    "requests": 0,
                    "input_tokens": 0,
                    "output_tokens": 0,
                    "cost": 0.0
                }

            model_summary = summary["by_model"][tier.name]
            model_summary["requests"] += 1
            model_summary["input_tokens"] += usage.input_tokens
            model_summary["output_tokens"] += usage.output_tokens
            model_summary["cost"] += self._calculate_cost(tier, usage.input_tokens, usage.output_tokens)

            task = usage.task_type or "unknown"
            if task not in summary["by_task"]:
                summary["by_task"][task] = {"requests": 0, "cost": 0.0}
            summary["by_task"][task]["requests"] += 1
            summary["by_task"][task]["cost"] += self._calculate_cost(tier, usage.input_tokens, usage.output_tokens)

            summary["totals"]["requests"] += 1
            summary["totals"]["input_tokens"] += usage.input_tokens
            summary["totals"]["output_tokens"] += usage.output_tokens
            summary["totals"]["cost"] += self._calculate_cost(tier, usage.input_tokens, usage.output_tokens)

            if usage.latency_ms:
                latencies.append(usage.latency_ms)

        if latencies:
            summary["totals"]["avg_latency_ms"] = sum(latencies) // len(latencies)

        return summary

    async def get_daily_costs(self, days: int = 30) -> List[dict]:
        """Get daily cost breakdown for charting."""
        from app.models.preferences import ModelUsage

        start = datetime.utcnow() - timedelta(days=days)

        result = await self.db.execute(
            select(ModelUsage).where(
                ModelUsage.user_id == self.user_id,
                ModelUsage.created_at >= start
            )
        )
        usages = result.scalars().all()

        daily = {}
        for usage in usages:
            day = usage.created_at.date().isoformat()
            tier = ModelTier[usage.model_tier.upper()]
            cost = self._calculate_cost(tier, usage.input_tokens, usage.output_tokens)

            if day not in daily:
                daily[day] = {"date": day, "haiku": 0, "sonnet": 0, "opus": 0, "total": 0}

            daily[day][tier.name.lower()] += cost
            daily[day]["total"] += cost

        return sorted(daily.values(), key=lambda x: x["date"])

    async def check_daily_limit(self) -> Tuple[bool, float, Optional[float]]:
        """Check if daily cost limit is exceeded."""
        from app.models.preferences import RoutingSettings, ModelUsage

        result = await self.db.execute(
            select(RoutingSettings).where(RoutingSettings.user_id == self.user_id)
        )
        cfg = result.scalar_one_or_none()
        limit = float(cfg.cost_limit_daily) if cfg and cfg.cost_limit_daily else None

        if not limit:
            return True, 0, None

        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

        result = await self.db.execute(
            select(ModelUsage).where(
                ModelUsage.user_id == self.user_id,
                ModelUsage.created_at >= today_start
            )
        )
        usages = result.scalars().all()

        current_cost = sum(
            self._calculate_cost(ModelTier[u.model_tier.upper()], u.input_tokens, u.output_tokens)
            for u in usages
        )

        return current_cost < limit, current_cost, limit

    def _calculate_cost(self, tier: ModelTier, input_tokens: int, output_tokens: int) -> float:
        costs = self.COSTS[tier]
        return (input_tokens / 1000) * costs["input"] + (output_tokens / 1000) * costs["output"]
