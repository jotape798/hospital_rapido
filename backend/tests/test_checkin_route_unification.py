"""Contrato único de check-in, com banco SQLite temporário da suíte."""

import json
from datetime import datetime, timedelta
from pathlib import Path

from sqlalchemy import select

from test_integration import SessionLocal, client
from test_staff_profiles import _login, _setup_staff_data

from app.core import clock
from app.core.security import pwd
from app.models import Appointment, AppointmentStatusHistory, AuditLog, User


FIXED_NOW = datetime(2026, 11, 8, 10, 30)
OFFICIAL_ROUTE = "/recepcao/agendamentos/{appointment_id}/check-in"
REMOVED_ROUTE = "/admin/appointments/{appointment_id}/check-in"


def _freeze_ubs_clock(monkeypatch) -> None:
    monkeypatch.setattr(clock, "today_sao_paulo", lambda: FIXED_NOW.date())
    monkeypatch.setattr(clock, "now_sao_paulo_naive", lambda: FIXED_NOW)


def _context(monkeypatch):
    _freeze_ubs_clock(monkeypatch)
    appointment_id = _setup_staff_data()
    with SessionLocal() as db:
        appointment = db.get(Appointment, appointment_id)
        appointment.data_horario = FIXED_NOW.replace(hour=10)
        admin = User(
            nome="Administradora Fictícia",
            cpf="12345678909",
            email="admin.checkin@example.test",
            senha_hash=pwd.hash("Admin@123"),
            perfil="admin",
            ativo=True,
        )
        db.add(admin)
        db.commit()
    return appointment_id


def test_official_route_preserves_reception_rules_audit_and_masked_cpf(
    client, monkeypatch
):
    appointment_id = _context(monkeypatch)
    reception = _login(client, "98765432100", "Recepcao@123")
    with SessionLocal() as db:
        actor_id = db.scalar(select(User.id).where(User.cpf == "98765432100"))

    response = client.patch(
        OFFICIAL_ROUTE.format(appointment_id=appointment_id), headers=reception
    )
    assert response.status_code == 200
    assert response.json()["status"] == "em_espera"
    assert response.json()["patient_document"] == "***.***.***-25"

    duplicate = client.patch(
        OFFICIAL_ROUTE.format(appointment_id=appointment_id), headers=reception
    )
    assert duplicate.status_code == 409
    no_show = client.patch(
        f"/recepcao/agendamentos/{appointment_id}/nao-compareceu",
        headers=reception,
    )
    assert no_show.status_code == 409

    with SessionLocal() as db:
        history = db.scalar(
            select(AppointmentStatusHistory).where(
                AppointmentStatusHistory.consulta_id == appointment_id
            )
        )
        event = db.scalar(
            select(AuditLog).where(
                AuditLog.acao == "chegada_confirmada",
                AuditLog.registro_id == appointment_id,
            )
        )
        assert history.status_anterior == "agendado"
        assert history.status_novo == "em_espera"
        assert history.alterado_por == actor_id
        assert event.usuario_id == actor_id
        assert event.criado_em is not None
        details = json.loads(event.detalhes)
        assert details["status_anterior"] == "agendado"
        assert details["status_novo"] == "em_espera"
        assert details["perfil_responsavel"] == "recepcao"


def test_official_route_authorization_missing_invalid_and_admin(client, monkeypatch):
    appointment_id = _context(monkeypatch)
    route = OFFICIAL_ROUTE.format(appointment_id=appointment_id)
    assert client.patch(route).status_code == 401

    nurse = _login(client, "39053344705", "Enfermagem@123")
    assert client.patch(route, headers=nurse).status_code == 403
    reception = _login(client, "98765432100", "Recepcao@123")
    assert client.patch(
        OFFICIAL_ROUTE.format(appointment_id=999999), headers=reception
    ).status_code == 404

    admin = _login(client, "12345678909", "Admin@123")
    assert client.patch(route, headers=admin).status_code == 200


def test_official_route_rejects_wrong_day_and_removed_route_is_404(
    client, monkeypatch
):
    appointment_id = _context(monkeypatch)
    reception = _login(client, "98765432100", "Recepcao@123")
    with SessionLocal() as db:
        appointment = db.get(Appointment, appointment_id)
        appointment.data_horario = FIXED_NOW + timedelta(days=1)
        db.commit()

    assert client.patch(
        OFFICIAL_ROUTE.format(appointment_id=appointment_id), headers=reception
    ).status_code == 409
    assert client.post(
        REMOVED_ROUTE.format(appointment_id=appointment_id), headers=reception
    ).status_code == 404


def test_openapi_and_flutter_expose_only_official_checkin(client):
    schema = client.get("/openapi.json").json()
    checkin_paths = [path for path in schema["paths"] if path.endswith("/check-in")]
    assert checkin_paths == ["/recepcao/agendamentos/{appointment_id}/check-in"]
    operation = schema["paths"][checkin_paths[0]]["patch"]
    assert operation["summary"] == "Registrar check-in presencial"
    assert "Recepção e Administrador" in operation["description"]
    assert {"200", "401", "403", "404", "409"}.issubset(operation["responses"])

    service = (
        Path(__file__).parents[2] / "frontend" / "lib" / "services" / "api_service.dart"
    ).read_text(encoding="utf-8")
    assert "/admin/appointments/$id/check-in" not in service
    assert "'/recepcao/agendamentos/$id/check-in'" in service
