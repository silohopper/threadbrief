"""Brief creation and retrieval HTTP endpoints."""

from fastapi import APIRouter, HTTPException, Request
import httpx
import logging
from datetime import datetime, timezone
from nanoid import generate

from app.models import CreateBriefRequest, BriefMeta, Brief
from app.settings import settings
from app.storage import memory_store
from app.utils import is_probably_youtube_url, clean_pasted_text
from app.youtube import fetch_youtube_transcript, get_ytdlp_info, TranscriptError
from app.llm import build_prompt, generate_brief_gemini, mock_brief
from app.parse import parse_llm_text

router = APIRouter()
logger = logging.getLogger(__name__)

ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"


def day_key_utc() -> str:
    """Return the current UTC date key used for rate limiting."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def client_ip(request: Request) -> str:
    """Extract a best-effort client IP from request headers."""
    # best-effort; behind proxies you'd use X-Forwarded-For
    client_host = request.client.host if request.client else ""
    return request.headers.get("x-forwarded-for", "").split(",")[0].strip() or client_host


@router.post("/briefs", response_model=Brief)
async def create_brief(payload: CreateBriefRequest, request: Request):
    """Create a brief from a YouTube URL or pasted text.

    Applies a per-IP daily rate limit, resolves the input content (either a
    transcript or cleaned paste), generates a prompt, and parses the LLM output
    into a structured Brief response that is stored in memory.

    Args:
        payload: Request body describing the source and output options.
        request: FastAPI request for rate limiting context.

    Returns:
        Fully parsed Brief object.

    Raises:
        HTTPException: When validation, rate limits, or transcript retrieval fails.
    """
    ip = client_ip(request)
    dk = day_key_utc()
    current = memory_store.get_rate(ip, dk)
    if current >= settings.rate_limit_per_day:
        raise HTTPException(status_code=429, detail=f"Daily limit reached ({settings.rate_limit_per_day}/day).")

    # Resolve content
    if payload.source_type == "youtube":
        if not is_probably_youtube_url(payload.source):
            raise HTTPException(status_code=400, detail="Please enter a valid YouTube URL.")
        try:
            content = fetch_youtube_transcript(payload.source)
        except TranscriptError as e:
            logger.warning("Transcript error for source=%s: %s", payload.source, e)
            raise HTTPException(status_code=400, detail=str(e))
    else:
        content = clean_pasted_text(payload.source)
        if len(content) < 200:
            raise HTTPException(status_code=400, detail="Paste text is too short. Paste the main post + top replies.")

    meta = BriefMeta(
        source_type=payload.source_type,
        source_url=payload.source if payload.source_type == "youtube" else None,
        mode=payload.mode,
        length=payload.length,
        output_language=payload.output_language,
    )

    prompt = build_prompt(payload.source_type, content, payload.mode, payload.length, payload.output_language)

    # Generate text (Gemini or mock)
    if settings.gemini_api_key:
        try:
            llm_text = await generate_brief_gemini(settings.gemini_api_key, prompt)
        except httpx.HTTPStatusError as exc:
            status = getattr(exc.response, "status_code", None) or 502
            if status == 429:
                raise HTTPException(
                    status_code=429,
                    detail="Gemini rate limit reached. Please wait a minute and try again.",
                ) from exc
            detail = f"Gemini request failed (status {status})."
            if exc.response is not None:
                text = (exc.response.text or "").strip()
                if text:
                    detail = f"{detail} {text[:200]}"
            raise HTTPException(status_code=status, detail=detail) from exc
    else:
        llm_text = mock_brief(prompt)

    brief_id = generate(size=6, alphabet=ALPHABET)
    share_url = f"{settings.web_base_url}/b/{brief_id}"

    brief = parse_llm_text(llm_text, brief_id=brief_id, share_url=share_url, meta=meta)

    # Store
    memory_store.save_brief(brief)
    memory_store.bump_rate(ip, dk)

    return brief


@router.get("/video-meta")
def get_video_meta(url: str, request: Request):
    """Return basic metadata for a YouTube URL (duration/title)."""
    if not is_probably_youtube_url(url):
        raise HTTPException(status_code=400, detail="Please enter a valid YouTube URL.")
    ip = client_ip(request)
    dk = f"video-meta:{day_key_utc()}"
    current = memory_store.get_rate(ip, dk)
    if current >= settings.rate_limit_per_day:
        raise HTTPException(status_code=429, detail=f"Daily limit reached ({settings.rate_limit_per_day}/day).")
    info = get_ytdlp_info(url)
    duration_seconds = None
    title = None
    if info:
        title = info.get("title")
        duration = info.get("duration")
        if isinstance(duration, (int, float)):
            duration_seconds = int(duration)
    memory_store.bump_rate(ip, dk)
    return {
        "duration_seconds": duration_seconds,
        "duration_minutes": round(duration_seconds / 60, 2) if duration_seconds else None,
        "title": title,
    }


@router.get("/briefs/{brief_id}", response_model=Brief)
def get_brief(brief_id: str):
    """Return a previously generated brief by id."""
    brief = memory_store.get_brief(brief_id)
    if not brief:
        raise HTTPException(status_code=404, detail="Brief not found.")
    return brief
