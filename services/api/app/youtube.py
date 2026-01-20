"""YouTube transcript retrieval with audio fallback."""

import logging
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from xml.etree.ElementTree import ParseError
import json

from youtube_transcript_api import (
    YouTubeTranscriptApi,
    TranscriptsDisabled,
    NoTranscriptFound,
    VideoUnavailable,
)

from app.utils import extract_youtube_video_id


class TranscriptError(Exception):
    """Raised when a transcript cannot be retrieved or generated."""


logger = logging.getLogger(__name__)


def _normalize_proxy(proxy_url: str) -> str:
    """Normalize proxy strings to URL form expected by yt-dlp."""
    if "://" in proxy_url:
        return proxy_url
    parts = proxy_url.split(":")
    if len(parts) == 4:
        host, port, user, password = parts
        safe_user = quote(user, safe="")
        safe_password = quote(password, safe="")
        return f"http://{safe_user}:{safe_password}@{host}:{port}"
    return proxy_url


def _resolve_executable(name: str, env_var: str | None = None) -> str | None:
    """Resolve a CLI executable path with an optional env override."""
    if env_var:
        override = os.getenv(env_var)
        if override:
            return override
    return shutil.which(name)


def _download_youtube_audio(url: str, workdir: str) -> Path:
    """Download YouTube audio to a local file using yt-dlp/youtube-dl."""
    logger.info("Downloading YouTube audio via yt-dlp/youtube-dl.")
    ytdlp = _resolve_executable("yt-dlp", "YTDLP_PATH") or _resolve_executable(
        "youtube-dl",
        "YOUTUBEDL_PATH",
    )
    if not ytdlp:
        raise TranscriptError("yt-dlp (or youtube-dl) not found. Install it to enable audio fallback.")

    output_template = str(Path(workdir) / "audio.%(ext)s")
    cmd = [
        ytdlp,
        "-x",
        "--audio-format",
        "mp3",
        "--audio-quality",
        "0",
        "-o",
        output_template,
        url,
    ]
    cookies_text = os.getenv("YTDLP_COOKIES")
    logger.info("yt-dlp cookies present=%s", bool(cookies_text))
    if cookies_text:
        cookies_path = Path(workdir) / "cookies.txt"
        cookies_path.write_text(cookies_text, encoding="utf-8")
        cmd.extend(["--cookies", str(cookies_path)])
    proxy_url = os.getenv("YTDLP_PROXY")
    logger.info("yt-dlp proxy present=%s", bool(proxy_url))
    if proxy_url:
        cmd.extend(["--proxy", _normalize_proxy(proxy_url)])
    extra_args = os.getenv("YTDLP_ARGS", "").split()
    if extra_args:
        logger.info("yt-dlp extra args=%s", extra_args)
    if extra_args:
        cmd.extend(extra_args)
    ytdlp_timeout = int(os.getenv("YTDLP_TIMEOUT_SECONDS", "900"))
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=ytdlp_timeout)
    except subprocess.TimeoutExpired as exc:
        raise TranscriptError("yt-dlp timed out while downloading audio.") from exc
    except subprocess.CalledProcessError as exc:
        logger.warning(
            "yt-dlp failed (cookies_present=%s proxy_present=%s)",
            bool(cookies_text),
            bool(proxy_url),
        )
        stderr = exc.stderr.strip() if exc.stderr else ""
        stdout = exc.stdout.strip() if exc.stdout else ""
        logger.error("yt-dlp exit=%s stdout=%s stderr=%s", exc.returncode, stdout[:500], stderr[:500])
        if not stderr and not stdout:
            stderr = "Unknown yt-dlp error."
        elif not stderr:
            stderr = stdout
        raise TranscriptError(f"yt-dlp failed to download audio: {stderr}") from exc

    candidates = list(Path(workdir).glob("audio.*"))
    if not candidates:
        raise TranscriptError("yt-dlp completed but no audio file was produced.")
    audio_path = max(candidates, key=lambda path: path.stat().st_size)
    logger.info("Downloaded audio file: %s", audio_path.name)
    return audio_path


