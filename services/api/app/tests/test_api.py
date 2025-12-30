from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"

def test_create_brief_paste_mock():
    payload = {
        "source_type": "paste",
        "source": "This is a long thread. " * 50,
        "mode": "insights",
        "length": "brief",
        "output_language": "en"
    }
    r = client.post("/v1/briefs", json=payload)
    assert r.status_code == 200
    data = r.json()
    assert "id" in data and len(data["id"]) == 6
    assert data["meta"]["source_type"] == "paste"
