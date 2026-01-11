"""
ToolExecutor - Executes Claude tool calls against real services.
"""
import json
from datetime import datetime, date, timedelta
from typing import Dict, Any, Optional
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_

from app.models.note import Note
from app.models.project import Project
from app.models.meeting import Meeting
from app.models.follow_up import FollowUp
from app.models.read_later import ReadLater
from app.models.preferences import Preference
from app.models.activity import ActivityLog


class ToolExecutor:
    """
    Executes tool calls made by Claude.
    Routes each tool to the appropriate service or database operation.
    """

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id
        self._services = {}
        self._user_latitude: Optional[float] = None
        self._user_longitude: Optional[float] = None

    def set_user_location(self, latitude: float, longitude: float):
        """Set the user's current location for location-based services."""
        self._user_latitude = latitude
        self._user_longitude = longitude

    async def execute(self, tool_name: str, tool_input: Dict[str, Any]) -> Any:
        """
        Execute a tool call and return the result.

        Args:
            tool_name: Name of the tool to execute
            tool_input: Input parameters for the tool

        Returns:
            Result of the tool execution
        """
        # Route to appropriate handler
        handler = getattr(self, f"_execute_{tool_name}", None)
        if handler:
            return await handler(tool_input)

        return {"error": f"Unknown tool: {tool_name}"}

    # Calendar Tools
    async def _execute_get_calendar_events(self, input: Dict) -> Any:
        """Get calendar events for a date range."""
        try:
            from app.services.calendar import CalendarService
            service = await self._get_service("calendar", CalendarService)
            return await service.get_events(
                start_date=input["start_date"],
                end_date=input["end_date"],
            )
        except Exception as e:
            return {"error": str(e), "events": []}

    async def _execute_create_calendar_event(self, input: Dict) -> Any:
        """Create a new calendar event."""
        try:
            from app.services.calendar import CalendarService
            service = await self._get_service("calendar", CalendarService)
            return await service.create_event(
                title=input["title"],
                start=input["start"],
                end=input["end"],
                location=input.get("location"),
                description=input.get("description"),
                attendees=input.get("attendees", []),
            )
        except Exception as e:
            return {"error": str(e)}

    async def _execute_update_calendar_event(self, input: Dict) -> Any:
        """Update an existing calendar event."""
        try:
            from app.services.calendar import CalendarService
            service = await self._get_service("calendar", CalendarService)
            return await service.update_event(
                event_id=input["event_id"],
                updates=input["updates"],
            )
        except Exception as e:
            return {"error": str(e)}

    async def _execute_delete_calendar_event(self, input: Dict) -> Any:
        """Delete a calendar event."""
        try:
            from app.services.calendar import CalendarService
            service = await self._get_service("calendar", CalendarService)
            return await service.delete_event(event_id=input["event_id"])
        except Exception as e:
            return {"error": str(e)}

    async def _execute_propose_schedule_optimization(self, input: Dict) -> Any:
        """Analyze schedule and propose optimizations."""
        try:
            from app.services.optimizer import ScheduleOptimizer
            optimizer = ScheduleOptimizer(self.db, self.user_id)
            return await optimizer.analyze_and_propose(
                start_date=input["date_range_start"],
                end_date=input["date_range_end"],
                goal=input.get("optimization_goal", "efficiency"),
            )
        except Exception as e:
            return {"error": str(e), "proposals": []}

    # Reminder Tools
    async def _execute_get_reminders(self, input: Dict) -> Any:
        """Get reminders from synced Apple Reminders."""
        from app.models.synced_reminder import SyncedReminder
        from app.models.project import Project

        include_completed = input.get("include_completed", False)

        query = select(SyncedReminder).where(SyncedReminder.user_id == self.user_id)

        if not include_completed:
            query = query.where(SyncedReminder.is_completed == False)

        query = query.order_by(SyncedReminder.due_date.asc().nullslast())

        result = await self.db.execute(query)
        reminders = result.scalars().all()

        # Get project names for grouping
        project_ids = {r.project_id for r in reminders if r.project_id}
        projects = {}
        if project_ids:
            project_result = await self.db.execute(
                select(Project).where(Project.id.in_(project_ids))
            )
            projects = {p.id: p.name for p in project_result.scalars().all()}

        # Format reminders with project info
        formatted = []
        for r in reminders:
            formatted.append({
                "id": str(r.id),
                "title": r.title,
                "notes": r.notes,
                "due_date": r.due_date.isoformat() if r.due_date else None,
                "priority": r.priority,
                "is_completed": r.is_completed,
                "list_name": r.list_name,
                "project": projects.get(r.project_id) if r.project_id else None,
            })

        return {
            "reminders": formatted,
            "count": len(formatted),
        }

    async def _execute_create_reminder(self, input: Dict) -> Any:
        """Create a reminder (synced from iOS)."""
        # Note: Reminders are created via iOS app and synced to backend
        # This tool is for reference - actual creation happens on device
        return {
            "success": False,
            "note": "Reminders should be created in the iOS Reminders app and will sync automatically"
        }

    async def _execute_complete_reminder(self, input: Dict) -> Any:
        """Mark a synced reminder as complete."""
        from app.models.synced_reminder import SyncedReminder
        from datetime import datetime

        reminder_id = input.get("reminder_id")
        if not reminder_id:
            return {"success": False, "error": "reminder_id required"}

        result = await self.db.execute(
            select(SyncedReminder).where(
                SyncedReminder.id == reminder_id,
                SyncedReminder.user_id == self.user_id,
            )
        )
        reminder = result.scalar_one_or_none()

        if not reminder:
            return {"success": False, "error": "Reminder not found"}

        reminder.is_completed = True
        reminder.completed_at = datetime.utcnow()
        await self.db.commit()

        return {
            "success": True,
            "reminder_id": str(reminder.id),
            "title": reminder.title,
        }

    # Note Tools
    async def _execute_search_notes(self, input: Dict) -> Any:
        """Search through notes."""
        query = input["query"]
        project_id = input.get("project_id")
        tags = input.get("tags", [])

        stmt = select(Note).where(
            and_(
                Note.user_id == self.user_id,
                or_(
                    Note.title.ilike(f"%{query}%"),
                    Note.content.ilike(f"%{query}%"),
                )
            )
        )

        if project_id:
            stmt = stmt.where(Note.project_id == project_id)

        if tags:
            stmt = stmt.where(Note.tags.contains(tags))

        stmt = stmt.limit(20)
        result = await self.db.execute(stmt)
        notes = result.scalars().all()

        return {
            "notes": [
                {
                    "id": str(n.id),
                    "title": n.title,
                    "content": n.content[:200] + "..." if len(n.content) > 200 else n.content,
                    "tags": n.tags,
                    "created_at": n.created_at.isoformat(),
                }
                for n in notes
            ]
        }

    async def _execute_create_note(self, input: Dict) -> Any:
        """Create a new note."""
        note = Note(
            user_id=self.user_id,
            title=input.get("title", "Untitled"),
            content=input["content"],
            project_id=input.get("project_id"),
            tags=input.get("tags", []),
        )
        self.db.add(note)
        await self.db.commit()
        await self.db.refresh(note)

        return {
            "success": True,
            "note_id": str(note.id),
            "title": note.title,
        }

    async def _execute_get_note(self, input: Dict) -> Any:
        """Retrieve a specific note by ID."""
        result = await self.db.execute(
            select(Note).where(
                and_(
                    Note.id == input["note_id"],
                    Note.user_id == self.user_id,
                )
            )
        )
        note = result.scalar_one_or_none()

        if not note:
            return {"error": "Note not found"}

        return {
            "id": str(note.id),
            "title": note.title,
            "content": note.content,
            "tags": note.tags,
            "project_id": str(note.project_id) if note.project_id else None,
            "created_at": note.created_at.isoformat(),
            "updated_at": note.updated_at.isoformat() if note.updated_at else None,
        }

    # Email Tools
    async def _execute_get_email_inbox(self, input: Dict) -> Any:
        """Get recent emails from Gmail inbox."""
        try:
            from app.services.email import EmailService
            service = await self._get_service("email", EmailService)
            return await service.get_inbox(
                max_results=input.get("max_results", 20),
                unread_only=input.get("unread_only", False),
            )
        except Exception as e:
            return {"error": str(e), "emails": []}

    async def _execute_get_email_thread(self, input: Dict) -> Any:
        """Get full email thread."""
        try:
            from app.services.email import EmailService
            service = await self._get_service("email", EmailService)
            return await service.get_thread(thread_id=input["thread_id"])
        except Exception as e:
            return {"error": str(e)}

    async def _execute_draft_email_reply(self, input: Dict) -> Any:
        """Draft a reply to an email thread."""
        try:
            from app.services.email import EmailService
            service = await self._get_service("email", EmailService)
            return await service.create_draft(
                thread_id=input["thread_id"],
                content=input["reply_content"],
                tone=input.get("tone", "friendly"),
            )
        except Exception as e:
            return {"error": str(e)}

    async def _execute_triage_emails(self, input: Dict) -> Any:
        """Analyze inbox and categorize emails."""
        try:
            from app.services.email import EmailService
            service = await self._get_service("email", EmailService)
            return await service.triage(
                max_emails=input.get("max_emails", 50),
            )
        except Exception as e:
            return {"error": str(e)}

    # Meeting Tools
    async def _execute_get_meeting_summary(self, input: Dict) -> Any:
        """Get the summary of a past meeting."""
        meeting_id = input.get("meeting_id")
        calendar_event_id = input.get("calendar_event_id")

        stmt = select(Meeting).where(Meeting.user_id == self.user_id)

        if meeting_id:
            stmt = stmt.where(Meeting.id == meeting_id)
        elif calendar_event_id:
            stmt = stmt.where(Meeting.calendar_event_id == calendar_event_id)
        else:
            return {"error": "Either meeting_id or calendar_event_id required"}

        result = await self.db.execute(stmt)
        meeting = result.scalar_one_or_none()

        if not meeting or not meeting.summary:
            return {"error": "Meeting summary not found"}

        summary = meeting.summary
        return {
            "summary": summary.get("discussion", ""),
            "action_items": summary.get("action_items", []),
            "key_decisions": summary.get("key_points", []),
            "attendees": summary.get("attendees", []),
            "generated_at": meeting.created_at.isoformat(),
        }

    async def _execute_get_meeting_prep(self, input: Dict) -> Any:
        """Prepare briefing for an upcoming meeting."""
        calendar_event_id = input["calendar_event_id"]

        # Get meeting details from calendar
        from app.services.calendar import CalendarService
        try:
            service = await self._get_service("calendar", CalendarService)
            event = await service.get_event(calendar_event_id)
        except Exception:
            event = None

        # Find related notes
        if event and event.get("attendees"):
            attendee_names = [a.get("name", a.get("email", "")) for a in event["attendees"]]
            notes_query = " OR ".join(attendee_names)
            related_notes = await self._execute_search_notes({"query": notes_query})
        else:
            related_notes = {"notes": []}

        # Find past meetings with same attendees
        past_meetings = []  # Would query for past meetings

        return {
            "event": event,
            "related_notes": related_notes["notes"][:5],
            "past_meetings": past_meetings,
            "prep_notes": "Meeting prep generated",
        }

    # Project Tools
    async def _execute_get_project_status(self, input: Dict) -> Any:
        """Get comprehensive status of a project."""
        project_id = input.get("project_id")
        project_name = input.get("project_name")

        stmt = select(Project).where(Project.user_id == self.user_id)

        if project_id:
            stmt = stmt.where(Project.id == project_id)
        elif project_name:
            stmt = stmt.where(Project.name.ilike(f"%{project_name}%"))
        else:
            return {"error": "Either project_id or project_name required"}

        result = await self.db.execute(stmt)
        project = result.scalar_one_or_none()

        if not project:
            return {"error": "Project not found"}

        # Get related notes
        notes_result = await self.db.execute(
            select(Note).where(Note.project_id == project.id).limit(10)
        )
        notes = notes_result.scalars().all()

        return {
            "id": str(project.id),
            "name": project.name,
            "description": project.description,
            "status": project.status,
            "notes": [{"id": str(n.id), "title": n.title} for n in notes],
            "created_at": project.created_at.isoformat(),
        }

    async def _execute_create_project(self, input: Dict) -> Any:
        """Create a new project."""
        project = Project(
            user_id=self.user_id,
            name=input["name"],
            description=input.get("description"),
        )
        self.db.add(project)
        await self.db.commit()
        await self.db.refresh(project)

        return {
            "success": True,
            "project_id": str(project.id),
            "name": project.name,
        }

    async def _execute_link_to_project(self, input: Dict) -> Any:
        """Link a note, meeting, or task to a project."""
        project_id = input["project_id"]
        item_type = input["item_type"]
        item_id = input["item_id"]

        if item_type == "note":
            result = await self.db.execute(
                select(Note).where(
                    and_(Note.id == item_id, Note.user_id == self.user_id)
                )
            )
            item = result.scalar_one_or_none()
            if item:
                item.project_id = project_id
                await self.db.commit()
                return {"success": True}
        elif item_type == "meeting":
            result = await self.db.execute(
                select(Meeting).where(
                    and_(Meeting.id == item_id, Meeting.user_id == self.user_id)
                )
            )
            item = result.scalar_one_or_none()
            if item:
                item.project_id = project_id
                await self.db.commit()
                return {"success": True}

        return {"error": f"Could not link {item_type} to project"}

    # Follow-up Tools
    async def _execute_get_pending_follow_ups(self, input: Dict) -> Any:
        """Get list of pending follow-ups."""
        stmt = select(FollowUp).where(
            and_(
                FollowUp.user_id == self.user_id,
                FollowUp.status == "waiting",
            )
        )

        if input.get("overdue_only"):
            stmt = stmt.where(FollowUp.follow_up_date < datetime.utcnow())

        stmt = stmt.order_by(FollowUp.follow_up_date)
        result = await self.db.execute(stmt)
        follow_ups = result.scalars().all()

        return {
            "follow_ups": [
                {
                    "id": str(f.id),
                    "contact_name": f.contact_name,
                    "contact_email": f.contact_email,
                    "context": f.context,
                    "follow_up_date": f.follow_up_date.isoformat() if f.follow_up_date else None,
                    "is_overdue": f.follow_up_date < datetime.utcnow() if f.follow_up_date else False,
                }
                for f in follow_ups
            ]
        }

    async def _execute_create_follow_up(self, input: Dict) -> Any:
        """Track that user is waiting on something from someone."""
        follow_up = FollowUp(
            user_id=self.user_id,
            contact_name=input["contact_name"],
            contact_email=input.get("contact_email"),
            context=input["context"],
            follow_up_date=datetime.fromisoformat(input["follow_up_date"]) if input.get("follow_up_date") else None,
        )
        self.db.add(follow_up)
        await self.db.commit()
        await self.db.refresh(follow_up)

        return {
            "success": True,
            "follow_up_id": str(follow_up.id),
        }

    async def _execute_draft_follow_up_nudge(self, input: Dict) -> Any:
        """Draft a polite follow-up email."""
        result = await self.db.execute(
            select(FollowUp).where(
                and_(
                    FollowUp.id == input["follow_up_id"],
                    FollowUp.user_id == self.user_id,
                )
            )
        )
        follow_up = result.scalar_one_or_none()

        if not follow_up:
            return {"error": "Follow-up not found"}

        # Generate a nudge email draft
        draft = f"""Hi {follow_up.contact_name},

I wanted to follow up on {follow_up.context}.

Would you have a chance to look into this when you get a moment?

Thanks!"""

        return {
            "draft": draft,
            "to": follow_up.contact_email,
            "context": follow_up.context,
        }

    # Read Later Tools
    async def _execute_save_for_later(self, input: Dict) -> Any:
        """Save a URL to read later."""
        item = ReadLater(
            user_id=self.user_id,
            url=input["url"],
            title=input.get("title"),
        )
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)

        return {
            "success": True,
            "item_id": str(item.id),
        }

    async def _execute_get_read_later_list(self, input: Dict) -> Any:
        """Get the read-later queue."""
        stmt = select(ReadLater).where(
            ReadLater.user_id == self.user_id
        )

        if input.get("unread_only", True):
            stmt = stmt.where(ReadLater.is_read == False)

        stmt = stmt.order_by(ReadLater.created_at.desc()).limit(50)
        result = await self.db.execute(stmt)
        items = result.scalars().all()

        return {
            "items": [
                {
                    "id": str(i.id),
                    "url": i.url,
                    "title": i.title,
                    "saved_at": i.created_at.isoformat(),
                    "read": i.is_read,
                }
                for i in items
            ]
        }

    # Location & Travel Tools
    async def _execute_get_travel_time(self, input: Dict) -> Any:
        """Get travel time between two locations."""
        try:
            from app.services.maps import MapsService
            service = await self._get_service("maps", MapsService)
            return await service.get_travel_time(
                origin=input["origin"],
                destination=input["destination"],
                departure_time=input.get("departure_time"),
            )
        except Exception as e:
            return {"error": str(e)}

    async def _execute_get_weather(self, input: Dict) -> Any:
        """Get weather forecast."""
        try:
            from app.services.weather import WeatherService
            service = await self._get_service("weather", WeatherService)

            location = input.get("location", "current")

            # If location is "current" and we have user coordinates, use them
            if location.lower() in ["current", "home"] and self._user_latitude and self._user_longitude:
                return await service.get_forecast_by_coordinates(
                    latitude=self._user_latitude,
                    longitude=self._user_longitude,
                    days=input.get("days", 1),
                )

            return await service.get_forecast(
                location=location,
                days=input.get("days", 1),
            )
        except Exception as e:
            return {"error": str(e), "forecast": None}

    # Preference Tools
    async def _execute_get_user_preferences(self, input: Dict) -> Any:
        """Get user preferences for a category."""
        category = input["category"]

        stmt = select(Preference).where(
            Preference.user_id == self.user_id
        )

        if category != "all":
            stmt = stmt.where(Preference.category == category)

        result = await self.db.execute(stmt)
        prefs = result.scalars().all()

        return {
            "preferences": {
                p.key: p.value for p in prefs
            }
        }

    async def _execute_update_user_preference(self, input: Dict) -> Any:
        """Update or learn a preference."""
        result = await self.db.execute(
            select(Preference).where(
                and_(
                    Preference.user_id == self.user_id,
                    Preference.category == input["category"],
                    Preference.key == input["key"],
                )
            )
        )
        pref = result.scalar_one_or_none()

        if pref:
            pref.value = input["value"]
            pref.learned = input.get("learned", False)
        else:
            pref = Preference(
                user_id=self.user_id,
                category=input["category"],
                key=input["key"],
                value=input["value"],
                learned=input.get("learned", False),
            )
            self.db.add(pref)

        await self.db.commit()
        return {"success": True}

    # Knowledge Tools
    async def _execute_get_relevant_knowledge(self, input: Dict) -> Any:
        """Get knowledge relevant to the current query."""
        from app.services.knowledge import KnowledgeService

        service = KnowledgeService(self.db, self.user_id)
        query = input["query"]
        categories = input.get("categories")
        max_results = input.get("max_results", 10)

        knowledge_items = await service.get_relevant_knowledge(
            query_text=query,
            max_results=max_results,
        )

        return {
            "knowledge": [
                {
                    "id": str(k.id),
                    "category": k.category,
                    "topic": k.topic,
                    "value": k.value,
                    "confidence": k.confidence,
                    "source": k.source,
                }
                for k in knowledge_items
            ],
            "count": len(knowledge_items),
        }

    async def _execute_learn_about_user(self, input: Dict) -> Any:
        """Store knowledge about the user."""
        from app.services.knowledge import KnowledgeService

        service = KnowledgeService(self.db, self.user_id)

        knowledge = await service.learn(
            category=input["category"],
            topic=input["topic"],
            value=input["value"],
            confidence=input.get("confidence", 0.8),
            source="explicit" if input.get("confidence", 0.8) >= 0.9 else "conversation",
        )

        return {
            "success": True,
            "knowledge_id": str(knowledge.id),
            "message": f"Remembered: {knowledge.topic} = {knowledge.value}",
        }

    async def _execute_get_knowledge_summary(self, input: Dict) -> Any:
        """Get a summary of all stored knowledge."""
        from app.services.knowledge import KnowledgeService

        service = KnowledgeService(self.db, self.user_id)
        summary = await service.get_knowledge_summary()

        # Also get all knowledge items for display
        all_knowledge = await service.get_all_knowledge()

        # Group by category
        by_category = {}
        for k in all_knowledge:
            if k.category not in by_category:
                by_category[k.category] = []
            by_category[k.category].append({
                "id": str(k.id),
                "topic": k.topic,
                "value": k.value,
                "confidence": k.confidence,
            })

        return {
            "summary": summary,
            "knowledge_by_category": by_category,
        }

    async def _execute_forget_knowledge(self, input: Dict) -> Any:
        """Remove a piece of stored knowledge."""
        from app.services.knowledge import KnowledgeService
        from uuid import UUID as PyUUID

        service = KnowledgeService(self.db, self.user_id)

        try:
            knowledge_id = PyUUID(input["knowledge_id"])
        except ValueError:
            return {"success": False, "error": "Invalid knowledge ID"}

        success = await service.forget(knowledge_id)

        if success:
            return {"success": True, "message": "Knowledge item forgotten"}
        return {"success": False, "error": "Knowledge item not found"}

    # Notification Tools
    async def _execute_send_push_notification(self, input: Dict) -> Any:
        """Send a push notification."""
        try:
            from app.services.notifications import PushNotificationService
            from app.config import settings

            if not settings.apns_cert_path:
                return {"error": "Push notifications not configured"}

            service = PushNotificationService(
                cert_path=settings.apns_cert_path,
                bundle_id=settings.apns_bundle_id,
            )

            await service.send_notification(
                user_id=str(self.user_id),
                title=input["title"],
                body=input["body"],
                category=input.get("category", "info"),
                db=self.db,
            )

            return {"success": True}
        except Exception as e:
            return {"error": str(e)}

    # Briefing Tools
    async def _execute_generate_daily_briefing(self, input: Dict) -> Any:
        """Generate the daily briefing."""
        from app.core.chat import ChatHandler

        handler = ChatHandler(self.db, self.user_id)
        briefing_date = date.fromisoformat(input["date"]) if input.get("date") else date.today()
        return await handler.generate_daily_briefing(briefing_date)

    async def _execute_generate_weekly_review(self, input: Dict) -> Any:
        """Generate weekly review."""
        from app.core.chat import ChatHandler

        handler = ChatHandler(self.db, self.user_id)
        week_start = date.fromisoformat(input["week_start"]) if input.get("week_start") else None
        return await handler.generate_weekly_review(week_start)

    # Meta Tools
    async def _execute_undo_last_action(self, input: Dict) -> Any:
        """Undo the most recent reversible action."""
        action_id = input.get("action_id")

        stmt = select(ActivityLog).where(
            and_(
                ActivityLog.user_id == self.user_id,
                ActivityLog.reversible == True,
                ActivityLog.reversed == False,
            )
        )

        if action_id:
            stmt = stmt.where(ActivityLog.id == action_id)

        stmt = stmt.order_by(ActivityLog.created_at.desc()).limit(1)
        result = await self.db.execute(stmt)
        activity = result.scalar_one_or_none()

        if not activity:
            return {"error": "No reversible action found"}

        # Mark as reversed
        activity.reversed = True
        await self.db.commit()

        # TODO: Actually reverse the action based on reverse_data
        return {
            "success": True,
            "undone_action": activity.action_type,
            "note": "Action marked as undone - actual reversal depends on action type",
        }

    async def _execute_explain_reasoning(self, input: Dict) -> Any:
        """Explain why Kai made a particular suggestion."""
        return {
            "context": input["context"],
            "explanation": "I made this suggestion based on your calendar patterns, stated preferences, and past interactions.",
        }

    async def _execute_log_activity(self, input: Dict) -> Any:
        """Log an action to the activity log."""
        activity = ActivityLog(
            user_id=self.user_id,
            action_type=input["action_type"],
            action_data=input["action_data"],
            reversible=input.get("reversible", False),
        )
        self.db.add(activity)
        await self.db.commit()

        return {"success": True, "activity_id": str(activity.id)}

    # Helper methods
    async def _get_service(self, name: str, service_class):
        """Get or create a service instance."""
        if name not in self._services:
            self._services[name] = service_class(self.db, self.user_id)
        return self._services[name]