def get_ytdlp_info(url: str) -> dict | None:
    """Fetch yt-dlp metadata for a YouTube URL."""
    ytdlp = _resolve_executable("yt-dlp", "YTDLP_PATH") or _resolve_executable(
        "youtube-dl",
        "YOUTUBEDL_PATH",
    )
    if not ytdlp:
        logger.warning("yt-dlp not found; cannot fetch metadata.")
        return None

    cmd = [
        ytdlp,
        "--dump-single-json",
        "--skip-download",
        "--no-warnings",
        "--no-playlist",
        url,
    ]
    cookies_text = os.getenv("YTDLP_COOKIES")
    if cookies_text:
        with tempfile.TemporaryDirectory() as tmpdir:
            cookies_path = Path(tmpdir) / "cookies.txt"
            cookies_path.write_text(cookies_text, encoding="utf-8")
            cmd.extend(["--cookies", str(cookies_path)])
            proxy_url = os.getenv("YTDLP_PROXY")
            if proxy_url:
                cmd.extend(["--proxy", _normalize_proxy(proxy_url)])
            return _run_ytdlp_info(cmd)

    proxy_url = os.getenv("YTDLP_PROXY")
    if proxy_url:
        cmd.extend(["--proxy", _normalize_proxy(proxy_url)])
    return _run_ytdlp_info(cmd)


def _run_ytdlp_info(cmd: list[str]) -> dict | None:
    """Run yt-dlp metadata command and return parsed JSON."""
    meta_timeout = int(os.getenv("YTDLP_META_TIMEOUT_SECONDS", "60"))
    start = time.monotonic()
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=meta_timeout)
    except Exception as exc:
        logger.warning("yt-dlp metadata failed after %.2fs: %s", time.monotonic() - start, exc)
        return None

    try:
        info = json.loads(result.stdout)
    except json.JSONDecodeError:
        logger.warning("yt-dlp metadata returned invalid JSON after %.2fs.", time.monotonic() - start)
        return None

    logger.info("yt-dlp metadata fetched in %.2fs.", time.monotonic() - start)
    return info


def _extract_duration_seconds(info: dict | None) -> int | None:
    """Extract a duration value (seconds) from yt-dlp metadata."""
    if not info:
        return None
    duration = info.get("duration")
    if isinstance(duration, (int, float)):
        return int(duration)
    return None


def get_youtube_duration_seconds(url: str) -> int | None:
    """Fetch YouTube duration (seconds) via yt-dlp metadata."""
    return _extract_duration_seconds(get_ytdlp_info(url))


def _select_caption_entry(captions: dict) -> dict | None:
    """Pick the best caption entry from a yt-dlp captions map."""
    if not captions:
        return None
    lang_keys = list(captions.keys())

    def lang_rank(lang: str) -> tuple[int, str]:
        lang_lower = lang.lower()
        if lang_lower == "en":
            return (0, lang_lower)
        if lang_lower.startswith("en-") or lang_lower.startswith("en_"):
            return (1, lang_lower)
        if lang_lower.startswith("en"):
            return (2, lang_lower)
        return (3, lang_lower)

    ext_priority = ["vtt", "ttml", "srv3", "srv2", "srv1", "json3"]

    def ext_rank(entry: dict) -> int:
        ext = (entry.get("ext") or "").lower()
        if ext in ext_priority:
            return ext_priority.index(ext)
        return len(ext_priority)

    for lang in sorted(lang_keys, key=lang_rank):
        entries = captions.get(lang) or []
        if not entries:
            continue
        return sorted(entries, key=ext_rank)[0]
    return None


