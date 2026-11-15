"""Filtros administrativos de auditoria e validações prioritárias."""

from datetime import datetime

from sqlalchemy import select

from test_integration import SessionLocal, _admin_headers, client

from app.core.security import make_token, pwd
from app.models import (
    Appointment,
    AuditLog,
    PriorityCondition,
    PriorityConditionHistory,
    User,
)


def _setup_history():
    with SessionLocal() as db:
        patient = User(
            nome="Paciente Ana Fictícia",
            cpf="52998224725",
            email="ana.history@example.com",
            senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente",
            email_verificado=True,
        )
        other_patient = User(
            nome="Paciente Bruno Fictício",
            cpf="39053344705",
            email="bruno.history@example.com",
            senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente",
            email_verificado=True,
        )
        reception = User(
            nome="Recepção Alice Fictícia",
            cpf="98765432100",
            email="alice.history@example.com",
            senha_hash=pwd.hash("Equipe@123"),
            perfil="recepcao",
        )
        doctor = User(
            nome="Dr. Lucas Histórico",
            cpf="16899535009",
            email="lucas.history@example.com",
            senha_hash=pwd.hash("Equipe@123"),
            perfil="medico",
        )
        db.add_all([patient, other_patient, reception, doctor])
        db.flush()
        appointment = Appointment(
            paciente_id=patient.id,
            medico_id=doctor.id,
            especialidade="Clínica Geral",
            data_horario=datetime(2026, 11, 10, 9),
            status="em_espera",
        )
        db.add(appointment)
        db.flush()
        condition = PriorityCondition(
            paciente_id=patient.id,
            condicao="pcd",
            status="confirmada",
            informada_em=datetime(2026, 11, 9, 15),
            validada_por=reception.id,
            validada_em=datetime(2026, 11, 10, 9, 30),
        )
        other_condition = PriorityCondition(
            paciente_id=other_patient.id,
            condicao="gestante",
            status="pendente",
            informada_em=datetime(2026, 11, 11, 15),
        )
        db.add_all([condition, other_condition])
        db.flush()
        db.add(PriorityConditionHistory(
            condicao_prioritaria_id=condition.id,
            status_anterior="pendente",
            status_novo="confirmada",
            alterado_por=reception.id,
            criado_em=datetime(2026, 11, 10, 12, 30),
        ))
        db.add_all([
            AuditLog(
                usuario_id=reception.id,
                acao="chegada_confirmada",
                tipo_registro="consulta",
                registro_id=appointment.id,
                detalhes='{"status_novo": "em_espera"}',
                criado_em=datetime(2026, 11, 10, 12),
            ),
            AuditLog(
                usuario_id=doctor.id,
                acao="atendimento_iniciado",
                tipo_registro="consulta",
                registro_id=appointment.id,
                detalhes='{"status_novo": "em_atendimento"}',
                criado_em=datetime(2026, 11, 11, 13),
            ),
        ])
        db.commit()
        return {
            "reception": {"Authorization": "Bearer " + make_token(reception)},
        }


def test_audit_filters_are_individual_and_combinable(client):
    admin, _ = _admin_headers()
    _setup_history()

    by_patient = client.get(
        "/admin/audit", headers=admin, params={"patient": "Ana Fictícia"}
    )
    assert by_patient.status_code == 200
    assert {item["action"] for item in by_patient.json()} == {
        "chegada_confirmada",
        "atendimento_iniciado",
    }

    combined = client.get(
        "/admin/audit",
        headers=admin,
        params={
            "patient": "Ana",
            "professional": "Lucas",
            "date_from": "2026-11-11",
            "date_to": "2026-11-11",
            "action": "atendimento_iniciado",
        },
    )
    assert combined.status_code == 200
    assert [item["action"] for item in combined.json()] == ["atendimento_iniciado"]


def test_priority_history_filters_and_safe_limit(client):
    admin, _ = _admin_headers()
    _setup_history()

    filtered = client.get(
        "/admin/priority-validations",
        headers=admin,
        params={
            "patient": "Ana",
            "professional": "Alice",
            "date_from": "2026-11-10",
            "date_to": "2026-11-10",
            "status": "confirmada",
        },
    )
    assert filtered.status_code == 200
    assert len(filtered.json()) == 1
    assert filtered.json()[0]["patient"] == "Paciente Ana Fictícia"
    assert filtered.json()[0]["history"][0]["new_status"] == "confirmada"

    empty_filters = client.get(
        "/admin/priority-validations", headers=admin, params={"limit": 1}
    )
    assert empty_filters.status_code == 200
    assert len(empty_filters.json()) == 1


def test_history_rejects_invalid_dates_and_ranges(client):
    admin, _ = _admin_headers()
    _setup_history()
    assert client.get(
        "/admin/audit", headers=admin, params={"date_from": "data-invalida"}
    ).status_code == 422
    invalid_range = client.get(
        "/admin/priority-validations",
        headers=admin,
        params={"date_from": "2026-11-12", "date_to": "2026-11-10"},
    )
    assert invalid_range.status_code == 422
    assert "data inicial" in invalid_range.text.lower()


def test_history_filters_are_admin_only(client):
    context = _setup_history()
    assert client.get("/admin/audit", headers=context["reception"]).status_code == 403
    assert client.get(
        "/admin/priority-validations", headers=context["reception"]
    ).status_code == 403
