"""
Chat schemas.
"""
from datetime import datetime
from typing import Optional, List, Any
from pydantic import BaseModel
from uuid import UUID


class ActionTaken(BaseModel):
    tool_name: str
    tool_input: dict
    result: Any
    success: bool


class ChatRequest(BaseModel):
    message: str
    conversation_id: Optional[UUID] = None
    source: str = "web"  # 'siri' | 'web'


class ChatResponse(BaseModel):
    response: str
    conversation_id: UUID
    actions_taken: List[ActionTaken] = []
    model_info: Optional[dict] = None


class MessageResponse(BaseModel):
    id: UUID
    role: str
    content: str
    tool_calls: Optional[dict] = None
    model_used: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class ConversationResponse(BaseModel):
    id: UUID
    title: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    messages: List[MessageResponse] = []

    class Config:
        from_attributes = True


class ConversationListResponse(BaseModel):
    id: UUID
    title: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    message_count: int = 0

    class Config:
        from_attributes = True