def _download_caption_text(caption_url: str) -> str | None:
    """Download caption text from a URL.

    How it works: performs a direct HTTP GET with a browser-like UA and timeout.
    """
    timeout = int(os.getenv("YTDLP_CAPTION_TIMEOUT_SECONDS", "30"))
    try:
        req = Request(caption_url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8", errors="ignore")
    except (HTTPError, URLError, TimeoutError) as exc:
        logger.warning("Caption download failed: %s", exc)
        return None


def _parse_vtt_text(raw_text: str) -> str:
    """Parse WebVTT captions into a single text string.

    How it works: strips cues/timestamps and joins visible lines.
    """
    lines = []
    for line in raw_text.splitlines():
        stripped = line.strip()
        if not stripped or stripped == "WEBVTT" or "-->" in stripped or stripped.isdigit():
            continue
        lines.append(stripped)
    return " ".join(lines).strip()


def _parse_ttml_text(raw_text: str) -> str:
    """Parse TTML captions into a single text string.

    How it works: extracts text from <p> elements and concatenates them.
    """
    try:
        from xml.etree import ElementTree

        root = ElementTree.fromstring(raw_text)
    except Exception:
        return ""
    parts = []
    for elem in root.iter():
        if elem.tag.endswith("p"):
            parts.append(" ".join(text.strip() for text in elem.itertext() if text and text.strip()))
    return " ".join(parts).strip()


def _parse_json3_text(raw_text: str) -> str:
    """Parse YouTube json3 captions into a single text string.

    How it works: concatenates utf8 segments from each caption event.
    """
    try:
        data = json.loads(raw_text)
    except json.JSONDecodeError:
        return ""
    parts = []
    for event in data.get("events", []):
        segs = event.get("segs") or []
        chunk = "".join(seg.get("utf8", "") for seg in segs if isinstance(seg, dict))
        if chunk:
            parts.append(chunk)
    return " ".join(parts).strip()


def _parse_caption_text(raw_text: str, ext: str) -> str:
    """Parse captions based on file extension.

    How it works: dispatches to the correct parser for vtt/ttml/json3/srv*.
    """
    ext_lower = (ext or "").lower()
    if ext_lower == "vtt":
        return _parse_vtt_text(raw_text)
    if ext_lower == "ttml":
        return _parse_ttml_text(raw_text)
    if ext_lower == "json3":
        return _parse_json3_text(raw_text)
    if ext_lower.startswith("srv"):
        return _parse_ttml_text(raw_text)
    return ""


def _get_caption_text_from_ytdlp_info(info: dict | None) -> str | None:
    """Fetch caption text from yt-dlp metadata if available.

    How it works: picks the best caption entry, downloads it, and parses to text.
    """
    if not info:
        return None
    for source_key in ("subtitles", "automatic_captions"):
        captions = info.get(source_key) or {}
        entry = _select_caption_entry(captions)
        if not entry:
            continue
        caption_url = entry.get("url")
        ext = entry.get("ext", "")
        if not caption_url:
            continue
        start = time.monotonic()
        raw_text = _download_caption_text(caption_url)
        if not raw_text:
            continue
        parsed = _parse_caption_text(raw_text, ext)
        if parsed:
            logger.info("yt-dlp %s captions fetched in %.2fs.", source_key, time.monotonic() - start)
            return parsed
        logger.warning("yt-dlp %s captions parsed empty (ext=%s).", source_key, ext)
    return None


def _transcribe_audio(audio_path: Path) -> str:
    """Transcribe an audio file using the Whisper CLI.

    How it works: runs Whisper CLI with configured model/language and reads output text.
    """
    logger.info("Starting Whisper transcription with model=%s.", os.getenv("WHISPER_MODEL", "base"))
    whisper = _resolve_executable("whisper", "WHISPER_PATH")
    if not whisper:
        raise TranscriptError("Whisper CLI not found. Install openai-whisper to enable audio transcription.")

    model = os.getenv("WHISPER_MODEL", "base")
    language = os.getenv("WHISPER_LANGUAGE", "en")
    output_dir = audio_path.parent / "whisper_out"
    output_dir.mkdir(exist_ok=True)

    cmd = [
        whisper,
        str(audio_path),
        "--model",
        model,
        "--output_format",
        "txt",
        "--output_dir",
        str(output_dir),
        "--task",
        "transcribe",
        "--fp16",
        "False",
    ]
    if language:
        cmd.extend(["--language", language])

    whisper_timeout = int(os.getenv("WHISPER_TIMEOUT_SECONDS", "900"))
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=whisper_timeout)
    except subprocess.TimeoutExpired as exc:
        raise TranscriptError("Whisper timed out while transcribing audio.") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip() if exc.stderr else ""
        stdout = exc.stdout.strip() if exc.stdout else ""
        logger.error("Whisper exit=%s stdout=%s stderr=%s", exc.returncode, stdout[:500], stderr[:500])
        if not stderr and not stdout:
            stderr = "Unknown Whisper error."
        elif not stderr:
            stderr = stdout
        raise TranscriptError(f"Whisper transcription failed: {stderr}") from exc

    transcript_path = output_dir / f"{audio_path.stem}.txt"
    if not transcript_path.exists():
        txt_files = list(output_dir.glob("*.txt"))
        if not txt_files:
            raise TranscriptError("Whisper finished but no transcript file was produced.")
        transcript_path = txt_files[0]

    text = transcript_path.read_text(encoding="utf-8").strip()
    logger.info("Whisper transcript length=%s chars.", len(text))
    return text


