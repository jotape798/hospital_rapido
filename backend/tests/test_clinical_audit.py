"""Auditoria clínica em SQLite temporário, sem conteúdo assistencial sensível."""
import json
from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from test_integration import SessionLocal, _admin_headers, client, header, register
from test_booking_flow import _booking_context, _payload
from test_staff_profiles import _login, _setup_staff_data

from app.core import clock
from app.core.security import make_token
from app.models import Appointment, AppointmentStatusHistory, AuditLog, User
from app.services import appointments as appointment_service
from app.services.appointments import mark_overdue_absences, register_manual_absence


def _events(appointment_id: int) -> list[AuditLog]:
    with SessionLocal() as db:
        return list(db.scalars(select(AuditLog).where(
            AuditLog.tipo_registro == "consulta",
            AuditLog.registro_id == appointment_id,
        ).order_by(AuditLog.id)))


def _assert_event(event: AuditLog, action: str, actor_id: int) -> dict:
    assert event.acao == action
    assert event.usuario_id == actor_id
    assert event.tipo_registro == "consulta"
    assert event.registro_id is not None
    assert event.criado_em is not None
    details = json.loads(event.detalhes or "{}")
    assert details["perfil_responsavel"]
    return details


def test_care_stages_are_audited_once_without_sensitive_details(client):
    appointment_id = _setup_staff_data()
    reception = _login(client, "98765432100", "Recepcao@123")
    nurse = _login(client, "39053344705", "Enfermagem@123")
    doctor = _login(client, "11144477735", "Profissional@123")
    with SessionLocal() as db:
        actors = {
            row.cpf: row.id for row in db.scalars(select(User).where(
                User.cpf.in_(["98765432100", "39053344705", "11144477735"])
            ))
        }

    refused = client.patch(
        f"/medico/atendimentos/{appointment_id}/iniciar", headers=doctor
    )
    assert refused.status_code == 409
    assert _events(appointment_id) == []

    assert client.patch(
        f"/recepcao/agendamentos/{appointment_id}/check-in", headers=reception
    ).status_code == 200
    assert client.patch(
        f"/recepcao/agendamentos/{appointment_id}/check-in", headers=reception
    ).status_code == 409
    assert client.patch(
        f"/enfermagem/agendamentos/{appointment_id}/classificacao-risco",
        headers=nurse,
        json={
            "level": "alto",
            "complaint": "Queixa clínica secreta.",
            "vital_signs": "Sinais vitais secretos.",
            "observation": "Observação clínica secreta.",
        },
    ).status_code == 200
    assert client.patch(
        f"/medico/atendimentos/{appointment_id}/iniciar", headers=doctor
    ).status_code == 200
    assert client.patch(
        f"/medico/atendimentos/{appointment_id}/concluir",
        headers=doctor,
        json={"summary": "Diagnóstico e resumo secretos."},
    ).status_code == 200
    assert client.patch(
        f"/medico/atendimentos/{appointment_id}/concluir",
        headers=doctor,
        json={"summary": "Tentativa recusada."},
    ).status_code == 409

    events = _events(appointment_id)
    assert [event.acao for event in events] == [
        "chegada_confirmada",
        "triagem_registrada",
        "atendimento_iniciado",
        "atendimento_concluido",
    ]
    actor_ids = [
        actors["98765432100"], actors["39053344705"],
        actors["11144477735"], actors["11144477735"],
    ]
    for event, action, actor_id in zip(events, [e.acao for e in events], actor_ids):
        _assert_event(event, action, actor_id)
    serialized = " ".join(event.detalhes or "" for event in events).casefold()
    for forbidden in ("queixa", "sinais vitais", "observação", "diagnóstico", "cpf", "email"):
        assert forbidden not in serialized


def test_cancellation_and_reschedule_are_audited_once(client):
    assert register(client).status_code == 201
    patient = header(client)
    context = _booking_context(slots=2)
    with SessionLocal() as db:
        patient_id = db.scalar(select(User.id).where(User.perfil == "paciente"))

    created = client.post("/appointments", headers=patient, json=_payload(context))
    appointment_id = created.json()["id"]
    moved_at = context["at"] + timedelta(hours=1)
    assert client.post(
        f"/appointments/{appointment_id}/reschedule",
        headers=patient,
        json={"doctor_id": context["doctor_id"], "scheduled_at": moved_at.isoformat()},
    ).status_code == 200
    assert client.post(
        f"/appointments/{appointment_id}/cancel", headers=patient
    ).status_code == 200
    assert client.post(
        f"/appointments/{appointment_id}/cancel", headers=patient
    ).status_code == 409

    events = _events(appointment_id)
    assert [event.acao for event in events] == [
        "consulta_reagendada", "consulta_cancelada"
    ]
    for event in events:
        details = _assert_event(event, event.acao, patient_id)
        assert "status_anterior" in details and "status_novo" in details


