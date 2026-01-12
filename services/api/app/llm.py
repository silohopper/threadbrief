"""LLM prompt construction and response generation helpers."""

import hashlib
import json
import httpx
from app.models import ModeType, LengthType

GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"


def _length_guidance(length: LengthType) -> str:
    """Map length choices to concise guidance."""
    if length == "tldr":
        return "3-5 bullets, very concise."
    if length == "detailed":
        return "8-12 bullets, include a little extra context per bullet."
    return "5-8 bullets, concise but useful."


def build_prompt(source_type: str, content: str, mode: ModeType, length: LengthType, output_language: str) -> str:
    """Build the strict prompt used to generate a brief.

    The prompt includes explicit output formatting instructions so the parser
    can reliably extract the title, overview, bullet list, and optional
    "WhyItMatters" section.

    Args:
        source_type: Input type such as "youtube" or "paste".
        content: Transcript or pasted text to summarize.
        mode: Summary vs insights mode.
        length: Target output length bucket.
        output_language: Language code for the output.

    Returns:
        Fully rendered prompt string.
    """
    mode_hint = "Extract the most important insights (signal over noise)." if mode == "insights" else "Summarize what was said accurately."
    guidance = _length_guidance(length)
    return f"""You are ThreadBrief, a tool that produces structured briefs.

TASK:
- {mode_hint}
- Output language: {output_language}
- Length: {guidance}

OUTPUT FORMAT (strict):
Title: <short title>
Overview: <2-3 sentences>
Bullets:
- <bullet 1>
- <bullet 2>
- ...
WhyItMatters: <optional single paragraph, or leave blank>

SOURCE TYPE: {source_type}

CONTENT:
{content}
"""


async def generate_brief_gemini(api_key: str, prompt: str) -> str:
    """Call Gemini to generate a brief from the prompt.

    Args:
        api_key: Gemini API key.
        prompt: Fully constructed prompt text.

    Returns:
        The raw model text, or a JSON payload if parsing fails.

    Raises:
        httpx.HTTPError: If the Gemini request fails.
    """
    headers = {"Content-Type": "application/json"}
    payload = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.4, "maxOutputTokens": 900},
    }
    url = f"{GEMINI_ENDPOINT}?key={api_key}"
    async with httpx.AsyncClient(timeout=45) as client:
        r = await client.post(url, headers=headers, json=payload)
        r.raise_for_status()
        data = r.json()
        # Pull first candidate text
        try:
            return data["candidates"][0]["content"]["parts"][0]["text"]
        except Exception:
            return json.dumps(data)


def mock_brief(prompt: str) -> str:
    """Return deterministic mock output for local dev without API keys."""
    # Deterministic mock for dev (no keys). Uses hash to vary slightly.
    h = hashlib.sha256(prompt.encode("utf-8")).hexdigest()[:6]
    return f"""Title: Demo Brief {h}
Overview: This is mock output because GEMINI_API_KEY is not set. It shows the final structure used by the UI.
Bullets:
- Key point one (mock)
- Key point two (mock)
- Key point three (mock)
WhyItMatters: Mock briefs let you build and test the full product end-to-end without burning tokens.
"""
