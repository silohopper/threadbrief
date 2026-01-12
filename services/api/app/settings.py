"""Application configuration loaded from environment variables."""

from pydantic import BaseModel
import os


class Settings(BaseModel):
    """Typed settings with defaults for local development."""

    app_env: str = os.getenv("APP_ENV", "dev")
    cors_origins: str = os.getenv("CORS_ORIGINS", "http://localhost:3000")
    storage_backend: str = os.getenv("STORAGE_BACKEND", "memory")
    gemini_api_key: str | None = os.getenv("GEMINI_API_KEY")
    rate_limit_per_day: int = int(os.getenv("RATE_LIMIT_PER_DAY", "2"))

    @property
    def cors_origins_list(self) -> list[str]:
        """Return CORS origins as a list."""
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
