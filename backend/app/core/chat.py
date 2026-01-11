"""
ChatHandler - Main chat processing logic for Kai.
Orchestrates Claude API calls, tool execution, and conversation management.
"""
import json
from datetime import datetime, date, timedelta
from typing import Optional, List, Dict, Any, AsyncGenerator
from uuid import UUID
from zoneinfo import ZoneInfo

import anthropic
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.config import settings
from app.models.conversation import Conversation, Message
from app.models.activity import ActivityLog
from app.models.user import User
from app.core.model_router import ModelRouter, ModelTier, CostTracker, RoutingConfig
from app.core.tools import TOOLS
from app.core.tool_executor import ToolExecutor


class ChatHandler:
    """
    Main handler for chat interactions with Kai.
    Manages conversations, Claude API calls, tool execution, and activity logging.
    """

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id
        self.client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        self.routing_config = RoutingConfig(db, str(user_id))
        self.model_router = ModelRouter(self.routing_config)
        self.cost_tracker = CostTracker(db, user_id)
        self.tool_executor = ToolExecutor(db, user_id)
        self._cached_timezone: Optional[str] = None
        self._user_location: Optional[Dict[str, float]] = None

    async def _get_user_timezone(self) -> str:
        """Get the user's timezone from the database."""
        if self._cached_timezone:
            return self._cached_timezone

        result = await self.db.execute(
            select(User.timezone).where(User.id == self.user_id)
        )
        timezone = result.scalar_one_or_none()
        self._cached_timezone = timezone or "America/Chicago"
        return self._cached_timezone

    async def get_or_create_conversation(
        self,
        conversation_id: Optional[UUID] = None,
        source: str = "web"
    ) -> Conversation:
        """Get existing conversation or create a new one."""
        if conversation_id:
            result = await self.db.execute(
                select(Conversation).where(
                    and_(
                        Conversation.id == conversation_id,
                        Conversation.user_id == self.user_id,
                    )
                )
            )
            conversation = result.scalar_one_or_none()
            if conversation:
                return conversation

        # Create new conversation
        conversation = Conversation(
            user_id=self.user_id,
        )
        self.db.add(conversation)
        await self.db.commit()
        await self.db.refresh(conversation)
        return conversation

    async def get_conversation_history(
        self,
        conversation_id: UUID,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """Get conversation history formatted for Claude API."""
        result = await self.db.execute(
            select(Message)
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.desc())
            .limit(limit)
        )
        messages = result.scalars().all()

        # Reverse to get chronological order
        messages = list(reversed(messages))

        formatted = []
        for msg in messages:
            formatted.append({
                "role": msg.role,
                "content": msg.content,
            })

        return formatted

    async def save_message(
        self,
        conversation_id: UUID,
        role: str,
        content: str,
        model_used: Optional[str] = None,
        tool_calls: Optional[List[Dict]] = None,
    ) -> Message:
        """Save a message to the conversation."""
        message = Message(
            conversation_id=conversation_id,
            role=role,
            content=content,
            model_used=model_used,
            tool_calls=tool_calls,
        )
        self.db.add(message)
        await self.db.commit()
        await self.db.refresh(message)
        return message

    async def log_activity(
        self,
        action_type: str,
        action_data: Dict[str, Any],
        reversible: bool = False,
    ):
        """Log an activity for audit trail and undo functionality."""
        activity = ActivityLog(
            user_id=self.user_id,
            action_type=action_type,
            action_data=action_data,
            reversible=reversible,
        )
        self.db.add(activity)
        await self.db.commit()

    async def _generate_conversation_title(
        self,
        conversation: Conversation,
        user_message: str,
        assistant_response: str,
    ):
        """Generate a concise title for a conversation using Haiku."""
        try:
            response = await self.client.messages.create(
                model="claude-3-5-haiku-20241022",
                max_tokens=50,
                messages=[
                    {
                        "role": "user",
                        "content": f"""Generate a very short title (3-6 words) for this conversation.
Just respond with the title, nothing else. No quotes or punctuation.

User: {user_message[:200]}
Assistant: {assistant_response[:200]}"""
                    }
                ],
            )

            title = response.content[0].text.strip()
            # Clean up the title - remove quotes if present
            title = title.strip('"\'')
            # Limit length
            if len(title) > 100:
                title = title[:97] + "..."

            conversation.title = title
            await self.db.commit()

        except Exception as e:
            # Don't fail the conversation if title generation fails
            print(f"Failed to generate conversation title: {e}")

    async def _build_system_prompt(self, message: Optional[str] = None) -> str:
        """Build the system prompt for Kai using the user's timezone and relevant knowledge."""
        user_tz = await self._get_user_timezone()
        try:
            tz = ZoneInfo(user_tz)
        except Exception:
            tz = ZoneInfo("America/Chicago")
        today = datetime.now(tz).date()

        # Get relevant knowledge if we have a message
        knowledge_context = ""
        if message:
            knowledge_context = await self._get_relevant_knowledge_context(message)

        base_prompt = f"""You are Kai (Kamron's Adaptive Intelligence), a personal AI assistant.

Today's date is {today.strftime('%A, %B %d, %Y')}.

Core Principles:
1. You are a trusted assistant. Be helpful, proactive, and respect user preferences.
2. Never make changes without explicit approval for important actions (calendar, emails).
3. When proposing changes, clearly explain what you'll do and why.
4. Learn from patterns and preferences to provide better assistance over time.
5. Keep responses concise but complete. Value efficiency.

{knowledge_context}

You have access to various tools to help manage calendar, notes, reminders, emails,
projects, and more. Use them proactively to provide comprehensive assistance.

Key behaviors:
- For calendar changes: Always propose first using propose_schedule_optimization, never modify directly
- For emails: Draft replies for review, never send directly
- For meetings: Provide prep briefings with relevant context
- Track follow-ups and remind of pending items
- IMPORTANT: When the user shares personal information (names, relationships, preferences, facts),
  use the learn_about_user tool to remember it for future conversations.
- Use get_relevant_knowledge to recall information about the user when relevant.

Remember: You're building a long-term relationship. Be consistent, reliable, and personable."""

        return base_prompt

    async def _get_relevant_knowledge_context(self, message: str) -> str:
        """Retrieve and format relevant knowledge for the system prompt."""
        try:
            from app.services.knowledge import KnowledgeService

            service = KnowledgeService(self.db, self.user_id)
            knowledge_items = await service.get_relevant_knowledge(
                query_text=message,
                max_results=8,  # Keep context small
                min_confidence=0.4,
            )

            if not knowledge_items:
                return ""

            return service.format_knowledge_for_context(knowledge_items)
        except Exception as e:
            # Don't fail if knowledge retrieval fails
            print(f"Failed to retrieve knowledge context: {e}")
            return ""

    async def process_message(
        self,
        message: str,
        conversation_id: Optional[UUID] = None,
        source: str = "web",
        attachments: Optional[List[Dict]] = None,
        force_model: Optional[str] = None,
        latitude: Optional[float] = None,
        longitude: Optional[float] = None,
    ) -> Dict[str, Any]:
        """
        Process an incoming message and generate a response.

        Args:
            message: The user's message
            conversation_id: Optional existing conversation ID
            source: Message source (web, ios, siri, watch)
            attachments: Optional file attachments
            force_model: Force a specific model tier
            latitude: User's current latitude (for location-based features)
            longitude: User's current longitude (for location-based features)

        Returns:
            Response dict with assistant reply and metadata
        """
        # Store user location for tool execution
        if latitude is not None and longitude is not None:
            self._user_location = {"latitude": latitude, "longitude": longitude}
            self.tool_executor.set_user_location(latitude, longitude)
        # Get or create conversation
        conversation = await self.get_or_create_conversation(conversation_id, source)

        # Save user message
        await self.save_message(conversation.id, "user", message)

        # Get conversation history
        history = await self.get_conversation_history(conversation.id)

        # Determine which model to use
        force_tier = ModelTier(force_model) if force_model else None
        selected_model = self.model_router.select_model(
            message=message,
            conversation_history=history,
            force_tier=force_tier,
        )

        # Check if we should use a multi-model chain
        chain_type = self.model_router.should_use_chain(message)
        if chain_type:
            response = await self._execute_chain(chain_type, message, history, conversation.id)
        else:
            response = await self._call_claude(
                model=selected_model,
                messages=history,
                conversation_id=conversation.id,
                user_message=message,
            )

        # Generate title for new conversations (first message)
        if not conversation.title and len(history) <= 2:
            await self._generate_conversation_title(
                conversation, message, response["content"]
            )

        return {
            "conversation_id": str(conversation.id),
            "response": response["content"],
            "model_used": response["model"],
            "tool_calls": response.get("tool_calls", []),
            "input_tokens": response.get("input_tokens", 0),
            "output_tokens": response.get("output_tokens", 0),
        }

    async def _call_claude(
        self,
        model: ModelTier,
        messages: List[Dict[str, Any]],
        conversation_id: UUID,
        max_iterations: int = 10,
        user_message: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Call Claude API and handle tool use loop.

        Implements agentic loop: call Claude, execute tools if needed,
        continue until no more tool calls or max iterations reached.
        """
        system_prompt = await self._build_system_prompt(user_message)
        all_tool_calls = []
        total_input_tokens = 0
        total_output_tokens = 0
        current_messages = messages.copy()

        for iteration in range(max_iterations):
            try:
                response = await self.client.messages.create(
                    model=model.value,
                    max_tokens=4096,
                    system=system_prompt,
                    messages=current_messages,
                    tools=TOOLS,
                )

                total_input_tokens += response.usage.input_tokens
                total_output_tokens += response.usage.output_tokens

                # Track costs
                await self.cost_tracker.record_usage(
                    tier=model,
                    input_tokens=response.usage.input_tokens,
                    output_tokens=response.usage.output_tokens,
                    task_type="chat",
                )

                # Check if we need to handle tool use
                if response.stop_reason == "tool_use":
                    # Extract tool calls and execute them
                    tool_results = []
                    assistant_content = []

                    for block in response.content:
                        if block.type == "text":
                            assistant_content.append({
                                "type": "text",
                                "text": block.text,
                            })
                        elif block.type == "tool_use":
                            tool_call = {
                                "id": block.id,
                                "name": block.name,
                                "input": block.input,
                            }
                            all_tool_calls.append(tool_call)
                            assistant_content.append({
                                "type": "tool_use",
                                "id": block.id,
                                "name": block.name,
                                "input": block.input,
                            })

                            # Execute the tool
                            result = await self.tool_executor.execute(
                                tool_name=block.name,
                                tool_input=block.input,
                            )

                            tool_results.append({
                                "type": "tool_result",
                                "tool_use_id": block.id,
                                "content": json.dumps(result) if isinstance(result, dict) else str(result),
                            })

                            # Log the tool execution
                            await self.log_activity(
                                action_type=f"tool:{block.name}",
                                action_data={
                                    "input": block.input,
                                    "result": result,
                                },
                                reversible=self._is_reversible_action(block.name),
                            )

                    # Add assistant message with tool calls
                    current_messages.append({
                        "role": "assistant",
                        "content": assistant_content,
                    })

                    # Add tool results
                    current_messages.append({
                        "role": "user",
                        "content": tool_results,
                    })

                    # Continue the loop
                    continue

                # No more tool calls, extract final response
                final_text = ""
                for block in response.content:
                    if block.type == "text":
                        final_text += block.text

                # Save assistant message
                await self.save_message(
                    conversation_id=conversation_id,
                    role="assistant",
                    content=final_text,
                    model_used=model.value,
                    tool_calls=all_tool_calls if all_tool_calls else None,
                )

                return {
                    "content": final_text,
                    "model": model.value,
                    "tool_calls": all_tool_calls,
                    "input_tokens": total_input_tokens,
                    "output_tokens": total_output_tokens,
                }

            except anthropic.APIError as e:
                # Log error and return error message
                await self.log_activity(
                    action_type="error:api",
                    action_data={"error": str(e), "model": model.value},
                )
                raise

        # Max iterations reached
        return {
            "content": "I apologize, but I wasn't able to complete this request. Please try again or simplify your request.",
            "model": model.value,
            "tool_calls": all_tool_calls,
            "input_tokens": total_input_tokens,
            "output_tokens": total_output_tokens,
        }

    async def _execute_chain(
        self,
        chain_type: str,
        message: str,
        history: List[Dict[str, Any]],
        conversation_id: UUID,
    ) -> Dict[str, Any]:
        """Execute a multi-model chain for complex tasks."""
        from app.core.model_router import DEFAULT_CHAINS

        chain_config = DEFAULT_CHAINS.get(chain_type)
        if not chain_config:
            # Fall back to single model
            return await self._call_claude(ModelTier.SONNET, history, conversation_id)

        steps = chain_config["steps"]
        context = {"original_message": message}
        total_input = 0
        total_output = 0
        all_tool_calls = []

        for step in steps:
            step_model = ModelTier(step["model"])
            step_task = step["task"]

            # Build step-specific prompt
            step_prompt = f"""Task: {step_task}

Context from previous steps: {json.dumps(context)}

Original request: {message}

Please complete this step of the task."""

            step_messages = history + [{"role": "user", "content": step_prompt}]

            result = await self._call_claude(
                model=step_model,
                messages=step_messages,
                conversation_id=conversation_id,
            )

            # Accumulate metrics
            total_input += result.get("input_tokens", 0)
            total_output += result.get("output_tokens", 0)
            all_tool_calls.extend(result.get("tool_calls", []))

            # Store result for next step
            context[step["task"]] = result["content"]

        # Final result is from last step
        return {
            "content": context[steps[-1]["task"]],
            "model": f"chain:{chain_type}",
            "tool_calls": all_tool_calls,
            "input_tokens": total_input,
            "output_tokens": total_output,
        }

    def _is_reversible_action(self, tool_name: str) -> bool:
        """Determine if a tool action is reversible."""
        reversible_tools = {
            "create_calendar_event",
            "update_calendar_event",
            "delete_calendar_event",
            "create_reminder",
            "complete_reminder",
            "create_note",
            "create_project",
            "create_follow_up",
            "save_for_later",
            "update_user_preference",
        }
        return tool_name in reversible_tools

    async def stream_message(
        self,
        message: str,
        conversation_id: Optional[UUID] = None,
        source: str = "web",
    ) -> AsyncGenerator[str, None]:
        """
        Stream a response for real-time display.
        Yields chunks of the response as they're generated.
        """
        conversation = await self.get_or_create_conversation(conversation_id, source)
        await self.save_message(conversation.id, "user", message)
        history = await self.get_conversation_history(conversation.id)

        selected_model = self.model_router.select_model(
            message=message,
            conversation_history=history,
        )

        system_prompt = await self._build_system_prompt(message)
        full_response = ""

        async with self.client.messages.stream(
            model=selected_model.value,
            max_tokens=4096,
            system=system_prompt,
            messages=history,
            tools=TOOLS,
        ) as stream:
            async for text in stream.text_stream:
                full_response += text
                yield text

        # Save the complete response
        message_obj = await stream.get_final_message()
        await self.save_message(
            conversation_id=conversation.id,
            role="assistant",
            content=full_response,
            model_used=selected_model.value,
        )

        await self.cost_tracker.record_usage(
            tier=selected_model,
            input_tokens=message_obj.usage.input_tokens,
            output_tokens=message_obj.usage.output_tokens,
            task_type="chat_stream",
        )

    async def generate_daily_briefing(self, briefing_date: date = None) -> Dict[str, Any]:
        """Generate daily briefing with calendar, weather, priorities, and emails."""
        if briefing_date is None:
            briefing_date = date.today()

        # Use tool executor to gather data
        calendar_data = await self.tool_executor.execute(
            "get_calendar_events",
            {
                "start_date": briefing_date.isoformat(),
                "end_date": briefing_date.isoformat(),
            }
        )

        reminders = await self.tool_executor.execute(
            "get_reminders",
            {"include_completed": False}
        )

        follow_ups = await self.tool_executor.execute(
            "get_pending_follow_ups",
            {"overdue_only": False}
        )

        weather = await self.tool_executor.execute(
            "get_weather",
            {"location": "current", "days": 1}
        )

        # Get schedule-aware email summary
        email_data = await self._get_briefing_emails()

        # Get relevant user knowledge for personalization
        knowledge_context = await self._get_relevant_knowledge_context(
            "daily briefing schedule reminders priorities"
        )

        # Generate briefing with Claude
        briefing_prompt = f"""Generate a concise daily briefing for {briefing_date.strftime('%A, %B %d, %Y')}.

{knowledge_context}

Calendar events: {json.dumps(calendar_data)}
Pending reminders: {json.dumps(reminders)}
Follow-ups waiting: {json.dumps(follow_ups)}
Weather: {json.dumps(weather)}
Email summary: {json.dumps(email_data)}

Provide:
1. A brief summary of the day
2. Key events and times
3. Top priorities (from reminders, grouped by project if applicable)
4. Any follow-ups that need attention
5. Email highlights (if any important emails)
6. Weather-appropriate suggestions

Keep it concise and actionable. Use any known user preferences to personalize the briefing."""

        response = await self.client.messages.create(
            model=ModelTier.HAIKU.value,
            max_tokens=1024,
            messages=[{"role": "user", "content": briefing_prompt}],
        )

        await self.cost_tracker.record_usage(
            tier=ModelTier.HAIKU,
            input_tokens=response.usage.input_tokens,
            output_tokens=response.usage.output_tokens,
            task_type="briefing",
        )

        return {
            "summary": response.content[0].text,
            "events": calendar_data,
            "reminders": reminders,
            "follow_ups": follow_ups,
            "weather": weather,
            "emails": email_data,
        }

    async def _get_briefing_emails(self) -> Dict[str, Any]:
        """Get schedule-aware emails for briefing."""
        try:
            from app.services.email import EmailService
            email_service = EmailService(self.db, self.user_id)
            return await email_service.get_briefing_emails()
        except Exception as e:
            return {"error": str(e), "note": "Email briefing not available"}

    async def generate_weekly_review(self, week_start: date = None) -> Dict[str, Any]:
        """Generate weekly review with accomplishments and patterns."""
        if week_start is None:
            today = date.today()
            week_start = today - timedelta(days=today.weekday())

        week_end = week_start + timedelta(days=6)

        # Gather week's data
        calendar_data = await self.tool_executor.execute(
            "get_calendar_events",
            {
                "start_date": week_start.isoformat(),
                "end_date": week_end.isoformat(),
            }
        )

        # Get activity log for the week
        result = await self.db.execute(
            select(ActivityLog).where(
                and_(
                    ActivityLog.user_id == self.user_id,
                    ActivityLog.created_at >= week_start,
                    ActivityLog.created_at <= week_end + timedelta(days=1),
                )
            )
        )
        activities = result.scalars().all()

        activity_summary = [
            {"type": a.action_type, "data": a.action_data}
            for a in activities[:100]  # Limit for context
        ]

        # Generate review with Claude
        review_prompt = f"""Generate a weekly review for the week of {week_start.strftime('%B %d')} - {week_end.strftime('%B %d, %Y')}.

Calendar events: {json.dumps(calendar_data)}
Activity log (sample): {json.dumps(activity_summary)}

Provide:
1. Key accomplishments
2. Meeting patterns (too many? well-distributed?)
3. Areas that got attention vs. neglected
4. Suggestions for the coming week
5. Any patterns worth noting

Be insightful and actionable."""

        response = await self.client.messages.create(
            model=ModelTier.SONNET.value,
            max_tokens=2048,
            messages=[{"role": "user", "content": review_prompt}],
        )

        await self.cost_tracker.record_usage(
            tier=ModelTier.SONNET,
            input_tokens=response.usage.input_tokens,
            output_tokens=response.usage.output_tokens,
            task_type="weekly_review",
        )

        return {
            "review": response.content[0].text,
            "week_start": week_start.isoformat(),
            "week_end": week_end.isoformat(),
            "events_count": len(calendar_data) if isinstance(calendar_data, list) else 0,
            "activities_count": len(activities),
        }
