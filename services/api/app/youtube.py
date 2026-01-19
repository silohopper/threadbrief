"""YouTube transcript retrieval with audio fallback."""

import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import quote
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


def _get_youtube_duration_seconds(url: str) -> int | None:
    """Fetch YouTube duration (seconds) via yt-dlp metadata."""
    ytdlp = _resolve_executable("yt-dlp", "YTDLP_PATH") or _resolve_executable(
        "youtube-dl",
        "YOUTUBEDL_PATH",
    )
    if not ytdlp:
        logger.warning("yt-dlp not found; cannot enforce video length limit.")
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
            return _run_ytdlp_meta(cmd)

    proxy_url = os.getenv("YTDLP_PROXY")
    if proxy_url:
        cmd.extend(["--proxy", _normalize_proxy(proxy_url)])
    return _run_ytdlp_meta(cmd)


def _run_ytdlp_meta(cmd: list[str]) -> int | None:
    """Run yt-dlp metadata command and extract duration."""
    meta_timeout = int(os.getenv("YTDLP_META_TIMEOUT_SECONDS", "60"))
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=meta_timeout)
    except Exception as exc:
        logger.warning("yt-dlp metadata failed: %s", exc)
        return None

    try:
        info = json.loads(result.stdout)
    except json.JSONDecodeError:
        logger.warning("yt-dlp metadata returned invalid JSON.")
        return None

    duration = info.get("duration")
    if isinstance(duration, (int, float)):
        return int(duration)
    return None


def _transcribe_audio(audio_path: Path) -> str:
    """Transcribe an audio file using the Whisper CLI."""
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
    """Download YouTube audio and transcribe it as a fallback."""
    with tempfile.TemporaryDirectory() as tmpdir:
        audio_path = _download_youtube_audio(url, tmpdir)
        return _transcribe_audio(audio_path)


def _fallback_to_audio_transcription(url: str, reason: str) -> str:
    """Try audio transcription fallback and wrap errors with context."""
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
    """
    vid = extract_youtube_video_id(url)
    if not vid:
        raise TranscriptError("Invalid YouTube URL (could not extract video id).")

    transcript = None
    transcript_url = None
    max_minutes = int(os.getenv("MAX_VIDEO_MINUTES", "10"))
    duration_seconds = _get_youtube_duration_seconds(url)
    if duration_seconds:
        duration_minutes = duration_seconds / 60.0
        logger.info("YouTube duration=%.2f minutes (max=%s).", duration_minutes, max_minutes)
        if duration_minutes > max_minutes:
            raise TranscriptError(f"Video is {duration_minutes:.1f} minutes. Max allowed is {max_minutes} minutes.")

    try:
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
        return " ".join([p.get("text", "") for p in parts]).strip()
    except (TranscriptsDisabled, NoTranscriptFound):
        return _fallback_to_audio_transcription(url, "No transcript available for this video.")
    except VideoUnavailable:
        raise TranscriptError("Video unavailable (region/age/restriction).")
    except ParseError as e:
        msg = str(e).lower()
        if "no element found" in msg:
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
        return _fallback_to_audio_transcription(url, f"Failed to fetch transcript: {e}")
