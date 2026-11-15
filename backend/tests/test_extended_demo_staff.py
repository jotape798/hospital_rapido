from datetime import datetime

from sqlalchemy import func, select

from app.core import clock
from app.core.demo_accounts import DEMO_ACCOUNTS
from app.core.extended_demo_staff import EXTENDED_DEMO_STAFF
from app.core.database import SessionLocal
from app.models import (
    Appointment,
    ProfessionalProfile,
    ProfessionalSchedule,
    RiskClassification,
    ScheduleGrid,
    Specialty,
    User,
)
from app.services.demo_seed import ensure_canonical_demo_accounts
from app.services.extended_demo_seed import ensure_extended_demo_staff
from test_integration import client


def _access_values(path):
    return {
        key.strip(): value.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#") and "=" in line
        for key, value in [line.split("=", 1)]
    }


def _login(client, cpf, password):
    response = client.post(
        "/auth/login", json={"document": cpf, "password": password}
    )
    assert response.status_code == 200
    return response.json(), {
        "Authorization": f"Bearer {response.json()['access_token']}"
    }


def _prepare_twice(access_file):
    with SessionLocal() as db:
        ensure_canonical_demo_accounts(db)
        db.commit()
    with SessionLocal() as db:
        first = ensure_extended_demo_staff(db, access_file)
        db.commit()
    with SessionLocal() as db:
        second = ensure_extended_demo_staff(db, access_file)
        db.commit()
    return first, second


def test_extended_demo_seed_is_idempotent_and_keeps_professional_identity(
    client, tmp_path
):
    access_file = tmp_path / "profissionais_demo.env.local"
    first, second = _prepare_twice(access_file)

    assert first.created_by_role == {
        "recepcao": 3,
        "enfermagem": 3,
        "medico": 6,
    }
    assert first.grids_created == 30
    assert first.slots_created == 300
    assert second.created_by_role == {}
    assert second.existing_users == 12
    assert second.specialties_created == 0
    assert second.grids_created == 0
    assert second.slots_created == 0
    assert access_file.exists()

    with SessionLocal() as db:
        emails = [
            f"demo.staff.{spec.key}@ubs-rapida.local"
            for spec in EXTENDED_DEMO_STAFF
        ]
        users = list(db.scalars(select(User).where(User.email.in_(emails))))
        assert len(users) == 12
        assert db.scalar(select(func.count(ScheduleGrid.id)).where(
            ScheduleGrid.profissional_id.in_([u.id for u in users])
        )) == 30
        assert db.scalar(select(func.count(ProfessionalSchedule.id)).where(
            ProfessionalSchedule.medico_id.in_([u.id for u in users])
        )) == 300
        assert len({row.nome for row in db.scalars(select(Specialty))}) == db.scalar(
            select(func.count(Specialty.id))
        )
        for spec in EXTENDED_DEMO_STAFF:
            user = next(row for row in users if row.nome == spec.name)
            profile = db.scalar(select(ProfessionalProfile).where(
                ProfessionalProfile.usuario_id == user.id
            ))
            if spec.role == "recepcao":
                assert profile is None
            else:
                assert profile.registro_profissional == spec.registration
                assert profile.especialidade.nome == spec.specialty
                assert profile.autorizado_triagem is (spec.role == "enfermagem")


