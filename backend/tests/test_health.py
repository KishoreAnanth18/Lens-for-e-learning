"""Test health check endpoint"""


def test_health_check(client):
    """Test that health check endpoint returns 200"""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "version" in data
