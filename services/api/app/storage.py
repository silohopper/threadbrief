import time
from typing import Dict, Optional
from app.models import Brief

class MemoryStore:
    def __init__(self) -> None:
        self.briefs: Dict[str, Brief] = {}
        self.rate: Dict[str, Dict[str, int]] = {}  # ip -> day_key -> count

    def save_brief(self, brief: Brief) -> None:
        self.briefs[brief.id] = brief

    def get_brief(self, brief_id: str) -> Optional[Brief]:
        return self.briefs.get(brief_id)

    def bump_rate(self, ip: str, day_key: str) -> int:
        if ip not in self.rate:
            self.rate[ip] = {}
        self.rate[ip][day_key] = self.rate[ip].get(day_key, 0) + 1
        return self.rate[ip][day_key]

    def get_rate(self, ip: str, day_key: str) -> int:
        return self.rate.get(ip, {}).get(day_key, 0)

memory_store = MemoryStore()
