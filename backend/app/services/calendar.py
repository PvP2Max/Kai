"""
Calendar service using CalDAV for Apple Calendar / iCloud integration.
"""
import caldav
from datetime import datetime, date, timedelta
from typing import Optional, List, Dict, Any
from uuid import UUID
import icalendar

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings


class CalendarService:
    """
    CalDAV calendar integration for iCloud/Apple Calendar.
    """

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id
        self._client = None
        self._calendar = None

    async def _get_client(self):
        """Get or create CalDAV client connection."""
        if self._client is None:
            if not settings.caldav_url:
                raise ValueError("CalDAV not configured")

            self._client = caldav.DAVClient(
                url=settings.caldav_url,
                username=settings.caldav_username,
                password=settings.caldav_password,
            )

        return self._client

    async def _get_calendar(self, calendar_name: Optional[str] = None):
        """Get the primary calendar or a named calendar."""
        client = await self._get_client()
        principal = client.principal()
        calendars = principal.calendars()

        if not calendars:
            raise ValueError("No calendars found")

        # Use provided name, or fall back to default from settings
        target_name = calendar_name or settings.default_calendar

        if target_name:
            for cal in calendars:
                if cal.name == target_name:
                    return cal
            raise ValueError(f"Calendar '{target_name}' not found")

        # Return first calendar (usually the primary)
        return calendars[0]

    async def get_events(
        self,
        start_date: str,
        end_date: str,
        calendar_name: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """
        Get calendar events for a date range.

        Args:
            start_date: ISO format start date
            end_date: ISO format end date
            calendar_name: Optional specific calendar name

        Returns:
            List of event dictionaries
        """
        try:
            calendar = await self._get_calendar(calendar_name)

            start = datetime.fromisoformat(start_date.replace("Z", "+00:00"))
            end = datetime.fromisoformat(end_date.replace("Z", "+00:00"))

            # Add time if only date provided
            if isinstance(start, date) and not isinstance(start, datetime):
                start = datetime.combine(start, datetime.min.time())
            if isinstance(end, date) and not isinstance(end, datetime):
                end = datetime.combine(end, datetime.max.time())

            events = calendar.date_search(start=start, end=end, expand=True)

            result = []
            for event in events:
                ical = icalendar.Calendar.from_ical(event.data)
                for component in ical.walk():
                    if component.name == "VEVENT":
                        result.append(self._parse_vevent(component, event.url))

            return sorted(result, key=lambda x: x.get("start", ""))

        except Exception as e:
            return {"error": str(e), "events": []}

    async def get_event(self, event_id: str) -> Optional[Dict[str, Any]]:
        """Get a single event by ID."""
        try:
            calendar = await self._get_calendar()
            event = calendar.event_by_url(event_id)

            if not event:
                return None

            ical = icalendar.Calendar.from_ical(event.data)
            for component in ical.walk():
                if component.name == "VEVENT":
                    return self._parse_vevent(component, event.url)

            return None
        except Exception:
            return None

    async def create_event(
        self,
        title: str,
        start: str,
        end: str,
        location: Optional[str] = None,
        description: Optional[str] = None,
        attendees: Optional[List[str]] = None,
        calendar_name: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Create a new calendar event.

        Args:
            title: Event title
            start: ISO datetime for start
            end: ISO datetime for end
            location: Optional location
            description: Optional description
            attendees: Optional list of attendee emails
            calendar_name: Optional calendar name

        Returns:
            Created event details
        """
        try:
            calendar = await self._get_calendar(calendar_name)

            # Build iCalendar event
            cal = icalendar.Calendar()
            cal.add("prodid", "-//Kai Personal Assistant//EN")
            cal.add("version", "2.0")

            event = icalendar.Event()
            event.add("summary", title)
            event.add("dtstart", datetime.fromisoformat(start.replace("Z", "+00:00")))
            event.add("dtend", datetime.fromisoformat(end.replace("Z", "+00:00")))

            if location:
                event.add("location", location)
            if description:
                event.add("description", description)
            if attendees:
                for attendee in attendees:
                    event.add("attendee", f"mailto:{attendee}")

            event.add("dtstamp", datetime.utcnow())

            cal.add_component(event)

            # Save to calendar
            created_event = calendar.save_event(cal.to_ical().decode())

            return {
                "success": True,
                "event_id": str(created_event.url),
                "title": title,
                "start": start,
                "end": end,
            }

        except Exception as e:
            return {"error": str(e), "success": False}

    async def update_event(
        self,
        event_id: str,
        updates: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Update an existing calendar event.

        Args:
            event_id: Event URL/ID
            updates: Dictionary of fields to update

        Returns:
            Updated event details
        """
        try:
            calendar = await self._get_calendar()
            event = calendar.event_by_url(event_id)

            if not event:
                return {"error": "Event not found", "success": False}

            ical = icalendar.Calendar.from_ical(event.data)

            for component in ical.walk():
                if component.name == "VEVENT":
                    if "title" in updates:
                        component["summary"] = updates["title"]
                    if "start" in updates:
                        component["dtstart"] = datetime.fromisoformat(
                            updates["start"].replace("Z", "+00:00")
                        )
                    if "end" in updates:
                        component["dtend"] = datetime.fromisoformat(
                            updates["end"].replace("Z", "+00:00")
                        )
                    if "location" in updates:
                        component["location"] = updates["location"]
                    if "description" in updates:
                        component["description"] = updates["description"]

            event.data = ical.to_ical()
            event.save()

            return {"success": True, "event_id": event_id}

        except Exception as e:
            return {"error": str(e), "success": False}

    async def delete_event(self, event_id: str) -> Dict[str, Any]:
        """Delete a calendar event."""
        try:
            calendar = await self._get_calendar()
            event = calendar.event_by_url(event_id)

            if not event:
                return {"error": "Event not found", "success": False}

            event.delete()
            return {"success": True}

        except Exception as e:
            return {"error": str(e), "success": False}

    def _parse_vevent(self, component, url) -> Dict[str, Any]:
        """Parse a VEVENT component into a dictionary."""
        def get_datetime(dt):
            if dt is None:
                return None
            if hasattr(dt, "dt"):
                dt = dt.dt
            if isinstance(dt, datetime):
                return dt.isoformat()
            if isinstance(dt, date):
                return dt.isoformat()
            return str(dt)

        attendees = []
        for attendee in component.get("attendee", []):
            if hasattr(attendee, "to_ical"):
                attendees.append(str(attendee).replace("mailto:", ""))
            else:
                attendees.append(str(attendee).replace("mailto:", ""))

        return {
            "id": str(url),
            "title": str(component.get("summary", "")),
            "start": get_datetime(component.get("dtstart")),
            "end": get_datetime(component.get("dtend")),
            "location": str(component.get("location", "")),
            "description": str(component.get("description", "")),
            "attendees": attendees,
            "all_day": not isinstance(
                component.get("dtstart").dt if component.get("dtstart") else None,
                datetime
            ),
        }

    async def get_free_busy(
        self,
        start_date: str,
        end_date: str,
    ) -> List[Dict[str, Any]]:
        """Get free/busy information for scheduling."""
        events = await self.get_events(start_date, end_date)

        if isinstance(events, dict) and "error" in events:
            return events

        busy_slots = []
        for event in events:
            busy_slots.append({
                "start": event["start"],
                "end": event["end"],
                "title": event["title"],
            })

        return {"busy_slots": busy_slots}
