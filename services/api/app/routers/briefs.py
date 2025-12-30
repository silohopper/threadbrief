from fastapi import APIRouter, HTTPException, Request
from datetime import datetime, timezone
from nanoid import generate

from app.models import CreateBriefRequest, BriefMeta
from app.settings import settings
from app.storage import memory_store
from app.utils import is_probably_youtube_url, clean_pasted_text
from app.youtube import fetch_youtube_transcript, TranscriptError
from app.llm import build_prompt, generate_brief_gemini, mock_brief
from app.parse import parse_llm_text

router = APIRouter()

ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

def day_key_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")

def client_ip(request: Request) -> str:
    # best-effort; behind proxies you'd use X-Forwarded-For
    return request.headers.get("x-forwarded-for", "").split(",")[0].strip() or request.client.host

@router.post("/briefs")
async def create_brief(payload: CreateBriefRequest, request: Request):
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
            raise HTTPException(status_code=400, detail=str(e))
    else:
        content = clean_pasted_text(payload.source)
        if len(content) < 200:
            raise HTTPException(status_code=400, detail="Paste text is too short. Paste the main post + top replies.")

    meta = BriefMeta(
        source_type=payload.source_type,
        mode=payload.mode,
        length=payload.length,
        output_language=payload.output_language,
    )

    prompt = build_prompt(payload.source_type, content, payload.mode, payload.length, payload.output_language)

    # Generate text (Gemini or mock)
    if settings.gemini_api_key:
        llm_text = await generate_brief_gemini(settings.gemini_api_key, prompt)
    else:
        llm_text = mock_brief(prompt)

    brief_id = generate(size=6, alphabet=ALPHABET)
    share_url = f"http://localhost:3000/b/{brief_id}"  # web builds can overwrite base; UI uses its own base

    brief = parse_llm_text(llm_text, brief_id=brief_id, share_url=share_url, meta=meta)

    # Store
    memory_store.save_brief(brief)
    memory_store.bump_rate(ip, dk)

    return brief

@router.get("/briefs/{brief_id}")
def get_brief(brief_id: str):
    brief = memory_store.get_brief(brief_id)
    if not brief:
        raise HTTPException(status_code=404, detail="Brief not found.")
    return brief
