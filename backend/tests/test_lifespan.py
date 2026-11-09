"""Regressões da inicialização da API pelo lifespan do FastAPI."""

import os
import secrets
import tempfile
from pathlib import Path

from fastapi.testclient import TestClient

TEST_DIR = tempfile.TemporaryDirectory()
os.environ["DATABASE_URL"] = "sqlite:///" + str(Path(TEST_DIR.name) / "test.db")
os.environ["JWT_SECRET_KEY"] = secrets.token_urlsafe(48)
os.environ["SEED_DEMO_DATA"] = "false"

import app.main as main_module


def test_lifespan_initializes_once_and_health_survives_shutdown(monkeypatch):
    calls: list[str] = []
    monkeypatch.setattr(main_module, "startup", lambda: calls.append("startup"))

    with TestClient(main_module.app) as client:
        assert calls == ["startup"]
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    assert calls == ["startup"]
