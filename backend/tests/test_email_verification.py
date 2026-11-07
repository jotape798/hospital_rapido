from datetime import timedelta
import logging

import pytest
from sqlalchemy import func, select

from test_integration import client, data, login
from app.core import clock
from app.core.database import SessionLocal
from app.core.security import pwd
from app.main import migrate_database
from app.models import EmailVerification, User
from app.routes import email_verification as routes
from app.services.mailer import MailUnavailable


def _capture_delivery(monkeypatch):
    sent = []
    monkeypatch.setattr(
        routes,
        "send_email_verification",
        lambda email, code: sent.append((email, code)),
    )
    return sent


def _register(client, monkeypatch, **overrides):
    sent = _capture_delivery(monkeypatch)
    payload = data(**overrides)
    response = client.post("/auth/register", json=payload)
    assert response.status_code == 201, response.text
    assert sent and sent[0][0] == payload["email"].strip().lower()
    return payload, response, sent


def _verify(client, email, code):
    return client.post(
        "/auth/email/validar-codigo", json={"email": email, "code": code}
    )


def test_registration_starts_required_confirmation_with_hashed_six_digit_code(
    client, monkeypatch
):
    payload, response, sent = _register(client, monkeypatch)
    code = sent[0][1]
    body = response.json()
    assert len(code) == 6 and code.isdigit()
    assert body["email"] == payload["email"]
    assert body["resend_after_seconds"] == 60
    assert body["verification_token"]
    assert body["verification_token"].count(".") != 2
    assert "access_token" not in body and "token_type" not in body
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.email == payload["email"]))
        row = db.scalar(select(EmailVerification))
        assert user is not None and user.email_verificado is False
        assert row.codigo_hash != code and len(row.codigo_hash) == 64
        assert row.token_correcao_hash != body["verification_token"]
        assert routes.verification_code_matches(user.id, code, row.codigo_hash)
        remaining = row.expira_em - clock.now_utc_naive()
        assert timedelta(minutes=9, seconds=55) < remaining <= timedelta(minutes=10)


def test_pending_patient_cannot_login_or_receive_jwt_then_can_after_confirmation(
    client, monkeypatch
):
    payload, _, sent = _register(client, monkeypatch)
    before = login(client)
    assert before.status_code == 403
    assert "access_token" not in before.text
    assert "Confirme seu e-mail" in before.json()["detail"]
    assert _verify(client, payload["email"], sent[0][1]).status_code == 200
    after = login(client)
    assert after.status_code == 200
    assert "access_token" in after.json()


def test_wrong_code_is_rejected_and_five_attempts_block_the_code(client, monkeypatch):
    payload, _, sent = _register(client, monkeypatch)
    wrong = "999999" if sent[0][1] != "999999" else "888888"
    for _ in range(routes.MAX_CODE_ATTEMPTS):
        response = _verify(client, payload["email"], wrong)
        assert response.status_code == 400
    with SessionLocal() as db:
        row = db.scalar(select(EmailVerification))
        assert row.tentativas == routes.MAX_CODE_ATTEMPTS
    blocked = _verify(client, payload["email"], sent[0][1])
    assert blocked.status_code in {400, 429}
    assert login(client).status_code == 403
    with SessionLocal() as db:
        row = db.scalar(select(EmailVerification))
        row.criado_em = clock.now_utc_naive() - timedelta(seconds=61)
        db.commit()
    resent = client.post(
        "/auth/email/reenviar-codigo", json={"email": payload["email"]}
    )
    assert resent.status_code == 200
    assert _verify(client, payload["email"], sent[-1][1]).status_code == 200


def test_expired_code_is_rejected(client, monkeypatch):
    payload, _, sent = _register(client, monkeypatch)
    with SessionLocal() as db:
        row = db.scalar(select(EmailVerification))
        row.expira_em = clock.now_utc_naive() - timedelta(seconds=1)
        db.commit()
    assert _verify(client, payload["email"], sent[0][1]).status_code == 400


def test_used_code_cannot_be_reused(client, monkeypatch):
    payload, _, sent = _register(client, monkeypatch)
    assert _verify(client, payload["email"], sent[0][1]).status_code == 200
    assert _verify(client, payload["email"], sent[0][1]).status_code == 400


