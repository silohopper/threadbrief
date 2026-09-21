"""Storage backends for briefs and per-IP rate limits."""

import time
from typing import Dict, Optional, Protocol
from app.models import Brief
from app.settings import settings

BRIEF_TTL_SECONDS = 60 * 60 * 24 * 30  # 30 days
RATE_TTL_SECONDS = 60 * 60 * 48  # 2 days


class Store(Protocol):
    """Interface shared by all storage backends."""

    def save_brief(self, brief: Brief) -> None: ...
    def get_brief(self, brief_id: str) -> Optional[Brief]: ...
    def bump_rate(self, ip: str, day_key: str) -> int: ...
    def get_rate(self, ip: str, day_key: str) -> int: ...


class MemoryStore:
    """In-process store. Only correct with a single, long-running worker."""

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
        bucket = self.rate.setdefault(ip, {})
        bucket[day_key] = bucket.get(day_key, 0) + 1
        return bucket[day_key]

    def get_rate(self, ip: str, day_key: str) -> int:
        """Return current request count for an IP/day."""
        return self.rate.get(ip, {}).get(day_key, 0)


class DynamoStore:
    """DynamoDB-backed store, shared across Lambda instances.

    Single table keyed by `pk`: briefs use `BRIEF#{id}`, rate counters use
    `RATE#{ip}#{day_key}`. Both item types carry a `ttl` attribute so DynamoDB
    expires them automatically instead of growing the table forever.
    """

    def __init__(self, table_name: str) -> None:
        import boto3

        self._table = boto3.resource("dynamodb").Table(table_name)

    def save_brief(self, brief: Brief) -> None:
        """Persist a brief, expiring it after BRIEF_TTL_SECONDS."""
        self._table.put_item(
            Item={
                "pk": f"BRIEF#{brief.id}",
                "data": brief.model_dump_json(),
                "ttl": int(time.time()) + BRIEF_TTL_SECONDS,
            }
        )

    def get_brief(self, brief_id: str) -> Optional[Brief]:
        """Fetch a brief by id if it exists and hasn't expired."""
        resp = self._table.get_item(Key={"pk": f"BRIEF#{brief_id}"})
        item = resp.get("Item")
        if not item:
            return None
        return Brief.model_validate_json(item["data"])

    def bump_rate(self, ip: str, day_key: str) -> int:
        """Atomically increment and return the request count for an IP/day."""
        resp = self._table.update_item(
            Key={"pk": f"RATE#{ip}#{day_key}"},
            UpdateExpression="SET #c = if_not_exists(#c, :zero) + :incr, #ttl = if_not_exists(#ttl, :ttl)",
            ExpressionAttributeNames={"#c": "count", "#ttl": "ttl"},
            ExpressionAttributeValues={
                ":zero": 0,
                ":incr": 1,
                ":ttl": int(time.time()) + RATE_TTL_SECONDS,
            },
            ReturnValues="UPDATED_NEW",
        )
        return int(resp["Attributes"]["count"])

    def get_rate(self, ip: str, day_key: str) -> int:
        """Return current request count for an IP/day."""
        resp = self._table.get_item(Key={"pk": f"RATE#{ip}#{day_key}"})
        item = resp.get("Item")
        return int(item["count"]) if item else 0


def _build_store() -> Store:
    """Select the storage backend based on settings.storage_backend."""
    if settings.storage_backend == "dynamodb":
        if not settings.dynamodb_table:
            raise RuntimeError("DYNAMODB_TABLE must be set when STORAGE_BACKEND=dynamodb.")
        return DynamoStore(settings.dynamodb_table)
    return MemoryStore()


store = _build_store()
