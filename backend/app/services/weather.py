"""
Weather service using Open-Meteo API (free, no API key required).
"""
import httpx
from typing import Optional, Dict, Any
from datetime import datetime, date, timedelta
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession


class WeatherService:
    """
    Weather forecast using Open-Meteo API.
    Free service with no API key required.
    """

    BASE_URL = "https://api.open-meteo.com/v1"
    GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1"

    def __init__(self, db: AsyncSession, user_id: UUID):
        self.db = db
        self.user_id = user_id
        self._default_location = None

    async def get_coordinates(self, location: str) -> Optional[Dict[str, float]]:
        """
        Get coordinates for a location name.

        Args:
            location: City name or location string

        Returns:
            Dict with latitude and longitude, or None if not found
        """
        # Handle special location names
        if location.lower() in ["current", "home"]:
            # Use default location from preferences
            # For now, default to a placeholder
            return {"latitude": 37.7749, "longitude": -122.4194}  # San Francisco

        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.GEOCODING_URL}/search",
                params={"name": location, "count": 1},
            )

            if response.status_code == 200:
                data = response.json()
                results = data.get("results", [])
                if results:
                    return {
                        "latitude": results[0]["latitude"],
                        "longitude": results[0]["longitude"],
                        "name": results[0].get("name"),
                        "country": results[0].get("country"),
                    }

        return None

    async def get_forecast_by_coordinates(
        self,
        latitude: float,
        longitude: float,
        days: int = 1,
    ) -> Dict[str, Any]:
        """
        Get weather forecast using coordinates directly.

        Args:
            latitude: Latitude of the location
            longitude: Longitude of the location
            days: Number of forecast days (1-16)

        Returns:
            Weather forecast data
        """
        coords = {
            "latitude": latitude,
            "longitude": longitude,
            "name": "Current Location",
        }
        return await self._fetch_forecast(coords, days)

    async def get_forecast(
        self,
        location: str = "current",
        days: int = 1,
    ) -> Dict[str, Any]:
        """
        Get weather forecast for a location.

        Args:
            location: Location name or "current"
            days: Number of forecast days (1-16)

        Returns:
            Weather forecast data
        """
        coords = await self.get_coordinates(location)

        if not coords:
            return {"error": f"Location '{location}' not found"}

        return await self._fetch_forecast(coords, days)

    async def _fetch_forecast(
        self,
        coords: Dict[str, Any],
        days: int = 1,
    ) -> Dict[str, Any]:
        """
        Internal method to fetch forecast data from API.

        Args:
            coords: Dictionary with latitude, longitude, and optionally name/country
            days: Number of forecast days (1-16)

        Returns:
            Weather forecast data
        """

        days = min(max(1, days), 16)  # Clamp to 1-16

        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.BASE_URL}/forecast",
                params={
                    "latitude": coords["latitude"],
                    "longitude": coords["longitude"],
                    "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum,weathercode",
                    "hourly": "temperature_2m,precipitation_probability,weathercode",
                    "current_weather": True,
                    "temperature_unit": "fahrenheit",
                    "timezone": "auto",
                    "forecast_days": days,
                },
            )

            if response.status_code != 200:
                return {"error": "Failed to fetch weather data"}

            data = response.json()

            # Parse current weather
            current = data.get("current_weather", {})
            current_weather = {
                "temperature": current.get("temperature"),
                "feels_like": current.get("temperature"),  # Open-Meteo doesn't provide feels_like
                "condition": self._weather_code_to_condition(current.get("weathercode")),
                "wind_speed": current.get("windspeed"),
            }

            # Parse daily forecast
            daily = data.get("daily", {})
            daily_forecast = []

            dates = daily.get("time", [])
            max_temps = daily.get("temperature_2m_max", [])
            min_temps = daily.get("temperature_2m_min", [])
            precip = daily.get("precipitation_sum", [])
            codes = daily.get("weathercode", [])

            for i in range(len(dates)):
                daily_forecast.append({
                    "date": dates[i],
                    "high": max_temps[i] if i < len(max_temps) else None,
                    "low": min_temps[i] if i < len(min_temps) else None,
                    "precipitation": precip[i] if i < len(precip) else 0,
                    "condition": self._weather_code_to_condition(
                        codes[i] if i < len(codes) else 0
                    ),
                })

            # Parse hourly forecast for today
            hourly = data.get("hourly", {})
            hourly_forecast = []

            times = hourly.get("time", [])[:24]  # First 24 hours
            temps = hourly.get("temperature_2m", [])[:24]
            precip_prob = hourly.get("precipitation_probability", [])[:24]
            hourly_codes = hourly.get("weathercode", [])[:24]

            for i in range(len(times)):
                hourly_forecast.append({
                    "time": times[i],
                    "temperature": temps[i] if i < len(temps) else None,
                    "precipitation_probability": precip_prob[i] if i < len(precip_prob) else 0,
                    "condition": self._weather_code_to_condition(
                        hourly_codes[i] if i < len(hourly_codes) else 0
                    ),
                })

            return {
                "location": coords.get("name", "Unknown"),
                "country": coords.get("country"),
                "current": current_weather,
                "daily": daily_forecast,
                "hourly": hourly_forecast,
                "timezone": data.get("timezone"),
            }

    async def get_weather_for_event(
        self,
        location: str,
        event_datetime: datetime,
    ) -> Dict[str, Any]:
        """
        Get weather forecast for a specific event time.

        Args:
            location: Event location
            event_datetime: Event date and time

        Returns:
            Weather forecast for that specific time
        """
        now = datetime.now()
        days_ahead = (event_datetime.date() - now.date()).days

        if days_ahead < 0:
            return {"error": "Cannot get weather for past dates"}
        if days_ahead > 16:
            return {"error": "Forecast only available for next 16 days"}

        forecast = await self.get_forecast(location, days=days_ahead + 1)

        if "error" in forecast:
            return forecast

        # Find the specific day
        event_date_str = event_datetime.date().isoformat()

        for day in forecast.get("daily", []):
            if day["date"] == event_date_str:
                # Find closest hour
                event_hour = event_datetime.hour
                hourly = forecast.get("hourly", [])

                closest_hourly = None
                for h in hourly:
                    if h["time"].startswith(event_date_str):
                        hour = int(h["time"].split("T")[1].split(":")[0])
                        if abs(hour - event_hour) <= 1:
                            closest_hourly = h
                            break

                return {
                    "location": forecast["location"],
                    "date": event_date_str,
                    "daily": day,
                    "hourly": closest_hourly,
                    "summary": self._generate_summary(day, closest_hourly),
                }

        return {"error": "Could not find forecast for event date"}

    def _weather_code_to_condition(self, code: int) -> str:
        """Convert WMO weather code to human-readable condition."""
        conditions = {
            0: "Clear sky",
            1: "Mainly clear",
            2: "Partly cloudy",
            3: "Overcast",
            45: "Fog",
            48: "Rime fog",
            51: "Light drizzle",
            53: "Moderate drizzle",
            55: "Dense drizzle",
            56: "Light freezing drizzle",
            57: "Dense freezing drizzle",
            61: "Slight rain",
            63: "Moderate rain",
            65: "Heavy rain",
            66: "Light freezing rain",
            67: "Heavy freezing rain",
            71: "Slight snow",
            73: "Moderate snow",
            75: "Heavy snow",
            77: "Snow grains",
            80: "Slight rain showers",
            81: "Moderate rain showers",
            82: "Violent rain showers",
            85: "Slight snow showers",
            86: "Heavy snow showers",
            95: "Thunderstorm",
            96: "Thunderstorm with slight hail",
            99: "Thunderstorm with heavy hail",
        }
        return conditions.get(code, "Unknown")

    def _generate_summary(
        self,
        daily: Dict[str, Any],
        hourly: Optional[Dict[str, Any]],
    ) -> str:
        """Generate a natural language weather summary."""
        parts = []

        if hourly:
            parts.append(f"{hourly['condition']}, {hourly['temperature']}°F")
            if hourly.get("precipitation_probability", 0) > 30:
                parts.append(f"{hourly['precipitation_probability']}% chance of rain")
        else:
            parts.append(daily["condition"])
            parts.append(f"High of {daily['high']}°F, low of {daily['low']}°F")

        if daily.get("precipitation", 0) > 0:
            parts.append(f"{daily['precipitation']}mm precipitation expected")

        return ". ".join(parts)
