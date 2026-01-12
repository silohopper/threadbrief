"""In-memory storage used for the demo API."""

from typing import Dict, Optional
from app.models import Brief


class MemoryStore:
    """Simple in-memory store for briefs and per-IP rate counts."""

    def __init__(self) -> None:
        """Initialize empty brief and rate maps."""
        self.briefs: Dict[str, Brief] = {}
        self.rate: Dict[str, Dict[str, int]] = {}  # ip -> day_key -> count

    def save_brief(self, brief: Brief) -> None:
        """Persist a brief by id in memory."""
        self.briefs[brief.id] = brief

    def get_brief(self, brief_id: str) -> Optional[Brief]:
        """Fetch a brief by id if it exists."""
        return self.briefs.get(brief_id)

    def bump_rate(self, ip: str, day_key: str) -> int:
        """Increment and return the request count for an IP/day."""
        if ip not in self.rate:
            self.rate[ip] = {}
        self.rate[ip][day_key] = self.rate[ip].get(day_key, 0) + 1
        return self.rate[ip][day_key]

    def get_rate(self, ip: str, day_key: str) -> int:
        """Return current request count for an IP/day."""
        return self.rate.get(ip, {}).get(day_key, 0)


memory_store = MemoryStore()
