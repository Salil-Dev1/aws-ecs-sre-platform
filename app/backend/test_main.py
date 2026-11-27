from unittest.mock import Mock

import pytest
from bson import ObjectId
from fastapi.testclient import TestClient
from pymongo.errors import ServerSelectionTimeoutError

from main import create_app


def make_client():
    collection = Mock()
    collection.find.return_value = [{"_id": ObjectId("507f1f77bcf86cd799439011"), "title": "Sample"}]
    collection.insert_one.return_value.inserted_id = ObjectId("507f1f77bcf86cd799439012")
    collection.delete_one.return_value.deleted_count = 1
    client = Mock()
    client.get_database.return_value.items = collection
    client.admin.command.return_value = {"ok": 1}

    application = create_app(client=client)
    application.state.client = client
    application.state.items = collection
    return TestClient(application), client, collection


def test_health_reports_database_state():
    http, client, _ = make_client()
    response = http.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "db": "connected"}
    client.admin.command.assert_called_once_with("ping")


def test_default_database_is_taskflowdb():
    client = Mock()
    client.get_database.return_value.items = Mock()
    with TestClient(create_app(client=client)):
        pass
    client.get_database.assert_called_once_with("taskflowdb")


def test_items_crud_and_request_id():
    http, _, collection = make_client()
    listed = http.get("/api/items", headers={"X-Request-ID": "request-123"})
    assert listed.status_code == 200
    assert listed.headers["x-request-id"] == "request-123"
    assert listed.json() == [{"id": "507f1f77bcf86cd799439011", "title": "Sample"}]
    created = http.post("/api/items", json={"title": "A task"})
    assert created.status_code == 201
    assert created.json() == {"id": "507f1f77bcf86cd799439012", "title": "A task"}
    deleted = http.delete("/api/items/507f1f77bcf86cd799439011")
    assert deleted.status_code == 200
    collection.delete_one.assert_called_once()


def test_metrics_are_exposed():
    http, _, _ = make_client()
    http.get("/health")
    response = http.get("/metrics")
    assert response.status_code == 200
    assert "http_requests_total" in response.text


def test_database_outage_returns_clean_503():
    http, client, collection = make_client()
    client.admin.command.side_effect = ServerSelectionTimeoutError("offline")
    response = http.get("/health")
    assert response.status_code == 503
    assert response.json() == {"status": "degraded", "db": "unreachable"}
    collection.find.side_effect = ServerSelectionTimeoutError("offline")
    response = http.get("/api/items")
    assert response.status_code == 503
    assert response.json() == {"detail": "Database is unavailable"}


def test_missing_mongo_uri_fails_startup_clearly(monkeypatch):
    monkeypatch.delenv("MONGO_URI", raising=False)
    with pytest.raises(RuntimeError, match="MONGO_URI is required"), TestClient(create_app()):
        pass
