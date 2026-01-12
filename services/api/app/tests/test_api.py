"""API smoke tests for the FastAPI app."""

import os
import pytest
from fastapi.testclient import TestClient
from app.main import app
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