def _transcribe_youtube_audio(url: str) -> str:
    """Download YouTube audio and transcribe it as a fallback.

    How it works: uses yt-dlp to fetch audio and then runs Whisper on the file.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        start = time.monotonic()
        audio_path = _download_youtube_audio(url, tmpdir)
        text = _transcribe_audio(audio_path)
        logger.info("Audio transcription finished in %.2fs.", time.monotonic() - start)
        return text


def _fallback_to_audio_transcription(url: str, reason: str) -> str:
    """Try audio transcription fallback and wrap errors with context.

    How it works: logs the reason, calls the audio path, and re-raises with context.
    """
    logger.info("Falling back to audio transcription: %s", reason)
    try:
        return _transcribe_youtube_audio(url)
    except TranscriptError as exc:
        raise TranscriptError(f"{reason} Audio transcription fallback failed: {exc}") from exc


def fetch_youtube_transcript(url: str) -> str:
    """Fetch a transcript or fall back to audio transcription.

    Attempts to use YouTube's transcript APIs first, preferring English or
    translating to English when possible. If no transcript is available,
    downloads the audio and runs the Whisper CLI to generate a transcript.

    Args:
        url: YouTube video URL.

    Returns:
        Transcript text in English (translated when supported).

    Raises:
        TranscriptError: When the transcript and fallback transcription fail.

    How it works: validates URL, checks duration, tries YouTube API, then yt-dlp
    captions, and finally Whisper audio transcription.
    """
    vid = extract_youtube_video_id(url)
    if not vid:
        raise TranscriptError("Invalid YouTube URL (could not extract video id).")

    transcript = None
    transcript_url = None
    ytdlp_info = get_ytdlp_info(url)
    max_minutes = int(os.getenv("MAX_VIDEO_MINUTES", "10"))
    duration_seconds = _extract_duration_seconds(ytdlp_info)
    if duration_seconds:
        duration_minutes = duration_seconds / 60.0
        logger.info("YouTube duration=%.2f minutes (max=%s).", duration_minutes, max_minutes)
        if duration_minutes > max_minutes:
            raise TranscriptError(f"Video is {duration_minutes:.1f} minutes. Max allowed is {max_minutes} minutes.")

    try:
        api_start = time.monotonic()
        transcript_list = YouTubeTranscriptApi.list_transcripts(vid)

        # Prefer English, but fall back to any available track (manual or generated),
        # and auto-translate to English if needed.
        try:
            transcript = transcript_list.find_manually_created_transcript(["en"])
        except Exception:
            try:
                transcript = transcript_list.find_generated_transcript(["en"])
            except Exception:
                # Grab first available transcript and translate to English if possible.
                available = list(transcript_list)
                if not available:
                    raise NoTranscriptFound("No transcripts in any language.")
                transcript = available[0]
                if "en" not in transcript.language_code and transcript.is_translatable:
                    transcript = transcript.translate("en")

        transcript_url = getattr(transcript, "_url", None)
        parts = transcript.fetch()
        text = " ".join([p.get("text", "") for p in parts]).strip()
        logger.info("YouTube transcript API fetched in %.2fs.", time.monotonic() - api_start)
        return text
    except (TranscriptsDisabled, NoTranscriptFound):
        ytdlp_text = _get_caption_text_from_ytdlp_info(ytdlp_info)
        if not ytdlp_text and ytdlp_info is None:
            ytdlp_text = _get_caption_text_from_ytdlp_info(get_ytdlp_info(url))
        if ytdlp_text:
            return ytdlp_text
        return _fallback_to_audio_transcription(url, "No transcript available for this video.")
    except VideoUnavailable:
        raise TranscriptError("Video unavailable (region/age/restriction).")
    except ParseError as e:
        msg = str(e).lower()
        if "no element found" in msg:
            ytdlp_text = _get_caption_text_from_ytdlp_info(ytdlp_info)
            if not ytdlp_text and ytdlp_info is None:
                ytdlp_text = _get_caption_text_from_ytdlp_info(get_ytdlp_info(url))
            if ytdlp_text:
                return ytdlp_text
            return _fallback_to_audio_transcription(
                url,
                "YouTube returned an empty transcript response.",
            )
        raise TranscriptError(f"Failed to parse transcript response: {e}")
    except Exception as e:
        raw_body = None
        if transcript and hasattr(transcript, "_http_client") and transcript_url:
            try:
                raw_body = transcript._http_client.get(transcript_url)
            except Exception:
                raw_body = None

        cause = getattr(e, "cause", None)
        resp = getattr(cause, "response", None) if cause else None
        body_snippet = None
        if resp is not None and hasattr(resp, "text"):
            body_snippet = resp.text[:200]
        elif isinstance(raw_body, str):
            body_snippet = raw_body[:200]
        logger.exception(
            "Transcript fetch failed for video_id=%s err_type=%s cause_type=%s status=%s body_snippet=%s transcript_url=%s raw_len=%s",
            vid,
            e.__class__.__name__,
            cause.__class__.__name__ if cause else None,
            getattr(resp, "status_code", None),
            body_snippet,
            transcript_url,
            len(raw_body) if isinstance(raw_body, str) else None,
        )
        ytdlp_text = _get_caption_text_from_ytdlp_info(ytdlp_info)
        if not ytdlp_text and ytdlp_info is None:
            ytdlp_text = _get_caption_text_from_ytdlp_info(get_ytdlp_info(url))
        if ytdlp_text:
            return ytdlp_text
        return _fallback_to_audio_transcription(url, f"Failed to fetch transcript: {e}")
