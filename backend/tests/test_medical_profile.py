from datetime import datetime

from sqlalchemy import select

from app.core import clock
from app.core.database import SessionLocal
from app.core.security import pwd
from app.models import Appointment, ProfessionalProfile, RiskClassification, Specialty, User
from app.main import migrate_database
from test_integration import client


def _login(client, cpf: str, password: str) -> dict[str, str]:
    response = client.post(
        "/auth/login", json={"document": cpf, "password": password}
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _setup_medical_flow() -> tuple[int, int]:
    with SessionLocal() as db:
        specialty = db.scalar(select(Specialty).where(Specialty.nome == "Clínica Geral"))
        doctor = User(
            nome="Doutor Médico",
            cpf="11144477735",
            email="medico.teste@ubs.local",
            senha_hash=pwd.hash("Medico@123"),
            perfil="medico",
            ativo=True,
        )
        other_doctor = User(
            nome="Outro Médico",
            cpf="52998224725",
            email="outro.medico@ubs.local",
            senha_hash=pwd.hash("Medico@123"),
            perfil="medico",
            ativo=True,
        )
        nurse = User(
            nome="Enfermeira Teste",
            cpf="39053344705",
            email="enfermagem.medico@ubs.local",
            senha_hash=pwd.hash("Enfermagem@123"),
            perfil="enfermagem",
            ativo=True,
        )
        patient = User(
            nome="Paciente Triado",
            cpf="12345678909",
            email="paciente.medico@ubs.local",
            senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente",
            ativo=True,
            data_nascimento=datetime(1990, 1, 15),
            e_prioridade="geral",
        )
        db.add_all([doctor, other_doctor, nurse, patient])
        db.flush()
        db.add_all(
            [
                ProfessionalProfile(
                    usuario_id=doctor.id,
                    registro_profissional="CRM-TESTE-001",
                    especialidade_id=specialty.id,
                    ativo=True,
                ),
                ProfessionalProfile(
                    usuario_id=other_doctor.id,
                    registro_profissional="CRM-TESTE-002",
                    especialidade_id=specialty.id,
                    ativo=True,
                ),
                ProfessionalProfile(
                    usuario_id=nurse.id,
                    registro_profissional="COREN-TESTE-001",
                    especialidade_id=specialty.id,
                    autorizado_triagem=True,
                    ativo=True,
                ),
            ]
        )
        appointment = Appointment(
            paciente_id=patient.id,
            medico_id=doctor.id,
            especialidade="Clínica Geral",
            data_horario=clock.now_sao_paulo_naive().replace(hour=10, minute=0, second=0, microsecond=0),
            status="em_triagem",
            classificacao_risco="alto",
            chegada_em=clock.now_sao_paulo_naive(),
            triagem_em=clock.now_sao_paulo_naive(),
            triagem_por=nurse.id,
        )
        db.add(appointment)
        db.flush()
        db.add(
            RiskClassification(
                consulta_id=appointment.id,
                profissional_id=nurse.id,
                nivel_risco="alto",
                queixa_principal="Dor fictícia para demonstração.",
                sinais_vitais="PA fictícia 120/80.",
                observacao="Observação fictícia.",
            )
        )
        db.commit()
        return appointment.id, patient.id


def test_medical_login_queue_and_complete_with_summary(client):
    appointment_id, _ = _setup_medical_flow()
    login = client.post(
        "/auth/login",
        json={"document": "11144477735", "password": "Medico@123"},
    )
    assert login.status_code == 200
    assert login.json()["user"]["role"] == "medico"
    assert "care:update" in login.json()["permissions"]
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    queue = client.get("/medico/fila", headers=headers)
    assert queue.status_code == 200
    assert [item["id"] for item in queue.json()] == [appointment_id]
    assert queue.json()[0]["patient"] == "Paciente Triado"
    assert queue.json()[0]["age"] >= 18
    assert queue.json()[0]["triage_complaint"] == "Dor fictícia para demonstração."

    started = client.patch(
        f"/medico/atendimentos/{appointment_id}/iniciar", headers=headers
    )
    assert started.status_code == 200
    assert started.json()["status"] == "em_atendimento"

    missing = client.patch(
        f"/medico/atendimentos/{appointment_id}/concluir",
        headers=headers,
        json={"summary": ""},
    )
    assert missing.status_code == 422

    whitespace_only = client.patch(
        f"/medico/atendimentos/{appointment_id}/concluir",
        headers=headers,
        json={"summary": "   \t  "},
    )
    assert whitespace_only.status_code == 422

    completed = client.patch(
        f"/medico/atendimentos/{appointment_id}/concluir",
        headers=headers,
        json={"summary": "Atendimento fictício concluído sem prescrição."},
    )
    assert completed.status_code == 200
    assert completed.json()["status"] == "concluido"
    assert completed.json()["care_summary"] == "Atendimento fictício concluído sem prescrição."

    with SessionLocal() as db:
        row = db.get(Appointment, appointment_id)
        doctor = db.scalar(select(User).where(User.cpf == "11144477735"))
        assert row.resumo_atendimento == "Atendimento fictício concluído sem prescrição."
        assert row.atendimento_medico_id == doctor.id


def test_medical_access_is_limited_to_assigned_triaged_patients(client):
    appointment_id, patient_id = _setup_medical_flow()
    doctor = _login(client, "11144477735", "Medico@123")
    other = _login(client, "52998224725", "Medico@123")

    assert client.get("/admin/users", headers=doctor).status_code == 403
    assert client.get("/schedules", headers=doctor).status_code == 403
    assert client.get("/enfermagem/fila", headers=doctor).status_code == 403
    assert (
        client.get(f"/medico/atendimentos/{appointment_id}", headers=other).status_code
        == 403
    )

    with SessionLocal() as db:
        assigned_doctor = db.scalar(select(User).where(User.cpf == "11144477735"))
        untriaged = Appointment(
            paciente_id=patient_id,
            medico_id=assigned_doctor.id,
            especialidade="Clínica Geral",
            data_horario=clock.now_sao_paulo_naive().replace(hour=11, minute=0, second=0, microsecond=0),
            status="em_espera",
            chegada_em=clock.now_sao_paulo_naive(),
        )
        db.add(untriaged)
        db.commit()
        untriaged_id = untriaged.id

    assert (
        client.patch(
            f"/medico/atendimentos/{untriaged_id}/iniciar", headers=doctor
        ).status_code
        == 409
    )
    assert [item["id"] for item in client.get("/medico/fila", headers=doctor).json()] == [
        appointment_id
    ]


def test_patient_cannot_be_in_two_simultaneous_medical_visits(client):
    first_id, patient_id = _setup_medical_flow()
    headers = _login(client, "11144477735", "Medico@123")
    with SessionLocal() as db:
        doctor = db.scalar(select(User).where(User.cpf == "11144477735"))
        nurse = db.scalar(select(User).where(User.cpf == "39053344705"))
        second = Appointment(
            paciente_id=patient_id,
            medico_id=doctor.id,
            especialidade="Clínica Geral",
            data_horario=clock.now_sao_paulo_naive().replace(hour=11, minute=0, second=0, microsecond=0),
            status="em_triagem",
            classificacao_risco="moderado",
            chegada_em=clock.now_sao_paulo_naive(),
            triagem_em=clock.now_sao_paulo_naive(),
            triagem_por=nurse.id,
        )
        db.add(second)
        db.flush()
        db.add(
            RiskClassification(
                consulta_id=second.id,
                profissional_id=nurse.id,
                nivel_risco="moderado",
                queixa_principal="Segunda queixa fictícia.",
                sinais_vitais="Sinais vitais fictícios.",
            )
        )
        db.commit()
        second_id = second.id

    assert client.patch(
        f"/medico/atendimentos/{first_id}/iniciar", headers=headers
    ).status_code == 200
    conflict = client.patch(
        f"/medico/atendimentos/{second_id}/iniciar", headers=headers
    )
    assert conflict.status_code == 409


def test_admin_manages_doctors_without_exposing_credentials(client):
    with SessionLocal() as db:
        admin = User(
            nome="Administrador Teste",
            cpf="11144477735",
            email="admin.medicos@ubs.local",
            senha_hash=pwd.hash("Admin@123"),
            perfil="admin",
            ativo=True,
        )
        db.add(admin)
        db.commit()
    headers = _login(client, "11144477735", "Admin@123")

    created = client.post(
        "/admin/medicos",
        headers=headers,
        json={
            "name": "Doutora Criada",
            "cpf": "52998224725",
            "password": "Medico@123",
            "password_confirmation": "Medico@123",
            "active": True,
        },
    )
    assert created.status_code == 201
    body = created.json()
    assert body["role"] == "medico"
    assert body["active"] is True
    assert "password" not in body and "senha_hash" not in body

    duplicate = client.post(
        "/admin/medicos",
        headers=headers,
        json={
            "name": "Outra Doutora",
            "cpf": "52998224725",
            "password": "Medico@123",
            "password_confirmation": "Medico@123",
            "active": True,
        },
    )
    assert duplicate.status_code == 409

    listing = client.get("/admin/medicos?q=Criada", headers=headers)
    assert listing.status_code == 200
    assert [item["id"] for item in listing.json()] == [body["id"]]

    updated = client.put(
        f"/admin/medicos/{body['id']}",
        headers=headers,
        json={"name": "Doutora Atualizada", "cpf": "12345678909", "active": False},
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "Doutora Atualizada"
    assert updated.json()["active"] is False
    assert (
        client.post(
            "/auth/login",
            json={"document": "12345678909", "password": "Medico@123"},
        ).status_code
        == 401
    )


def test_legacy_professional_migration_preserves_ids_and_links(client):
    with SessionLocal() as db:
        legacy = User(
            nome="Médico Legado",
            cpf="45678912364",
            email="legado@ubs.local",
            senha_hash=pwd.hash("Medico@123"),
            perfil="profissional",
            ativo=True,
        )
        patient = User(
            nome="Paciente Legado",
            cpf="52998224725",
            email="paciente.legado@ubs.local",
            senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente",
            ativo=True,
        )
        db.add_all([legacy, patient])
        db.flush()
        appointment = Appointment(
            paciente_id=patient.id,
            medico_id=legacy.id,
            especialidade="Clínica Geral",
            data_horario=clock.now_sao_paulo_naive(),
            status="agendado",
        )
        db.add(appointment)
        db.commit()
        legacy_id, appointment_id = legacy.id, appointment.id

    migrate_database()
    migrate_database()

    with SessionLocal() as db:
        migrated = db.get(User, legacy_id)
        appointment = db.get(Appointment, appointment_id)
        assert migrated.perfil == "medico"
        assert appointment.medico_id == legacy_id


def test_demo_doctor_seed_is_idempotent(client):
    from seed_demonstracao import ensure_demo_accounts

    ensure_demo_accounts()
    ensure_demo_accounts()

    with SessionLocal() as db:
        doctors = list(
            db.scalars(select(User).where(User.cpf == "39053344705"))
        )
        assert len(doctors) == 1
        assert doctors[0].nome == "Dr. Victor Almeida"
        assert doctors[0].perfil == "medico"
        assert doctors[0].ativo is True
