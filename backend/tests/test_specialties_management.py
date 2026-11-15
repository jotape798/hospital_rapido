"""Gestão administrativa de especialidades e preservação de vínculos."""
from datetime import datetime, timedelta
import atexit
import os
import secrets
import tempfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
# O arquivo também pode ser executado isoladamente sem tocar no SQLite real.
_TEST_DIR = tempfile.TemporaryDirectory()
os.environ["DATABASE_URL"] = "sqlite:///" + str(Path(_TEST_DIR.name) / "specialties.db")
os.environ["JWT_SECRET_KEY"] = secrets.token_urlsafe(48)
os.environ["SEED_DEMO_DATA"] = "false"

from app.core.database import Base, SessionLocal, engine
from app.core import clock
from app.core.security import make_token, pwd
from app.main import app
from app.models import Appointment, ProfessionalProfile, ProfessionalSchedule, Specialty, User

atexit.register(engine.dispose)


@pytest.fixture()
def client():
    Base.metadata.drop_all(engine)
    with TestClient(app) as value:
        yield value


def _user(role: str, index: int) -> User:
    return User(
        nome=f"Usuário {role.title()}",
        cpf=f"{index:011d}",
        email=f"{role}.{index}@example.test",
        senha_hash=pwd.hash("Equipe@123"),
        perfil=role,
        ativo=True,
        email_verificado=True,
    )


def _headers(role: str = "admin", index: int = 1) -> dict[str, str]:
    with SessionLocal() as db:
        user = _user(role, index)
        db.add(user)
        db.commit()
        db.refresh(user)
        return {"Authorization": f"Bearer {make_token(user)}"}


def test_admin_creates_valid_specialty_and_blocks_empty_or_duplicate(client):
    headers = _headers()

    created = client.post(
        "/admin/specialties",
        headers=headers,
        json={"name": "  Pediatria   Clínica  "},
    )
    assert created.status_code == 201
    assert created.json() == {
        "id": created.json()["id"],
        "name": "Pediatria Clínica",
        "active": True,
    }

    empty = client.post(
        "/admin/specialties", headers=headers, json={"name": "   "}
    )
    assert empty.status_code == 422
    assert empty.json()["detail"] == {
        "field": "name",
        "message": "Informe o nome da especialidade.",
    }

    duplicate = client.post(
        "/admin/specialties",
        headers=headers,
        json={"name": "pEDIATRIA clÍNICA"},
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == "Especialidade já cadastrada"


def test_admin_edits_specialty_and_keeps_schedules_and_appointments_linked(client):
    headers = _headers()
    with SessionLocal() as db:
        specialty = Specialty(nome="Cardiologia Integrada", ativo=True)
        doctor = _user("medico", 20)
        patient = _user("paciente", 21)
        db.add_all([specialty, doctor, patient])
        db.flush()
        profile = ProfessionalProfile(
            usuario_id=doctor.id,
            registro_profissional="CRM-TESTE-20",
            especialidade_id=specialty.id,
        )
        scheduled_at = clock.now_sao_paulo_naive() + timedelta(days=3)
        schedule = ProfessionalSchedule(
            medico_id=doctor.id,
            data_horario=scheduled_at,
            especialidade=specialty.nome,
        )
        appointment = Appointment(
            paciente_id=patient.id,
            medico_id=doctor.id,
            especialidade=specialty.nome,
            data_horario=scheduled_at,
            status="agendado",
        )
        db.add_all([profile, schedule, appointment])
        db.commit()
        specialty_id = specialty.id
        profile_id = profile.id
        schedule_id = schedule.id
        appointment_id = appointment.id

    updated = client.put(
        f"/admin/specialties/{specialty_id}",
        headers=headers,
        json={"name": "Cardiologia da Família"},
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "Cardiologia da Família"

    with SessionLocal() as db:
        assert db.get(ProfessionalProfile, profile_id).especialidade_id == specialty_id
        assert db.get(ProfessionalSchedule, schedule_id).especialidade == "Cardiologia da Família"
        assert db.get(Appointment, appointment_id).especialidade == "Cardiologia da Família"


def test_admin_activates_and_deactivates_without_hiding_historical_record(client):
    admin_headers = _headers()
    patient_headers = _headers("paciente", 30)
    created = client.post(
        "/admin/specialties",
        headers=admin_headers,
        json={"name": "Dermatologia Comunitária"},
    ).json()
    specialty_id = created["id"]

    deactivated = client.post(
        f"/admin/specialties/{specialty_id}/deactivate", headers=admin_headers
    )
    assert deactivated.status_code == 200
    assert deactivated.json()["active"] is False
    patient_names = [
        item["name"]
        for item in client.get("/specialties", headers=patient_headers).json()
    ]
    assert "Dermatologia Comunitária" not in patient_names
    admin_item = next(
        item
        for item in client.get("/admin/specialties", headers=admin_headers).json()
        if item["id"] == specialty_id
    )
    assert admin_item["active"] is False

    activated = client.post(
        f"/admin/specialties/{specialty_id}/activate", headers=admin_headers
    )
    assert activated.status_code == 200
    assert activated.json()["active"] is True


@pytest.mark.parametrize(
    ("role", "index"),
    [("paciente", 40), ("recepcao", 41), ("enfermagem", 42), ("medico", 43)],
)
def test_non_admin_profiles_cannot_create_or_edit_specialties(client, role, index):
    admin_headers = _headers("admin", 39)
    specialty_id = client.post(
        "/admin/specialties",
        headers=admin_headers,
        json={"name": "Especialidade Protegida"},
    ).json()["id"]
    headers = _headers(role, index)

    assert client.post(
        "/admin/specialties",
        headers=headers,
        json={"name": f"Especialidade {role}"},
    ).status_code == 403
    assert client.put(
        f"/admin/specialties/{specialty_id}",
        headers=headers,
        json={"name": "Alteração indevida"},
    ).status_code == 403
