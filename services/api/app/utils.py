import re
from urllib.parse import urlparse, parse_qs

def is_probably_youtube_url(url: str) -> bool:
    try:
        u = urlparse(url)
        return u.netloc.endswith("youtube.com") or u.netloc.endswith("youtu.be")
    except Exception:
        return False

def extract_youtube_video_id(url: str) -> str | None:
    u = urlparse(url)
    if u.netloc.endswith("youtu.be"):
        vid = u.path.strip("/")
        return vid or None
    if "youtube.com" in u.netloc:
        qs = parse_qs(u.query)
        if "v" in qs and qs["v"]:
            return qs["v"][0]
        # shorts
        m = re.match(r"^/shorts/([^/]+)", u.path)
        if m:
            return m.group(1)
    return None

def clean_pasted_text(text: str) -> str:
    # Basic cleanup: remove repeated whitespace, "see more", timestamps-ish fragments.
    t = text.replace("\r", "\n")
    t = re.sub(r"\n{3,}", "\n\n", t)
    t = re.sub(r"\s{2,}", " ", t)
    # common junk
    junk = [
        "See more",
        "Show more",
        "Translate Tweet",
        "Like",
        "Reply",
        "Repost",
        "Retweet",
    ]
    for j in junk:
        t = t.replace(j, "")
    return t.strip()
