"""Pydantic models and shared type aliases for the API."""

from pydantic import BaseModel, Field
from typing import Literal

SourceType = Literal["youtube", "paste"]
ModeType = Literal["insights", "summary"]
LengthType = Literal["tldr", "brief", "detailed"]


class CreateBriefRequest(BaseModel):
    """Request body for creating a brief."""

    source_type: SourceType
    source: str = Field(..., description="YouTube URL or pasted text")
    mode: ModeType = "insights"
    length: LengthType = "brief"
    output_language: str = "en"


class BriefMeta(BaseModel):
    """Metadata associated with a generated brief."""

    source_type: SourceType
    mode: ModeType
    length: LengthType
    output_language: str


class Brief(BaseModel):
    """Structured brief payload returned by the API."""

    id: str
    share_url: str
    title: str
    overview: str
    bullets: list[str]
    why_it_matters: str | None = None
    meta: BriefMeta
