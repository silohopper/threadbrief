from pydantic import BaseModel, Field
from typing import Literal

SourceType = Literal["youtube", "paste"]
ModeType = Literal["insights", "summary"]
LengthType = Literal["tldr", "brief", "detailed"]

class CreateBriefRequest(BaseModel):
    source_type: SourceType
    source: str = Field(..., description="YouTube URL or pasted text")
    mode: ModeType = "insights"
    length: LengthType = "brief"
    output_language: str = "en"

class BriefMeta(BaseModel):
    source_type: SourceType
    mode: ModeType
    length: LengthType
    output_language: str

class Brief(BaseModel):
    id: str
    share_url: str
    title: str
    overview: str
    bullets: list[str]
    why_it_matters: str | None = None
    meta: BriefMeta