def test_existing_administrative_audit_remains_available(client):
    headers, admin_id = _admin_headers()
    created = client.post(
        "/admin/specialties", headers=headers, json={"name": "Especialidade Fictícia"}
    )
    assert created.status_code == 201
    with SessionLocal() as db:
        event = db.scalar(select(AuditLog).where(
            AuditLog.acao == "especialidade_criada"
        ))
        assert event.usuario_id == admin_id
        assert event.tipo_registro == "especialidade"
        assert event.registro_id == created.json()["id"]


def _absence_context(
    scheduled_at: datetime,
    *,
    status: str = "agendado",
    arrived_at=None,
    suffix: int = 0,
):
    with SessionLocal() as db:
        users = {
            role: User(
                nome=f"{role.title()} Ausência Fictício",
                cpf=f"70000{suffix:03d}{index:03d}",
                email=f"ausencia.{suffix}.{role}@example.com",
                senha_hash="não-utilizado",
                perfil=role,
                ativo=True,
            )
            for index, role in enumerate(
                ("paciente", "recepcao", "enfermagem", "medico", "admin"), start=1
            )
        }
        db.add_all(users.values())
        db.flush()
        appointment = Appointment(
            paciente_id=users["paciente"].id,
            medico_id=users["medico"].id,
            especialidade="Clínica Geral",
            data_horario=scheduled_at,
            status=status,
            chegada_em=arrived_at,
        )
        db.add(appointment)
        db.commit()
        db.refresh(appointment)
        return (
            appointment.id,
            {
                role: {"Authorization": f"Bearer {make_token(user)}"}
                for role, user in users.items()
            },
        )


def _absence_counts(appointment_id: int) -> tuple[int, int]:
    with SessionLocal() as db:
        history = db.scalar(select(func.count(AppointmentStatusHistory.id)).where(
            AppointmentStatusHistory.consulta_id == appointment_id,
            AppointmentStatusHistory.status_novo == "falta",
        ))
        audit = db.scalar(select(func.count(AuditLog.id)).where(
            AuditLog.tipo_registro == "consulta",
            AuditLog.registro_id == appointment_id,
            AuditLog.acao.in_(["falta_registrada", "falta_automatica"]),
        ))
        return history, audit


@pytest.mark.parametrize(
    ("method", "path_template", "actor_role"),
    [
        ("patch", "/recepcao/agendamentos/{id}/nao-compareceu", "recepcao"),
        ("post", "/admin/appointments/{id}/absence", "admin"),
    ],
)
@pytest.mark.parametrize(
    ("scheduled_delta", "expected_status"),
    [
        (timedelta(hours=2), 409),
        (-timedelta(minutes=14, seconds=59), 409),
        (-timedelta(minutes=15), 200),
    ],
)
def test_manual_absence_boundaries_are_identical_on_official_routes(
    client, monkeypatch, method, path_template, actor_role,
    scheduled_delta, expected_status,
):
    fixed_now = datetime(2026, 10, 21, 12, 0, 0)

    monkeypatch.setattr(
        appointment_service.clock, "now_sao_paulo_naive", lambda: fixed_now
    )
    appointment_id, headers = _absence_context(fixed_now + scheduled_delta)
    response = getattr(client, method)(
        path_template.format(id=appointment_id), headers=headers[actor_role]
    )
    assert response.status_code == expected_status

    with SessionLocal() as db:
        row = db.get(Appointment, appointment_id)
        if expected_status == 200:
            assert row.status == "falta"
            assert row.falta_em == fixed_now
            assert _absence_counts(appointment_id) == (1, 1)
            event = db.scalar(select(AuditLog).where(
                AuditLog.registro_id == appointment_id,
                AuditLog.acao == "falta_registrada",
            ))
            details = json.loads(event.detalhes)
            assert event.usuario_id is not None
            assert event.tipo_registro == "consulta"
            assert details == {
                "status_anterior": "agendado",
                "status_novo": "falta",
                "perfil_responsavel": actor_role,
            }
            assert not any(
                term in event.detalhes.casefold()
                for term in (
                    "cpf", "email", "queixa", "sinais", "observa",
                    "diagn", "resumo", "senha", "hash", "token",
                )
            )
        else:
            assert row.status == "agendado"
            assert row.falta_em is None
            assert _absence_counts(appointment_id) == (0, 0)


