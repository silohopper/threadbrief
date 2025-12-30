import logging
from xml.etree.ElementTree import ParseError
from youtube_transcript_api import YouTubeTranscriptApi, TranscriptsDisabled, NoTranscriptFound, VideoUnavailable
from app.utils import extract_youtube_video_id

class TranscriptError(Exception):
    pass

logger = logging.getLogger(__name__)

def fetch_youtube_transcript(url: str) -> str:
    vid = extract_youtube_video_id(url)
    if not vid:
        raise TranscriptError("Invalid YouTube URL (could not extract video id).")

    transcript = None
    transcript_url = None

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
        raise TranscriptError("No transcript available for this video.")
    except VideoUnavailable:
        raise TranscriptError("Video unavailable (region/age/restriction).")
    except ParseError as e:
        msg = str(e).lower()
        if "no element found" in msg:
            raise TranscriptError("YouTube returned an empty transcript response. Try again later or paste the transcript.")
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
        logger.exception(
            "Transcript fetch failed for video_id=%s err_type=%s cause_type=%s status=%s body_snippet=%s transcript_url=%s raw_len=%s",
            vid,
            e.__class__.__name__,
            cause.__class__.__name__ if cause else None,
            getattr(resp, "status_code", None),
            (resp.text[:200] if hasattr(resp, "text") else (raw_body[:200] if isinstance(raw_body, str) else None)),
            transcript_url,
            len(raw_body) if isinstance(raw_body, str) else None,
        )
        raise TranscriptError(f"Failed to fetch transcript: {e}")
