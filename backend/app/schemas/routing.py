"""
Model routing schemas.
"""
from typing import Optional, List
from pydantic import BaseModel
from decimal import Decimal


class ChainStep(BaseModel):
    model: str  # 'haiku', 'sonnet', 'opus'
    purpose: str  # 'classify', 'execute', 'synthesize', 'validate'
    prompt_template: str


class ChainConfig(BaseModel):
    name: str
    description: str
    steps: List[ChainStep]


class RoutingSettingsResponse(BaseModel):
    task_routing: dict
    tool_routing: dict
    custom_patterns: dict
    default_model: str
    enable_chaining: bool
    chain_configs: dict
    cost_limit_daily: Optional[float] = None
    prefer_speed: bool
    prefer_quality: bool


class RoutingSettingsUpdate(BaseModel):
    task_routing: Optional[dict] = None
    tool_routing: Optional[dict] = None
    custom_patterns: Optional[dict] = None
    default_model: Optional[str] = None
    enable_chaining: Optional[bool] = None
    chain_configs: Optional[dict] = None
    cost_limit_daily: Optional[float] = None
    prefer_speed: Optional[bool] = None
    prefer_quality: Optional[bool] = None


class RoutingTestRequest(BaseModel):
    message: str
    task_type: Optional[str] = None


class RoutingTestResponse(BaseModel):
    selected_model: str
    would_chain: bool
    chain_name: Optional[str] = None
    reasoning: str


class RoutingDefaultsResponse(BaseModel):
    task_routing: dict
    tool_routing: dict
    patterns: dict
    chains: dict


class ResetRoutingRequest(BaseModel):
    sections: List[str]  # ['task_routing', 'tool_routing', 'patterns', 'chains']