def test_extended_demo_logins_catalog_booking_care_and_access_isolation(
    client, tmp_path
):
    access_file = tmp_path / "profissionais_demo.env.local"
    _prepare_twice(access_file)
    access = _access_values(access_file)
    headers_by_key = {}

    for spec in EXTENDED_DEMO_STAFF:
        prefix = spec.key.upper()
        body, headers = _login(
            client, access[f"{prefix}_CPF"], access[f"{prefix}_SENHA"]
        )
        assert body["user"]["role"] == spec.role
        headers_by_key[spec.key] = headers
        if spec.role == "recepcao":
            assert "appointments:checkin" in body["permissions"]
        elif spec.role == "enfermagem":
            assert "triage:write" in body["permissions"]
        else:
            assert "care:update" in body["permissions"]
            assert client.get("/admin/users", headers=headers).status_code == 403
            assert client.get("/enfermagem/fila", headers=headers).status_code == 403

    admin = next(item for item in DEMO_ACCOUNTS if item.role == "admin")
    _, admin_headers = _login(client, admin.cpf, admin.password)
    users = client.get("/admin/users", headers=admin_headers)
    assert users.status_code == 200
    added = {row["name"]: row for row in users.json() if row["name"] in {
        spec.name for spec in EXTENDED_DEMO_STAFF
    }}
    assert len(added) == 12
    assert added["Carolina Fernandes"]["profession"] == "Dentista"
    assert added["Carolina Fernandes"]["specialty"] == "Odontologia"

    doctors = client.get("/admin/medicos", headers=admin_headers)
    assert doctors.status_code == 200
    carolina_admin = next(
        row for row in doctors.json() if row["name"] == "Carolina Fernandes"
    )
    assert carolina_admin["profession"] == "Dentista"
    assert carolina_admin["specialty"] == "Odontologia"

    patient = next(item for item in DEMO_ACCOUNTS if item.role == "paciente")
    _, patient_headers = _login(client, patient.cpf, patient.password)
    specialties = client.get("/specialties", headers=patient_headers)
    assert specialties.status_code == 200
    assert {row["name"] for row in specialties.json()} >= {
        "Clínica Geral", "Cardiologia", "Pediatria", "Ginecologia", "Odontologia"
    }
    professionals = client.get(
        "/professionals?specialty=Odontologia", headers=patient_headers
    )
    assert professionals.status_code == 200
    assert {row["name"] for row in professionals.json()} == {
        "Carolina Fernandes", "Gabriel Ribeiro"
    }
    carolina = next(row for row in professionals.json() if row["name"] == "Carolina Fernandes")
    dates = client.get(
        f"/availability/calendar-dates?specialty=Odontologia&doctor_id={carolina['id']}",
        headers=patient_headers,
    )
    assert dates.status_code == 200 and dates.json()
    day = dates.json()[0]
    times = client.get(
        f"/availability/calendar-times?specialty=Odontologia&doctor_id={carolina['id']}&day={day}",
        headers=patient_headers,
    )
    available = next(row for row in times.json() if row["selectable"])
    booked = client.post(
        "/appointments",
        headers=patient_headers,
        json={
            "doctor_id": carolina["id"],
            "specialty": "Odontologia",
            "scheduled_at": available["scheduled_at"],
        },
    )
    assert booked.status_code == 201

    with SessionLocal() as db:
        appointment = db.get(Appointment, booked.json()["id"])
        nurse = db.scalar(select(User).where(
            User.email == "demo.staff.juliana_ferreira_lima@ubs-rapida.local"
        ))
        appointment.data_horario = datetime.combine(
            clock.today_sao_paulo(), datetime.min.time()
        ).replace(hour=10)
        appointment.status = "em_triagem"
        appointment.classificacao_risco = "baixo"
        appointment.chegada_em = clock.now_sao_paulo_naive()
        appointment.triagem_em = clock.now_sao_paulo_naive()
        appointment.triagem_por = nurse.id
        db.add(RiskClassification(
            consulta_id=appointment.id,
            profissional_id=nurse.id,
            nivel_risco="baixo",
            queixa_principal="Queixa odontológica fictícia.",
            sinais_vitais="Sinais vitais fictícios estáveis.",
        ))
        db.commit()

    carolina_headers = headers_by_key["carolina_fernandes"]
    gabriel_headers = headers_by_key["gabriel_ribeiro"]
    own_queue = client.get("/medico/fila", headers=carolina_headers)
    other_queue = client.get("/medico/fila", headers=gabriel_headers)
    assert [row["id"] for row in own_queue.json()] == [booked.json()["id"]]
    assert other_queue.json() == []
    started = client.patch(
        f"/medico/atendimentos/{booked.json()['id']}/iniciar",
        headers=carolina_headers,
    )
    assert started.status_code == 200
    completed = client.patch(
        f"/medico/atendimentos/{booked.json()['id']}/concluir",
        headers=carolina_headers,
        json={"summary": "Atendimento odontológico fictício concluído."},
    )
    assert completed.status_code == 200
    assert completed.json()["status"] == "concluido"
