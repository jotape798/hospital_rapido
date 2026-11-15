"""Regressões direcionadas da criação idempotente dos cenários fictícios."""

from datetime import date, datetime, time

from sqlalchemy import func, select

from test_integration import client

from app.core import clock
from app.core.database import SessionLocal
from app.core.security import pwd
from app.models import Appointment, ProfessionalSchedule, User
from seed_demonstracao import (
    WORKFLOW_CASES,
    _next_weekday,
    ensure_demo_accounts,
    ensure_demo_schedules,
    ensure_demo_workflow,
)


def _prepare() -> None:
    ensure_demo_accounts()
    ensure_demo_schedules()


def _intended_first_slot() -> datetime:
    return datetime.combine(_next_weekday(clock.today_sao_paulo()), time(7))


def test_workflow_is_stable_across_three_runs(client):
    _prepare()
    first = ensure_demo_workflow()
    with SessionLocal() as db:
        first_count = db.scalar(select(func.count(Appointment.id)))
    second = ensure_demo_workflow()
    third = ensure_demo_workflow()
    with SessionLocal() as db:
        final_count = db.scalar(select(func.count(Appointment.id)))
    assert sum(status.startswith("criada") for _, status in first) == len(WORKFLOW_CASES)
    assert all(status.startswith("já existia") for _, status in second + third)
    assert final_count == first_count == len(WORKFLOW_CASES)


def test_occupied_slot_uses_next_free_schedule_without_changing_existing(client):
    _prepare()
    intended = _intended_first_slot()
    with SessionLocal() as db:
        doctor = db.scalar(select(User).where(User.cpf == "39053344705"))
        occupant = User(
            nome="Paciente Ocupante Fictício", cpf="70000000906",
            email="ocupante@example.test", senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente", ativo=True,
        )
        db.add(occupant)
        db.flush()
        existing = Appointment(
            paciente_id=occupant.id, medico_id=doctor.id,
            especialidade="Clínica Geral", data_horario=intended,
            status="agendado",
        )
        db.add(existing)
        db.commit()
        existing_id = existing.id
        original = (existing.paciente_id, existing.medico_id, existing.data_horario, existing.status)

    results = ensure_demo_workflow()

    with SessionLocal() as db:
        existing = db.get(Appointment, existing_id)
        patient = db.scalar(select(User).where(User.cpf == WORKFLOW_CASES[0].cpf))
        created = db.scalar(select(Appointment).where(Appointment.paciente_id == patient.id))
        scheduled = db.scalar(select(ProfessionalSchedule.id).where(
            ProfessionalSchedule.medico_id == created.medico_id,
            ProfessionalSchedule.data_horario == created.data_horario,
            ProfessionalSchedule.especialidade == created.especialidade,
        ))
        assert (existing.paciente_id, existing.medico_id, existing.data_horario, existing.status) == original
        assert created.data_horario > intended
        assert scheduled is not None
    assert results[0][1] == "criada no próximo horário livre"


def test_no_free_schedule_warns_and_does_not_create_partial_scenario(client):
    ensure_demo_accounts()
    intended = _intended_first_slot()
    with SessionLocal() as db:
        doctor = db.scalar(select(User).where(User.cpf == "39053344705"))
        occupant = User(
            nome="Paciente Sem Vaga Fictício", cpf="70000000906",
            email="sem-vaga@example.test", senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente", ativo=True,
        )
        db.add(occupant)
        db.flush()
        existing = Appointment(
            paciente_id=occupant.id, medico_id=doctor.id,
            especialidade="Clínica Geral", data_horario=intended,
            status="agendado",
        )
        db.add(existing)
        db.commit()
        existing_id = existing.id

    results = ensure_demo_workflow()

    with SessionLocal() as db:
        assert db.get(Appointment, existing_id).status == "agendado"
        assert db.scalar(select(User).where(User.cpf == WORKFLOW_CASES[0].cpf)) is None
    assert results[0][1] == "aviso: sem horário futuro livre; cenário não criado"
