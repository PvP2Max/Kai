"""
Maps service using Google Maps API for travel time and routing.
"""
import httpx
from typing import Optional, Dict, Any, List
from datetime import datetime
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings


class MapsService:
    """
    Google Maps API integration for travel time and directions.
    """

    BASE_URL = "https://maps.googleapis.com/maps/api"

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id
        self._saved_locations = {}

    async def _get_api_key(self) -> Optional[str]:
        """Get Google Maps API key from settings."""
        return settings.google_maps_api_key

    async def get_travel_time(
        self,
        origin: str,
        destination: str,
        departure_time: Optional[str] = None,
        mode: str = "driving",
    ) -> Dict[str, Any]:
        """
        Get travel time between two locations.

        Args:
            origin: Starting location (address or saved location name)
            destination: Ending location
            departure_time: ISO datetime for departure (defaults to now)
            mode: Travel mode (driving, walking, bicycling, transit)

        Returns:
            Travel time and route information
        """
        api_key = await self._get_api_key()

        if not api_key:
            # Fallback to estimation without API
            return await self._estimate_travel_time(origin, destination, mode)

        # Resolve saved location names
        origin = await self._resolve_location(origin)
        destination = await self._resolve_location(destination)

        # Parse departure time
        if departure_time:
            dt = datetime.fromisoformat(departure_time.replace("Z", "+00:00"))
            departure_timestamp = int(dt.timestamp())
        else:
            departure_timestamp = int(datetime.now().timestamp())

        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.BASE_URL}/distancematrix/json",
                params={
                    "origins": origin,
                    "destinations": destination,
                    "mode": mode,
                    "departure_time": departure_timestamp,
                    "traffic_model": "best_guess",
                    "key": api_key,
                },
            )

            if response.status_code != 200:
                return {"error": "Failed to fetch travel time"}

            data = response.json()

            if data.get("status") != "OK":
                return {"error": data.get("status")}

            rows = data.get("rows", [])
            if not rows or not rows[0].get("elements"):
                return {"error": "No route found"}

            element = rows[0]["elements"][0]

            if element.get("status") != "OK":
                return {"error": element.get("status")}

            result = {
                "origin": data.get("origin_addresses", [origin])[0],
                "destination": data.get("destination_addresses", [destination])[0],
                "distance": element.get("distance", {}).get("text"),
                "distance_meters": element.get("distance", {}).get("value"),
                "duration": element.get("duration", {}).get("text"),
                "duration_seconds": element.get("duration", {}).get("value"),
                "mode": mode,
            }

            # Include traffic info if available
            if "duration_in_traffic" in element:
                result["duration_in_traffic"] = element["duration_in_traffic"]["text"]
                result["duration_in_traffic_seconds"] = element["duration_in_traffic"]["value"]

            return result

    async def get_directions(
        self,
        origin: str,
        destination: str,
        departure_time: Optional[str] = None,
        mode: str = "driving",
        waypoints: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Get detailed directions between locations.

        Args:
            origin: Starting location
            destination: Ending location
            departure_time: ISO datetime for departure
            mode: Travel mode
            waypoints: Optional intermediate stops

        Returns:
            Detailed route with turn-by-turn directions
        """
        api_key = await self._get_api_key()

        if not api_key:
            return {"error": "Google Maps API not configured"}

        origin = await self._resolve_location(origin)
        destination = await self._resolve_location(destination)

        params = {
            "origin": origin,
            "destination": destination,
            "mode": mode,
            "key": api_key,
        }

        if departure_time:
            dt = datetime.fromisoformat(departure_time.replace("Z", "+00:00"))
            params["departure_time"] = int(dt.timestamp())

        if waypoints:
            resolved_waypoints = [
                await self._resolve_location(wp) for wp in waypoints
            ]
            params["waypoints"] = "|".join(resolved_waypoints)

        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.BASE_URL}/directions/json",
                params=params,
            )

            if response.status_code != 200:
                return {"error": "Failed to fetch directions"}

            data = response.json()

            if data.get("status") != "OK":
                return {"error": data.get("status")}

            routes = data.get("routes", [])
            if not routes:
                return {"error": "No route found"}

            route = routes[0]
            legs = route.get("legs", [])

            total_distance = sum(leg.get("distance", {}).get("value", 0) for leg in legs)
            total_duration = sum(leg.get("duration", {}).get("value", 0) for leg in legs)

            steps = []
            for leg in legs:
                for step in leg.get("steps", []):
                    steps.append({
                        "instruction": step.get("html_instructions", ""),
                        "distance": step.get("distance", {}).get("text"),
                        "duration": step.get("duration", {}).get("text"),
                        "travel_mode": step.get("travel_mode"),
                    })

            return {
                "origin": legs[0].get("start_address") if legs else origin,
                "destination": legs[-1].get("end_address") if legs else destination,
                "total_distance": f"{total_distance / 1000:.1f} km",
                "total_distance_meters": total_distance,
                "total_duration": f"{total_duration // 60} min",
                "total_duration_seconds": total_duration,
                "steps": steps,
                "polyline": route.get("overview_polyline", {}).get("points"),
            }

    async def search_places(
        self,
        query: str,
        location: Optional[str] = None,
        radius: int = 5000,
    ) -> Dict[str, Any]:
        """
        Search for places near a location.

        Args:
            query: Search query (e.g., "coffee shop")
            location: Center point for search
            radius: Search radius in meters

        Returns:
            List of matching places
        """
        api_key = await self._get_api_key()

        if not api_key:
            return {"error": "Google Maps API not configured"}

        params = {
            "query": query,
            "key": api_key,
        }

        if location:
            # First geocode the location
            coords = await self._geocode(location)
            if coords:
                params["location"] = f"{coords['lat']},{coords['lng']}"
                params["radius"] = radius

        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.BASE_URL}/place/textsearch/json",
                params=params,
            )

            if response.status_code != 200:
                return {"error": "Failed to search places"}

            data = response.json()

            if data.get("status") != "OK":
                return {"error": data.get("status"), "places": []}

            places = []
            for result in data.get("results", [])[:10]:
                places.append({
                    "name": result.get("name"),
                    "address": result.get("formatted_address"),
                    "rating": result.get("rating"),
                    "price_level": result.get("price_level"),
                    "place_id": result.get("place_id"),
                    "types": result.get("types", []),
                    "open_now": result.get("opening_hours", {}).get("open_now"),
                })

            return {"places": places}

    async def _resolve_location(self, location: str) -> str:
        """Resolve saved location names to addresses."""
        # Check if it's a saved location
        saved = {
            "home": "123 Main St, San Francisco, CA",  # Placeholder
            "work": "456 Office Ave, San Francisco, CA",  # Placeholder
        }

        return saved.get(location.lower(), location)

    async def _geocode(self, address: str) -> Optional[Dict[str, float]]:
        """Geocode an address to coordinates."""
        api_key = await self._get_api_key()

        if not api_key:
            return None

        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.BASE_URL}/geocode/json",
                params={
                    "address": address,
                    "key": api_key,
                },
            )

            if response.status_code != 200:
                return None

            data = response.json()

            if data.get("status") != "OK":
                return None

            results = data.get("results", [])
            if not results:
                return None

            location = results[0].get("geometry", {}).get("location", {})
            return {
                "lat": location.get("lat"),
                "lng": location.get("lng"),
            }

    async def _estimate_travel_time(
        self,
        origin: str,
        destination: str,
        mode: str,
    ) -> Dict[str, Any]:
        """
        Estimate travel time without API (very rough estimate).
        Used as fallback when API is not configured.
        """
        # Very rough estimates based on mode
        # In reality, this would need actual distance calculation
        estimates = {
            "driving": {"speed": 30, "unit": "mph"},  # Average urban speed
            "walking": {"speed": 3, "unit": "mph"},
            "bicycling": {"speed": 12, "unit": "mph"},
            "transit": {"speed": 20, "unit": "mph"},
        }

        mode_info = estimates.get(mode, estimates["driving"])

        return {
            "origin": origin,
            "destination": destination,
            "mode": mode,
            "estimated": True,
            "note": "Exact travel time unavailable. Configure Google Maps API for accurate estimates.",
            "average_speed": f"{mode_info['speed']} {mode_info['unit']}",
        }
