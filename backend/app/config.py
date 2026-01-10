"""
Application configuration loaded from environment variables.
"""
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql+asyncpg://kai:kai_dev_password@localhost:5432/kai"
    database_url_sync: str = "postgresql://kai:kai_dev_password@localhost:5432/kai"

    # Claude API
    anthropic_api_key: str = ""

    # JWT Authentication
    jwt_secret: str = "your-super-secret-jwt-key-change-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24  # 24 hours
    refresh_token_expire_days: int = 30

    # Apple Calendar (CalDAV)
    caldav_url: Optional[str] = None
    caldav_username: Optional[str] = None
    caldav_password: Optional[str] = None

    # Gmail API
    google_client_id: Optional[str] = None
    google_client_secret: Optional[str] = None
    google_refresh_token: Optional[str] = None

    # Google Maps
    google_maps_api_key: Optional[str] = None

    # Apple Push Notifications
    apns_cert_path: Optional[str] = None
    apns_bundle_id: Optional[str] = None

    # Whisper
    whisper_device: str = "cpu"  # or "cuda" for GPU
    whisper_model: str = "large-v3"

    # Server
    host: str = "0.0.0.0"
    port: int = 8000
    debug: bool = False

    # Audio storage
    audio_upload_dir: str = "/app/audio"

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
