"""Canonical specialty presentation with legacy database compatibility."""

from datetime import datetime, timedelta

from sqlalchemy import select, text

from test_integration import client
from app.core import clock
from app.core.database import SessionLocal
from app.core.security import make_token, pwd
from app.models import Appointment, Specialty, User


def test_legacy_general_clinic_is_presented_canonically(client):
    with SessionLocal() as db:
        specialty = db.scalar(select(Specialty).limit(1))
        db.execute(
            text("UPDATE especialidades SET nome = :name WHERE id = :id"),
            {"name": "  CLÍNICA gera  ", "id": specialty.id},
        )
        patient = User(
            nome="Paciente Fictício",
            cpf="52998224725",
            email="patient@example.test",
            senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente",
            ativo=True,
            email_verificado=True,
        )
        doctor = User(
            nome="Médico Fictício",
            cpf="39053344705",
            email="doctor@example.test",
            senha_hash=pwd.hash("Medico@123"),
            perfil="medico",
            ativo=True,
            email_verificado=True,
        )
        db.add_all([patient, doctor])
        db.flush()
        appointment = Appointment(
            paciente_id=patient.id,
            medico_id=doctor.id,
            especialidade="Pediatria",
            data_horario=clock.now_sao_paulo_naive() + timedelta(days=2),
            status="agendado",
        )
        db.add(appointment)
        db.flush()
        db.execute(
            text("UPDATE consultas SET especialidade = :name WHERE id = :id"),
            {"name": "Clínica gera", "id": appointment.id},
        )
        db.commit()
        token = make_token(patient)

    headers = {"Authorization": f"Bearer {token}"}
    specialties = client.get("/specialties", headers=headers)
    assert specialties.status_code == 200
    assert specialties.json()[0]["name"] == "Clínica Geral"
    appointments = client.get("/appointments/me", headers=headers)
    assert appointments.status_code == 200
    assert appointments.json()[0]["specialty"] == "Clínica Geral"
