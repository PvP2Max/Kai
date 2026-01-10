"""
Preference learning service for adapting to user patterns.
"""
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List
from uuid import UUID
import json

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_

from app.models.activity import ActivityLog
from app.models.preferences import UserPreference
from app.models.conversation import Message


class LearningService:
    """
    Learns user preferences from behavior patterns.
    Analyzes activity logs to infer preferences and habits.
    """

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id

    async def analyze_patterns(
        self,
        days: int = 30,
    ) -> Dict[str, Any]:
        """
        Analyze user patterns from the last N days.

        Args:
            days: Number of days to analyze

        Returns:
            Discovered patterns and insights
        """
        since = datetime.utcnow() - timedelta(days=days)

        # Get activity logs
        result = await self.db.execute(
            select(ActivityLog).where(
                and_(
                    ActivityLog.user_id == self.user_id,
                    ActivityLog.created_at >= since,
                )
            ).order_by(ActivityLog.created_at)
        )
        activities = result.scalars().all()

        patterns = {
            "scheduling": await self._analyze_scheduling_patterns(activities),
            "communication": await self._analyze_communication_patterns(activities),
            "productivity": await self._analyze_productivity_patterns(activities),
            "preferences": await self._extract_explicit_preferences(activities),
        }

        return patterns

    async def _analyze_scheduling_patterns(
        self,
        activities: List[ActivityLog],
    ) -> Dict[str, Any]:
        """Analyze scheduling-related patterns."""
        calendar_actions = [
            a for a in activities
            if a.action_type.startswith("tool:") and "calendar" in a.action_type
        ]

        # Analyze preferred meeting times
        meeting_hours = []
        for action in calendar_actions:
            if "create_calendar_event" in action.action_type:
                data = action.action_data or {}
                start = data.get("input", {}).get("start")
                if start:
                    try:
                        dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
                        meeting_hours.append(dt.hour)
                    except Exception:
                        pass

        # Calculate preferred hours
        preferred_hours = {}
        if meeting_hours:
            for hour in meeting_hours:
                preferred_hours[hour] = preferred_hours.get(hour, 0) + 1

        # Find peak hours
        peak_hours = sorted(
            preferred_hours.items(),
            key=lambda x: x[1],
            reverse=True,
        )[:3]

        return {
            "total_calendar_actions": len(calendar_actions),
            "preferred_meeting_hours": [h[0] for h in peak_hours],
            "hour_distribution": preferred_hours,
        }

    async def _analyze_communication_patterns(
        self,
        activities: List[ActivityLog],
    ) -> Dict[str, Any]:
        """Analyze communication patterns."""
        email_actions = [
            a for a in activities
            if a.action_type.startswith("tool:") and "email" in a.action_type
        ]

        # Analyze response patterns
        drafts = [
            a for a in email_actions
            if "draft" in a.action_type
        ]

        tones = []
        for draft in drafts:
            data = draft.action_data or {}
            tone = data.get("input", {}).get("tone")
            if tone:
                tones.append(tone)

        preferred_tone = None
        if tones:
            tone_counts = {}
            for t in tones:
                tone_counts[t] = tone_counts.get(t, 0) + 1
            preferred_tone = max(tone_counts.items(), key=lambda x: x[1])[0]

        return {
            "total_email_actions": len(email_actions),
            "drafts_created": len(drafts),
            "preferred_tone": preferred_tone,
        }

    async def _analyze_productivity_patterns(
        self,
        activities: List[ActivityLog],
    ) -> Dict[str, Any]:
        """Analyze productivity patterns."""
        # Analyze activity by hour of day
        hour_activity = {}
        for activity in activities:
            hour = activity.created_at.hour
            hour_activity[hour] = hour_activity.get(hour, 0) + 1

        # Find most productive hours
        peak_hours = sorted(
            hour_activity.items(),
            key=lambda x: x[1],
            reverse=True,
        )[:3]

        # Analyze activity by day of week
        day_activity = {}
        for activity in activities:
            day = activity.created_at.strftime("%A")
            day_activity[day] = day_activity.get(day, 0) + 1

        return {
            "most_active_hours": [h[0] for h in peak_hours],
            "activity_by_day": day_activity,
            "total_activities": len(activities),
        }

    async def _extract_explicit_preferences(
        self,
        activities: List[ActivityLog],
    ) -> Dict[str, Any]:
        """Extract explicitly stated preferences from conversations."""
        # Get recent messages looking for preference statements
        result = await self.db.execute(
            select(Message).where(
                Message.role == "user"
            ).order_by(Message.created_at.desc()).limit(100)
        )
        messages = result.scalars().all()

        # Look for preference indicators
        preference_keywords = [
            "prefer", "like", "don't like", "always", "never",
            "favorite", "hate", "love", "want", "need",
        ]

        preference_statements = []
        for msg in messages:
            content = msg.content.lower()
            for keyword in preference_keywords:
                if keyword in content:
                    preference_statements.append(msg.content)
                    break

        return {
            "explicit_statements": preference_statements[:10],
            "statement_count": len(preference_statements),
        }

    async def update_learned_preference(
        self,
        category: str,
        key: str,
        value: Any,
        confidence: float = 0.5,
    ) -> Dict[str, Any]:
        """
        Update or create a learned preference.

        Args:
            category: Preference category
            key: Preference key
            value: Preference value
            confidence: Confidence score (0-1)

        Returns:
            Update result
        """
        result = await self.db.execute(
            select(UserPreference).where(
                and_(
                    UserPreference.user_id == self.user_id,
                    UserPreference.category == category,
                    UserPreference.key == key,
                )
            )
        )
        pref = result.scalar_one_or_none()

        if pref:
            # Update existing preference
            # Only update if new confidence is higher
            if not pref.learned or confidence > pref.confidence:
                pref.value = value
                pref.confidence = confidence
                pref.learned = True
                await self.db.commit()
                return {"success": True, "action": "updated"}
            return {"success": True, "action": "skipped", "reason": "lower confidence"}
        else:
            # Create new learned preference
            pref = UserPreference(
                user_id=self.user_id,
                category=category,
                key=key,
                value=value,
                learned=True,
                confidence=confidence,
            )
            self.db.add(pref)
            await self.db.commit()
            return {"success": True, "action": "created"}

    async def get_recommendations(self) -> Dict[str, Any]:
        """
        Get personalized recommendations based on learned patterns.

        Returns:
            List of recommendations
        """
        patterns = await self.analyze_patterns()
        recommendations = []

        # Scheduling recommendations
        sched = patterns.get("scheduling", {})
        if sched.get("preferred_meeting_hours"):
            peak = sched["preferred_meeting_hours"][0]
            recommendations.append({
                "category": "scheduling",
                "recommendation": f"You seem most active around {peak}:00. Consider scheduling important meetings during this time.",
                "confidence": 0.7,
            })

        # Communication recommendations
        comm = patterns.get("communication", {})
        if comm.get("preferred_tone"):
            recommendations.append({
                "category": "communication",
                "recommendation": f"You prefer a {comm['preferred_tone']} tone in emails. I'll use this as the default.",
                "confidence": 0.8,
            })

        # Productivity recommendations
        prod = patterns.get("productivity", {})
        if prod.get("most_active_hours"):
            hours = prod["most_active_hours"]
            recommendations.append({
                "category": "productivity",
                "recommendation": f"Your peak productivity hours are around {hours[0]}:00 to {hours[-1]}:00.",
                "confidence": 0.6,
            })

        return {"recommendations": recommendations}

    async def run_learning_cycle(self) -> Dict[str, Any]:
        """
        Run a complete learning cycle to update preferences.

        Returns:
            Summary of learned preferences
        """
        patterns = await self.analyze_patterns()
        learned = []

        # Learn scheduling preferences
        sched = patterns.get("scheduling", {})
        if sched.get("preferred_meeting_hours"):
            result = await self.update_learned_preference(
                category="scheduling",
                key="preferred_meeting_hours",
                value=sched["preferred_meeting_hours"],
                confidence=0.7,
            )
            if result.get("action") in ["created", "updated"]:
                learned.append("preferred_meeting_hours")

        # Learn communication preferences
        comm = patterns.get("communication", {})
        if comm.get("preferred_tone"):
            result = await self.update_learned_preference(
                category="communication",
                key="default_email_tone",
                value=comm["preferred_tone"],
                confidence=0.8,
            )
            if result.get("action") in ["created", "updated"]:
                learned.append("default_email_tone")

        # Learn productivity preferences
        prod = patterns.get("productivity", {})
        if prod.get("most_active_hours"):
            result = await self.update_learned_preference(
                category="productivity",
                key="peak_hours",
                value=prod["most_active_hours"],
                confidence=0.6,
            )
            if result.get("action") in ["created", "updated"]:
                learned.append("peak_hours")

        return {
            "learned_preferences": learned,
            "patterns_analyzed": list(patterns.keys()),
        }
