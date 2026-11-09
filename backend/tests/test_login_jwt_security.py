"""Casos explícitos de segurança do login e dos tokens de acesso."""

import base64
import json
from datetime import datetime, timedelta

import pytest
from sqlalchemy import event

from test_integration import client
from app.core import clock
from app.core.database import SessionLocal, engine
from app.core.security import make_token, pwd
from app.models import User


def _patient() -> tuple[int, str]:
    with SessionLocal() as db:
        patient = User(
            nome="Paciente Segurança",
            cpf="52998224725",
            email="seguranca.login@example.test",
            senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente",
            ativo=True,
            email_verificado=True,
            data_nascimento=datetime(1990, 1, 1),
        )
        db.add(patient)
        db.commit()
        db.refresh(patient)
        return patient.id, make_token(patient)


def _unsigned_token(user_id: int) -> str:
    def encoded(value: dict) -> str:
        raw = json.dumps(value, separators=(",", ":")).encode()
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    return ".".join(
        [
            encoded({"alg": "none", "typ": "JWT"}),
            encoded(
                {
                    "sub": str(user_id),
                    "purpose": "access",
                    "version": 0,
                    "role": "paciente",
                    "exp": int(
                        (clock.now_utc() + timedelta(hours=1)).timestamp()
                    ),
                }
            ),
            "",
        ]
    )


def _assert_safe_error(response) -> None:
    assert response.status_code in {401, 422}
    body = response.text.casefold()
    for internal in (
        "traceback",
        "sqlalchemy",
        "sqlite",
        "usuarios.",
        "select ",
        "insert ",
        "database error",
    ):
        assert internal not in body


def test_alg_none_is_rejected_without_breaking_valid_tokens(client):
    patient_id, valid_token = _patient()

    valid = client.get(
        "/patients/me", headers={"Authorization": f"Bearer {valid_token}"}
    )
    assert valid.status_code == 200

    rejected = client.get(
        "/patients/me",
        headers={"Authorization": f"Bearer {_unsigned_token(patient_id)}"},
    )
    assert rejected.status_code == 401
    assert rejected.headers["www-authenticate"] == "Bearer"
    assert rejected.json() == {"detail": "Sessão inválida ou expirada"}
    _assert_safe_error(rejected)


@pytest.mark.parametrize(
    ("document", "password"),
    [
        ("' OR '1'='1", "qualquer"),
        ("52998224725' --", "qualquer"),
        ("52998224725", "' OR '1'='1"),
        ("52998224725", "x'; DROP TABLE usuarios; --"),
    ],
)
def test_login_sql_injection_is_parameterized_and_cannot_bypass_authentication(
    client, document, password
):
    _patient()
    statements: list[str] = []

    def capture(_connection, _cursor, statement, _parameters, _context, _many):
        statements.append(statement)

    event.listen(engine, "before_cursor_execute", capture)
    try:
        response = client.post(
            "/auth/login", json={"document": document, "password": password}
        )
    finally:
        event.remove(engine, "before_cursor_execute", capture)

    assert response.status_code == 401
    assert response.json() == {"detail": "CPF ou senha inválidos"}
    _assert_safe_error(response)
    assert statements
    assert all(document not in statement for statement in statements)
    assert all(password not in statement for statement in statements)
    if document == "52998224725":
        user_queries = [
            statement for statement in statements if "usuarios.cpf" in statement
        ]
        assert user_queries
        assert all("?" in statement for statement in user_queries)


def test_valid_login_still_works_after_malicious_attempts(client):
    _patient()
    for password in ("' OR 1=1 --", "admin' --", '" OR ""="'):
        response = client.post(
            "/auth/login",
            json={"document": "52998224725", "password": password},
        )
        assert response.status_code == 401

    valid = client.post(
        "/auth/login",
        json={"document": "52998224725", "password": "Paciente@123"},
    )
    assert valid.status_code == 200
    assert valid.json()["access_token"]
