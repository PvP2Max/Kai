"""
Core intelligence modules for Kai.
"""
from app.core.model_router import ModelRouter, ModelTier, RoutingConfig, CostTracker
from app.core.tools import TOOLS

# Lazy imports to avoid circular dependencies
def get_chat_handler():
    from app.core.chat import ChatHandler
    return ChatHandler

def get_tool_executor():
    from app.core.tool_executor import ToolExecutor
    return ToolExecutor

__all__ = [
    "get_chat_handler",
    "get_tool_executor",
    "ModelRouter",
    "ModelTier",
    "RoutingConfig",
    "CostTracker",
    "TOOLS",
]
