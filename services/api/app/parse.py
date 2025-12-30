import re
from app.models import BriefMeta, Brief

def parse_llm_text(text: str, brief_id: str, share_url: str, meta: BriefMeta) -> Brief:
    # Very forgiving parser for the strict-ish format
    title = _grab(text, r"Title:\s*(.*)")
    overview = _grab(text, r"Overview:\s*(.*)")
    why = _grab(text, r"WhyItMatters:\s*(.*)", default="").strip() or None

    bullets_block = _grab_block(text, r"Bullets:\s*(.*)", stop_keys=["WhyItMatters:"])
    bullets = []
    if bullets_block:
        for line in bullets_block.splitlines():
            line = line.strip()
            if line.startswith("-"):
                bullets.append(line[1:].strip())
    if not bullets:
        # fallback: grab any dashed lines
        bullets = [m.group(1).strip() for m in re.finditer(r"^-\s+(.*)$", text, re.M)]

    title = title or "Untitled Brief"
    overview = overview or "No overview generated."

    return Brief(
        id=brief_id,
        share_url=share_url,
        title=title,
        overview=overview,
        bullets=bullets[:12],
        why_it_matters=why,
        meta=meta,
    )

def _grab(text: str, pattern: str, default: str = "") -> str:
    m = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
    return m.group(1).strip() if m else default

def _grab_block(text: str, pattern: str, stop_keys: list[str]) -> str:
    m = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
    if not m:
        return ""
    block = m.group(1)
    # stop at next key
    for k in stop_keys:
        idx = block.lower().find(k.lower())
        if idx != -1:
            block = block[:idx]
    return block.strip()
