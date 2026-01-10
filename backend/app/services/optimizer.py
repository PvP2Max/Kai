"""
Schedule optimization service for intelligent calendar management.
"""
from datetime import datetime, date, timedelta
from typing import Optional, Dict, Any, List
from uuid import UUID
import json

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.models.preferences import Preference
from app.config import settings


class ScheduleOptimizer:
    """
    Analyzes calendar and proposes optimizations.
    Never modifies calendar directly - only proposes changes for user approval.
    """

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id

    async def analyze_and_propose(
        self,
        start_date: str,
        end_date: str,
        goal: str = "efficiency",
    ) -> Dict[str, Any]:
        """
        Analyze schedule and propose optimizations.

        Args:
            start_date: Start of date range to analyze
            end_date: End of date range to analyze
            goal: Optimization goal (efficiency, focus_time, balance)

        Returns:
            Analysis and proposed changes
        """
        from app.services.calendar import CalendarService

        # Get current events
        calendar = CalendarService(self.db, self.user_id)
        events = await calendar.get_events(start_date, end_date)

        if isinstance(events, dict) and "error" in events:
            return {"error": events["error"], "proposals": []}

        # Get user preferences
        preferences = await self._get_scheduling_preferences()

        # Analyze schedule
        analysis = await self._analyze_schedule(events, preferences)

        # Generate proposals based on goal
        if goal == "efficiency":
            proposals = await self._propose_efficiency_improvements(events, analysis, preferences)
        elif goal == "focus_time":
            proposals = await self._propose_focus_time(events, analysis, preferences)
        elif goal == "balance":
            proposals = await self._propose_balance(events, analysis, preferences)
        else:
            proposals = await self._propose_efficiency_improvements(events, analysis, preferences)

        return {
            "analysis": analysis,
            "proposals": proposals,
            "goal": goal,
            "date_range": {
                "start": start_date,
                "end": end_date,
            },
        }

    async def _get_scheduling_preferences(self) -> Dict[str, Any]:
        """Get user's scheduling preferences."""
        result = await self.db.execute(
            select(Preference).where(
                and_(
                    Preference.user_id == self.user_id,
                    Preference.category == "scheduling",
                )
            )
        )
        prefs = result.scalars().all()

        preferences = {
            "preferred_meeting_hours": [9, 10, 11, 14, 15, 16],  # Default
            "max_meetings_per_day": 6,
            "min_break_between_meetings": 15,  # minutes
            "focus_time_blocks": ["09:00-11:00", "14:00-16:00"],
            "avoid_back_to_back": True,
        }

        for pref in prefs:
            preferences[pref.key] = pref.value

        return preferences

    async def _analyze_schedule(
        self,
        events: List[Dict[str, Any]],
        preferences: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Analyze current schedule for issues and patterns."""
        analysis = {
            "total_events": len(events),
            "meetings_by_day": {},
            "back_to_back_count": 0,
            "fragmentation_score": 0,
            "focus_time_available": {},
            "issues": [],
        }

        # Group events by day
        events_by_day = {}
        for event in events:
            if event.get("start"):
                try:
                    dt = datetime.fromisoformat(event["start"].replace("Z", "+00:00"))
                    day = dt.date().isoformat()
                    if day not in events_by_day:
                        events_by_day[day] = []
                    events_by_day[day].append(event)
                except Exception:
                    pass

        # Analyze each day
        for day, day_events in events_by_day.items():
            analysis["meetings_by_day"][day] = len(day_events)

            # Check for back-to-back meetings
            sorted_events = sorted(
                day_events,
                key=lambda x: x.get("start", ""),
            )

            for i in range(len(sorted_events) - 1):
                current_end = sorted_events[i].get("end")
                next_start = sorted_events[i + 1].get("start")

                if current_end and next_start:
                    try:
                        end_dt = datetime.fromisoformat(current_end.replace("Z", "+00:00"))
                        start_dt = datetime.fromisoformat(next_start.replace("Z", "+00:00"))
                        gap = (start_dt - end_dt).total_seconds() / 60

                        if gap < preferences.get("min_break_between_meetings", 15):
                            analysis["back_to_back_count"] += 1
                            if preferences.get("avoid_back_to_back"):
                                analysis["issues"].append({
                                    "type": "back_to_back",
                                    "day": day,
                                    "events": [
                                        sorted_events[i].get("title"),
                                        sorted_events[i + 1].get("title"),
                                    ],
                                })
                    except Exception:
                        pass

            # Check if day is overloaded
            max_meetings = preferences.get("max_meetings_per_day", 6)
            if len(day_events) > max_meetings:
                analysis["issues"].append({
                    "type": "overloaded",
                    "day": day,
                    "meeting_count": len(day_events),
                    "max_allowed": max_meetings,
                })

            # Calculate focus time
            focus_blocks = preferences.get("focus_time_blocks", [])
            available_focus = self._calculate_focus_time(day_events, focus_blocks)
            analysis["focus_time_available"][day] = available_focus

        # Calculate fragmentation score (0-100, lower is better)
        if analysis["total_events"] > 0:
            fragmentation = (
                analysis["back_to_back_count"] / analysis["total_events"]
            ) * 100
            analysis["fragmentation_score"] = round(fragmentation, 1)

        return analysis

    def _calculate_focus_time(
        self,
        events: List[Dict[str, Any]],
        focus_blocks: List[str],
    ) -> int:
        """Calculate available focus time in minutes."""
        total_focus = 0

        for block in focus_blocks:
            try:
                start_str, end_str = block.split("-")
                block_start = datetime.strptime(start_str, "%H:%M")
                block_end = datetime.strptime(end_str, "%H:%M")
                block_minutes = (block_end - block_start).seconds // 60

                # Check for conflicts
                conflicts = 0
                for event in events:
                    event_start = event.get("start")
                    event_end = event.get("end")
                    if event_start and event_end:
                        try:
                            es = datetime.fromisoformat(event_start.replace("Z", "+00:00"))
                            ee = datetime.fromisoformat(event_end.replace("Z", "+00:00"))

                            # Simplified conflict check
                            if es.hour >= block_start.hour and es.hour < block_end.hour:
                                conflicts += (ee - es).seconds // 60
                        except Exception:
                            pass

                total_focus += max(0, block_minutes - conflicts)
            except Exception:
                pass

        return total_focus

    async def _propose_efficiency_improvements(
        self,
        events: List[Dict[str, Any]],
        analysis: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        """Generate efficiency improvement proposals."""
        proposals = []

        # Propose fixing back-to-back meetings
        for issue in analysis.get("issues", []):
            if issue["type"] == "back_to_back":
                proposals.append({
                    "type": "add_buffer",
                    "priority": "medium",
                    "description": f"Add 15-minute buffer between '{issue['events'][0]}' and '{issue['events'][1]}'",
                    "day": issue["day"],
                    "action": "reschedule",
                    "details": {
                        "events": issue["events"],
                        "suggested_buffer": 15,
                    },
                })

        # Propose batching similar meetings
        meeting_types = self._categorize_meetings(events)
        for category, category_events in meeting_types.items():
            if len(category_events) >= 3:
                proposals.append({
                    "type": "batch_meetings",
                    "priority": "low",
                    "description": f"Consider batching {len(category_events)} {category} meetings together",
                    "action": "reschedule",
                    "details": {
                        "category": category,
                        "meeting_count": len(category_events),
                    },
                })

        return proposals

    async def _propose_focus_time(
        self,
        events: List[Dict[str, Any]],
        analysis: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        """Generate proposals to increase focus time."""
        proposals = []

        for day, focus_minutes in analysis.get("focus_time_available", {}).items():
            if focus_minutes < 60:  # Less than 1 hour of focus time
                proposals.append({
                    "type": "protect_focus_time",
                    "priority": "high",
                    "description": f"Only {focus_minutes} minutes of focus time available on {day}",
                    "day": day,
                    "action": "reschedule",
                    "details": {
                        "current_focus_minutes": focus_minutes,
                        "target_focus_minutes": 120,
                        "suggestion": "Move non-essential meetings to create a 2-hour focus block",
                    },
                })

        return proposals

    async def _propose_balance(
        self,
        events: List[Dict[str, Any]],
        analysis: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        """Generate proposals for better work-life balance."""
        proposals = []

        # Check for overloaded days
        for issue in analysis.get("issues", []):
            if issue["type"] == "overloaded":
                proposals.append({
                    "type": "reduce_meetings",
                    "priority": "high",
                    "description": f"{issue['day']} has {issue['meeting_count']} meetings (max recommended: {issue['max_allowed']})",
                    "day": issue["day"],
                    "action": "reschedule",
                    "details": {
                        "current_count": issue["meeting_count"],
                        "max_recommended": issue["max_allowed"],
                        "suggestion": f"Consider moving {issue['meeting_count'] - issue['max_allowed']} meetings to another day",
                    },
                })

        # Check for early morning or late evening meetings
        for event in events:
            if event.get("start"):
                try:
                    dt = datetime.fromisoformat(event["start"].replace("Z", "+00:00"))
                    if dt.hour < 8 or dt.hour >= 18:
                        proposals.append({
                            "type": "work_hours",
                            "priority": "medium",
                            "description": f"'{event.get('title')}' is outside normal work hours",
                            "action": "consider_reschedule",
                            "details": {
                                "event": event.get("title"),
                                "time": event["start"],
                                "suggestion": "Consider moving to regular work hours if possible",
                            },
                        })
                except Exception:
                    pass

        return proposals

    def _categorize_meetings(
        self,
        events: List[Dict[str, Any]],
    ) -> Dict[str, List[Dict[str, Any]]]:
        """Categorize meetings by type based on title patterns."""
        categories = {
            "1:1": [],
            "team": [],
            "external": [],
            "recurring": [],
            "other": [],
        }

        for event in events:
            title = event.get("title", "").lower()

            if "1:1" in title or "one on one" in title or "1-1" in title:
                categories["1:1"].append(event)
            elif "team" in title or "standup" in title or "sync" in title:
                categories["team"].append(event)
            elif "external" in title or "client" in title or "customer" in title:
                categories["external"].append(event)
            else:
                categories["other"].append(event)

        return {k: v for k, v in categories.items() if v}

    async def find_optimal_slot(
        self,
        duration_minutes: int,
        date_range_start: str,
        date_range_end: str,
        attendees: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Find optimal time slot for a new meeting.

        Args:
            duration_minutes: Required meeting duration
            date_range_start: Start of search range
            date_range_end: End of search range
            attendees: Optional list of attendee emails

        Returns:
            Suggested time slots
        """
        from app.services.calendar import CalendarService

        calendar = CalendarService(self.db, self.user_id)
        events = await calendar.get_events(date_range_start, date_range_end)

        if isinstance(events, dict) and "error" in events:
            return {"error": events["error"], "slots": []}

        preferences = await self._get_scheduling_preferences()
        preferred_hours = preferences.get("preferred_meeting_hours", [9, 10, 11, 14, 15, 16])

        # Find free slots
        free_slots = []
        current_date = datetime.fromisoformat(date_range_start.replace("Z", "+00:00")).date()
        end_date = datetime.fromisoformat(date_range_end.replace("Z", "+00:00")).date()

        while current_date <= end_date:
            day_events = [
                e for e in events
                if e.get("start", "").startswith(current_date.isoformat())
            ]

            for hour in preferred_hours:
                slot_start = datetime.combine(current_date, datetime.min.time().replace(hour=hour))
                slot_end = slot_start + timedelta(minutes=duration_minutes)

                # Check if slot is free
                is_free = True
                for event in day_events:
                    try:
                        event_start = datetime.fromisoformat(event["start"].replace("Z", "+00:00"))
                        event_end = datetime.fromisoformat(event["end"].replace("Z", "+00:00"))

                        # Check for overlap
                        if not (slot_end <= event_start or slot_start >= event_end):
                            is_free = False
                            break
                    except Exception:
                        pass

                if is_free:
                    free_slots.append({
                        "start": slot_start.isoformat(),
                        "end": slot_end.isoformat(),
                        "score": self._score_slot(slot_start, preferences),
                    })

            current_date += timedelta(days=1)

        # Sort by score and return top 5
        free_slots.sort(key=lambda x: x["score"], reverse=True)

        return {
            "slots": free_slots[:5],
            "total_found": len(free_slots),
        }

    def _score_slot(
        self,
        slot_start: datetime,
        preferences: Dict[str, Any],
    ) -> float:
        """Score a time slot based on preferences."""
        score = 50.0  # Base score

        # Prefer preferred hours
        preferred_hours = preferences.get("preferred_meeting_hours", [])
        if slot_start.hour in preferred_hours:
            score += 20

        # Prefer mid-week
        if slot_start.weekday() in [1, 2, 3]:  # Tue, Wed, Thu
            score += 10

        # Avoid Monday morning and Friday afternoon
        if slot_start.weekday() == 0 and slot_start.hour < 11:
            score -= 15
        if slot_start.weekday() == 4 and slot_start.hour > 14:
            score -= 15

        return score