def test_manual_absence_duplicate_preserves_original_timestamp(client):
    fixed_now = datetime(2026, 10, 21, 12, 0, 0)
    appointment_id, _ = _absence_context(fixed_now - timedelta(minutes=15))
    with SessionLocal() as db:
        appointment = db.get(Appointment, appointment_id)
        actor = db.scalar(select(User).where(User.perfil == "recepcao"))
        register_manual_absence(db, appointment, actor, now=fixed_now)
        original = appointment.falta_em
        with pytest.raises(HTTPException) as error:
            register_manual_absence(
                db, appointment, actor, now=fixed_now + timedelta(minutes=1)
            )
        assert error.value.status_code == 409
        db.refresh(appointment)
        assert appointment.falta_em == original
    assert _absence_counts(appointment_id) == (1, 1)


def test_manual_absence_after_checkin_is_rejected_by_both_routes(client):
    appointment_id, headers = _absence_context(clock.now_sao_paulo_naive())
    checkin = client.patch(
        f"/recepcao/agendamentos/{appointment_id}/check-in",
        headers=headers["recepcao"],
    )
    assert checkin.status_code == 200
    arrived_at = checkin.json()["arrived_at"]

    assert client.patch(
        f"/recepcao/agendamentos/{appointment_id}/nao-compareceu",
        headers=headers["recepcao"],
    ).status_code == 409
    assert client.post(
        f"/admin/appointments/{appointment_id}/absence",
        headers=headers["admin"],
    ).status_code == 409

    with SessionLocal() as db:
        row = db.get(Appointment, appointment_id)
        assert row.status == "em_espera"
        assert row.chegada_em.isoformat() == arrived_at
        assert row.falta_em is None
    assert _absence_counts(appointment_id) == (0, 0)


def test_manual_absence_rejects_another_day(client, monkeypatch):
    fixed_now = datetime(2026, 10, 21, 12, 0, 0)

    monkeypatch.setattr(
        appointment_service.clock, "now_sao_paulo_naive", lambda: fixed_now
    )
    appointment_id, headers = _absence_context(fixed_now - timedelta(days=1))
    response = client.post(
        f"/admin/appointments/{appointment_id}/absence", headers=headers["admin"]
    )
    assert response.status_code == 409
    assert _absence_counts(appointment_id) == (0, 0)


@pytest.mark.parametrize("role", ["paciente", "enfermagem", "medico"])
def test_manual_absence_requires_reception_or_admin(client, role):
    appointment_id, headers = _absence_context(
        clock.now_sao_paulo_naive() - timedelta(hours=1)
    )
    response = client.patch(
        f"/recepcao/agendamentos/{appointment_id}/nao-compareceu",
        headers=headers[role],
    )
    assert response.status_code == 403
    assert _absence_counts(appointment_id) == (0, 0)


def test_automatic_absence_is_idempotent_and_skips_checkin(client):
    fixed_now = datetime(2026, 10, 21, 12, 0, 0)
    overdue_id, headers = _absence_context(fixed_now - timedelta(minutes=15))
    checked_id, _ = _absence_context(
        fixed_now - timedelta(hours=1),
        status="agendado",
        arrived_at=fixed_now - timedelta(minutes=50),
        suffix=1,
    )
    recent_id, _ = _absence_context(
        fixed_now - timedelta(minutes=14, seconds=59), suffix=2
    )

    with SessionLocal() as db:
        actor = db.scalar(select(User).where(User.perfil == "recepcao"))
        assert mark_overdue_absences(db, actor, now=fixed_now) == 1
        assert mark_overdue_absences(db, actor, now=fixed_now) == 0
        assert db.get(Appointment, overdue_id).status == "falta"
        assert db.get(Appointment, overdue_id).falta_em == fixed_now
        assert db.get(Appointment, checked_id).status == "agendado"
        assert db.get(Appointment, recent_id).status == "agendado"
    assert _absence_counts(overdue_id) == (1, 1)
    assert _absence_counts(checked_id) == (0, 0)
    assert _absence_counts(recent_id) == (0, 0)
