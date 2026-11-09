"""Garante que as filas clínicas não voltem a executar consultas N+1."""

from datetime import datetime

from sqlalchemy import event, select

from test_integration import client
from app.core import clock
from app.core.database import SessionLocal, engine
from app.core.security import make_token, pwd
from app.models import (
    Appointment,
    ProfessionalProfile,
    RiskClassification,
    Specialty,
    User,
)


def _staff() -> tuple[User, User]:
    with SessionLocal() as db:
        specialty = db.scalar(
            select(Specialty).where(Specialty.nome == "Clínica Geral")
        )
        doctor = User(
            nome="Médico Contagem",
            cpf="70000000159",
            email="medico.contagem@example.test",
            senha_hash=pwd.hash("Medico@123"),
            perfil="medico",
            ativo=True,
        )
        nurse = User(
            nome="Enfermagem Contagem",
            cpf="70000000230",
            email="enfermagem.contagem@example.test",
            senha_hash=pwd.hash("Enfermagem@123"),
            perfil="enfermagem",
            ativo=True,
        )
        db.add_all([doctor, nurse])
        db.flush()
        db.add(
            ProfessionalProfile(
                usuario_id=nurse.id,
                registro_profissional="COREN-CONTAGEM-001",
                especialidade_id=specialty.id,
                autorizado_triagem=True,
                ativo=True,
            )
        )
        db.commit()
        db.refresh(doctor)
        db.refresh(nurse)
        db.expunge(doctor)
        db.expunge(nurse)
        return doctor, nurse


def _add_triaged_patients(doctor_id: int, nurse_id: int, start: int, end: int) -> None:
    now = clock.now_sao_paulo_naive().replace(second=0, microsecond=0)
    with SessionLocal() as db:
        for index in range(start, end):
            patient = User(
                nome=f"Paciente Contagem {index}",
                cpf=f"71000000{index:03d}",
                email=f"paciente.contagem.{index}@example.test",
                senha_hash=pwd.hash("Paciente@123"),
                perfil="paciente",
                ativo=True,
                data_nascimento=datetime(1990, 1, 1),
            )
            db.add(patient)
            db.flush()
            appointment = Appointment(
                paciente_id=patient.id,
                medico_id=doctor_id,
                especialidade="Clínica Geral",
                data_horario=now.replace(hour=8, minute=index),
                status="em_triagem",
                chegada_em=now,
                triagem_em=now,
                triagem_por=nurse_id,
                classificacao_risco="moderado",
            )
            db.add(appointment)
            db.flush()
            db.add(
                RiskClassification(
                    consulta_id=appointment.id,
                    profissional_id=nurse_id,
                    nivel_risco="moderado",
                    queixa_principal=f"Queixa determinística {index}",
                    sinais_vitais="PA 120/80",
                )
            )
        db.commit()


def _select_count(request) -> tuple[int, object]:
    statements = 0

    def count_selects(_connection, _cursor, statement, _parameters, _context, _many):
        nonlocal statements
        if statement.lstrip().upper().startswith("SELECT"):
            statements += 1

    event.listen(engine, "before_cursor_execute", count_selects)
    try:
        response = request()
    finally:
        event.remove(engine, "before_cursor_execute", count_selects)
    return statements, response


def test_medical_and_nursing_queue_queries_are_constant(client):
    doctor, nurse = _staff()
    medical_headers = {"Authorization": f"Bearer {make_token(doctor)}"}
    nursing_headers = {"Authorization": f"Bearer {make_token(nurse)}"}

    empty_medical_count, empty_medical = _select_count(
        lambda: client.get("/medico/fila", headers=medical_headers)
    )
    empty_nursing_count, empty_nursing = _select_count(
        lambda: client.get("/enfermagem/fila", headers=nursing_headers)
    )
    assert empty_medical.status_code == empty_nursing.status_code == 200
    assert empty_medical.json() == empty_nursing.json() == []

    _add_triaged_patients(doctor.id, nurse.id, 0, 1)
    one_medical_count, one_medical = _select_count(
        lambda: client.get("/medico/fila", headers=medical_headers)
    )
    one_nursing_count, one_nursing = _select_count(
        lambda: client.get("/enfermagem/fila", headers=nursing_headers)
    )
    assert len(one_medical.json()) == len(one_nursing.json()) == 1

    _add_triaged_patients(doctor.id, nurse.id, 1, 8)
    many_medical_count, many_medical = _select_count(
        lambda: client.get("/medico/fila", headers=medical_headers)
    )
    many_nursing_count, many_nursing = _select_count(
        lambda: client.get("/enfermagem/fila", headers=nursing_headers)
    )
    assert len(many_medical.json()) == len(many_nursing.json()) == 8
    assert many_medical_count == one_medical_count
    assert many_nursing_count == one_nursing_count
    assert one_medical_count <= empty_medical_count + 2
    assert one_nursing_count <= empty_nursing_count + 2
