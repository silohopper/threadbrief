"""API smoke tests for the FastAPI app."""

import asyncio
import os
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.llm import build_prompt, generate_brief_gemini
from app.youtube import fetch_youtube_transcript

client = TestClient(app)


def test_health():
    """Ensure the health endpoint returns a basic OK payload."""
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_create_brief_paste_mock():
    """Verify paste mode can create a brief without API keys."""
    payload = {
        "source_type": "paste",
        "source": "This is a long thread. " * 50,
        "mode": "insights",
        "length": "brief",
        "output_language": "en",
    }
    r = client.post("/v1/briefs", json=payload)
    assert r.status_code == 200
    data = r.json()
    assert "id" in data and len(data["id"]) == 6
    assert data["meta"]["source_type"] == "paste"


def test_youtube_transcript_integration():
    """Integration test for YouTube transcript fetching when enabled."""
    if os.getenv("YOUTUBE_INTEGRATION") != "1":
        pytest.skip("YOUTUBE_INTEGRATION not enabled.")

    url = "https://www.youtube.com/watch?v=fR-PReWhMGM"
    print("\nFetching YouTube transcript...", flush=True)
    text = fetch_youtube_transcript(url)
    print("\nTranscript preview:\n", text[:800])
    assert isinstance(text, str)
    assert len(text) > 40


def test_gemini_brief_from_youtube():
    """Integration test for Gemini generation from a YouTube transcript."""
    if os.getenv("GEMINI_INTEGRATION") != "1":
        pytest.skip("GEMINI_INTEGRATION not enabled.")
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        pytest.skip("GEMINI_API_KEY not set.")

    url = "https://www.youtube.com/watch?v=fR-PReWhMGM"
    transcript = fetch_youtube_transcript(url)
    prompt = build_prompt("youtube", transcript, "insights", "brief", "en")
    text = asyncio.run(generate_brief_gemini(api_key, prompt))
    assert isinstance(text, str)
    assert "Title:" in text
