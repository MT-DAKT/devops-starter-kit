from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_returns_200():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_metrics_endpoint_exists():
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"http_requests_total" in response.content