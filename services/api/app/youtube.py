from youtube_transcript_api import YouTubeTranscriptApi, TranscriptsDisabled, NoTranscriptFound, VideoUnavailable
from app.utils import extract_youtube_video_id

class TranscriptError(Exception):
    pass

def fetch_youtube_transcript(url: str) -> str:
    vid = extract_youtube_video_id(url)
    if not vid:
        raise TranscriptError("Invalid YouTube URL (could not extract video id).")

    try:
        # Prefer manually created transcripts when available; fallback to generated.
        transcript_list = YouTubeTranscriptApi.list_transcripts(vid)
        transcript = None
        try:
            transcript = transcript_list.find_manually_created_transcript(["en"])
        except Exception:
            transcript = transcript_list.find_generated_transcript(["en"])
        parts = transcript.fetch()
        return " ".join([p.get("text", "") for p in parts]).strip()
    except (TranscriptsDisabled, NoTranscriptFound):
        raise TranscriptError("No transcript available for this video.")
    except VideoUnavailable:
        raise TranscriptError("Video unavailable (region/age/restriction).")
    except Exception as e:
        raise TranscriptError(f"Failed to fetch transcript: {e}")