def test_resend_waits_sixty_seconds_invalidates_previous_code(client, monkeypatch):
    payload, _, sent = _register(client, monkeypatch)
    early = client.post(
        "/auth/email/reenviar-codigo", json={"email": payload["email"]}
    )
    assert early.status_code == 429
    assert int(early.headers["retry-after"]) > 0
    with SessionLocal() as db:
        row = db.scalar(select(EmailVerification))
        row.criado_em = clock.now_utc_naive() - timedelta(seconds=61)
        db.commit()
    resent = client.post(
        "/auth/email/reenviar-codigo", json={"email": payload["email"]}
    )
    assert resent.status_code == 200
    assert resent.json()["resend_after_seconds"] == 60
    assert len(sent) == 2
    assert _verify(client, payload["email"], sent[0][1]).status_code == 400
    assert _verify(client, payload["email"], sent[1][1]).status_code == 200
    with SessionLocal() as db:
        rows = list(db.scalars(select(EmailVerification).order_by(EmailVerification.id)))
        assert len(rows) == 2 and all(row.utilizado for row in rows)


def test_code_is_bound_to_registration_email(client, monkeypatch):
    first, _, sent = _register(client, monkeypatch)
    second_payload = {
        **data(),
        "name": "Joana Oliveira",
        "cpf": "12345678909",
        "email": "joana@example.com",
    }
    second = client.post("/auth/register", json=second_payload)
    assert second.status_code == 201
    response = _verify(client, second_payload["email"], sent[0][1])
    assert response.status_code == 400
    with SessionLocal() as db:
        users = list(db.scalars(select(User).order_by(User.id)))
        assert len(users) == 2 and all(not user.email_verificado for user in users)
    assert first["email"] != second_payload["email"]


@pytest.mark.parametrize(
    "field,value",
    [("cpf", "52998224725"), ("email", "maria@example.com")],
)
def test_duplicate_cpf_and_email_remain_blocked(client, monkeypatch, field, value):
    _register(client, monkeypatch)
    duplicate = {
        **data(),
        "name": "Joana Oliveira",
        "cpf": "12345678909",
        "email": "joana@example.com",
    }
    duplicate[field] = value
    response = client.post("/auth/register", json=duplicate)
    assert response.status_code == 409
    with SessionLocal() as db:
        assert db.scalar(select(func.count(User.id))) == 1


def test_opaque_token_corrects_email_and_old_code_is_invalid(client, monkeypatch):
    payload, response, sent = _register(client, monkeypatch)
    token = response.json()["verification_token"]
    corrected = client.post(
        "/auth/email/corrigir",
        json={"verification_token": token, "new_email": " Nova@Example.com "},
    )
    assert corrected.status_code == 200
    assert corrected.json()["email"] == "nova@example.com"
    assert _verify(client, payload["email"], sent[0][1]).status_code == 400
    requested = client.post(
        "/auth/email/solicitar-codigo", json={"email": "nova@example.com"}
    )
    assert requested.status_code == 200
    assert sent[-1][0] == "nova@example.com"
    assert _verify(client, "nova@example.com", sent[-1][1]).status_code == 200


def test_smtp_failure_rolls_back_registration_and_exposes_no_sensitive_detail(
    client, monkeypatch, caplog
):
    def unavailable(_email, _code):
        raise MailUnavailable("SMTP_AUTH_FAILED")

    monkeypatch.setattr(routes, "send_email_verification", unavailable)
    caplog.set_level(logging.INFO)
    payload = data()
    response = client.post("/auth/register", json=payload)
    assert response.status_code == 503
    assert "Não foi possível enviar" in response.json()["detail"]
    with SessionLocal() as db:
        assert db.scalar(select(func.count(User.id))) == 0
        assert db.scalar(select(func.count(EmailVerification.id))) == 0
    assert payload["password"] not in caplog.text
    assert payload["email"] not in caplog.text


def test_existing_verified_patient_and_staff_accounts_keep_working(client):
    with SessionLocal() as db:
        db.add_all(
            [
                User(
                    nome="Paciente Existente",
                    cpf="52998224725",
                    email="existente@example.com",
                    senha_hash=pwd.hash("Paciente@123"),
                    perfil="paciente",
                    ativo=True,
                    email_verificado=True,
                ),
                User(
                    nome="Recepção Existente",
                    cpf="12345678909",
                    email="recepcao@example.com",
                    senha_hash=pwd.hash("Recepcao@123"),
                    perfil="recepcao",
                    ativo=True,
                    email_verificado=False,
                ),
            ]
        )
        db.commit()
    assert login(client).status_code == 200
    assert login(client, "12345678909", "Recepcao@123").status_code == 200


def test_migration_preserves_existing_verified_state(client):
    with SessionLocal() as db:
        user = User(
            nome="Paciente Legado",
            cpf="52998224725",
            email="legado@example.com",
            senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente",
            email_verificado=True,
        )
        db.add(user)
        db.commit()
        user_id = user.id
    migrate_database()
    with SessionLocal() as db:
        assert db.get(User, user_id).email_verificado is True
