"""Bloqueio da triagem fora da ordem priorizada."""

from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

from sqlalchemy import func, select

from test_integration import client
from app.core import clock
from app.core.database import SessionLocal
from app.core.security import make_token, pwd
from app.models import (
    Appointment,
    AppointmentStatusHistory,
    AuditLog,
    PriorityCondition,
    ProfessionalProfile,
    RiskClassification,
    Specialty,
    User,
)


TRIAGE_PAYLOAD = {
    "level": "moderado",
    "complaint": "Queixa fictícia para teste de ordenação.",
    "vital_signs": "Sinais vitais fictícios estáveis.",
}


def _setup_prioritized_queue():
    now = clock.now_sao_paulo_naive().replace(second=0, microsecond=0)
    today = clock.today_sao_paulo()
    with SessionLocal() as db:
        specialty = db.scalar(
            select(Specialty).where(Specialty.nome == "Clínica Geral")
        )
        nurse = User(
            nome="Enfermagem da Fila",
            cpf="70000000159",
            email="enfermagem.fila@example.com",
            senha_hash=pwd.hash("Enfermagem@123"),
            perfil="enfermagem",
            ativo=True,
        )
        doctor = User(
            nome="Médico da Fila",
            cpf="70000000230",
            email="medico.fila@example.com",
            senha_hash=pwd.hash("Medico@123"),
            perfil="medico",
            ativo=True,
        )
        patients = {
            "elderly": User(
                nome="Paciente Idoso",
                cpf="70000000310",
                email="idoso.fila@example.com",
                senha_hash=pwd.hash("Paciente@123"),
                perfil="paciente",
                ativo=True,
                data_nascimento=datetime(today.year - 70, 1, 1),
            ),
            "confirmed": User(
                nome="Paciente PCD Confirmado",
                cpf="70000000409",
                email="pcd.confirmado@example.com",
                senha_hash=pwd.hash("Paciente@123"),
                perfil="paciente",
                ativo=True,
                data_nascimento=datetime(1990, 1, 1),
            ),
            "general": User(
                nome="Paciente Geral",
                cpf="70000000582",
                email="geral.fila@example.com",
                senha_hash=pwd.hash("Paciente@123"),
                perfil="paciente",
                ativo=True,
                data_nascimento=datetime(1990, 1, 1),
            ),
            "pending": User(
                nome="Paciente PCD Pendente",
                cpf="70000000663",
                email="pcd.pendente@example.com",
                senha_hash=pwd.hash("Paciente@123"),
                perfil="paciente",
                ativo=True,
                data_nascimento=datetime(1990, 1, 1),
            ),
            "rejected": User(
                nome="Paciente PCD Rejeitado",
                cpf="70000000744",
                email="pcd.rejeitado@example.com",
                senha_hash=pwd.hash("Paciente@123"),
                perfil="paciente",
                ativo=True,
                data_nascimento=datetime(1990, 1, 1),
            ),
        }
        db.add_all([nurse, doctor, *patients.values()])
        db.flush()
        db.add(
            ProfessionalProfile(
                usuario_id=nurse.id,
                registro_profissional="COREN-FILA-001",
                especialidade_id=specialty.id,
                autorizado_triagem=True,
                ativo=True,
            )
        )
        db.add_all(
            [
                PriorityCondition(
                    paciente_id=patients["confirmed"].id,
                    condicao="pcd",
                    status="confirmada",
                ),
                PriorityCondition(
                    paciente_id=patients["pending"].id,
                    condicao="pcd",
                    status="pendente",
                ),
                PriorityCondition(
                    paciente_id=patients["rejected"].id,
                    condicao="pcd",
                    status="rejeitada",
                ),
            ]
        )
        arrivals = {
            "elderly": now - timedelta(minutes=1),
            "confirmed": now,
            "general": now - timedelta(minutes=20),
            "pending": now - timedelta(minutes=15),
            "rejected": now - timedelta(minutes=10),
        }
        appointments = {}
        for index, (name, patient) in enumerate(patients.items()):
            appointment = Appointment(
                paciente_id=patient.id,
                medico_id=doctor.id,
                especialidade="Clínica Geral",
                data_horario=now.replace(hour=8, minute=index),
                status="em_espera",
                chegada_em=arrivals[name],
            )
            db.add(appointment)
            db.flush()
            appointments[name] = appointment.id
        without_check_in = Appointment(
            paciente_id=patients["general"].id,
            medico_id=doctor.id,
            especialidade="Clínica Geral",
            data_horario=now.replace(hour=8, minute=10),
            status="agendado",
        )
        db.add(without_check_in)
        db.commit()
        return {
            "headers": {"Authorization": f"Bearer {make_token(nurse)}"},
            "doctor_headers": {"Authorization": f"Bearer {make_token(doctor)}"},
            "appointments": appointments,
            "without_check_in": without_check_in.id,
        }


def test_nursing_queue_respects_age_confirmed_priority_and_arrival(client):
    setup = _setup_prioritized_queue()

    response = client.get("/enfermagem/fila", headers=setup["headers"])

    assert response.status_code == 200
    rows = response.json()
    assert [row["id"] for row in rows] == [
        setup["appointments"]["elderly"],
        setup["appointments"]["confirmed"],
        setup["appointments"]["general"],
        setup["appointments"]["pending"],
        setup["appointments"]["rejected"],
    ]
    assert rows[0]["legal_priority"] == "idoso_60+"
    assert rows[1]["legal_priority"] == "pcd"
    assert rows[3]["legal_priority"] == "geral"
    assert rows[4]["legal_priority"] == "geral"
    assert rows[0]["triage_action_allowed"] is True
    assert all(row["triage_action_allowed"] is False for row in rows[1:])
    assert all(
        row["triage_block_reason"] == "Outro paciente está à frente na fila."
        for row in rows[1:]
    )


def test_next_patient_is_released_after_initial_triage_without_medical_action(client):
    setup = _setup_prioritized_queue()
    first_id = setup["appointments"]["elderly"]
    second_id = setup["appointments"]["confirmed"]

    blocked = client.patch(
        f"/enfermagem/agendamentos/{second_id}/classificacao-risco",
        headers=setup["headers"],
        json=TRIAGE_PAYLOAD,
    )
    assert blocked.status_code == 409
    assert blocked.json()["detail"] == "Outro paciente está à frente na fila de triagem"

    allowed = client.patch(
        f"/enfermagem/agendamentos/{first_id}/classificacao-risco",
        headers=setup["headers"],
        json=TRIAGE_PAYLOAD,
    )
    assert allowed.status_code == 200
    assert allowed.json()["status"] == "em_triagem"

    medical_queue = client.get(
        "/medico/fila", headers=setup["doctor_headers"]
    )
    assert medical_queue.status_code == 200
    assert first_id in [row["id"] for row in medical_queue.json()]

    released = client.patch(
        f"/enfermagem/agendamentos/{second_id}/classificacao-risco",
        headers=setup["headers"],
        json=TRIAGE_PAYLOAD,
    )
    assert released.status_code == 200
    assert released.json()["status"] == "em_triagem"

    queue = client.get("/enfermagem/fila", headers=setup["headers"]).json()
    assert queue[0]["id"] == first_id
    assert queue[0]["triage_action_allowed"] is True
    assert queue[1]["triage_action_allowed"] is True
    assert queue[1]["triage_block_reason"] is None

    reclassified = client.patch(
        f"/enfermagem/agendamentos/{first_id}/classificacao-risco",
        headers=setup["headers"],
        json={**TRIAGE_PAYLOAD, "level": "baixo"},
    )
    assert reclassified.status_code == 200
    assert reclassified.json()["risk_classification"] == "baixo"

    with SessionLocal() as db:
        assert db.scalar(select(func.count(RiskClassification.id))) == 2
        assert db.scalar(
            select(func.count(AppointmentStatusHistory.id)).where(
                AppointmentStatusHistory.status_novo == "em_triagem"
            )
        ) == 2
        assert db.scalar(
            select(func.count(AuditLog.id)).where(
                AuditLog.acao == "triagem_registrada"
            )
        ) == 3


def test_queue_filters_do_not_promote_a_patient_out_of_order(client):
    setup = _setup_prioritized_queue()
    rows = client.get(
        "/enfermagem/fila",
        headers=setup["headers"],
        params={"status": "em_espera"},
    ).json()

    assert rows[0]["id"] == setup["appointments"]["elderly"]
    assert rows[0]["triage_action_allowed"] is True
    assert all(row["triage_action_allowed"] is False for row in rows[1:])


def test_concurrent_initial_triage_attempts_preserve_the_first_patient(
    client, monkeypatch
):
    from app.routes import staff

    setup = _setup_prioritized_queue()
    first_id = setup["appointments"]["elderly"]
    second_id = setup["appointments"]["confirmed"]
    original = staff._initial_triage_rows
    simultaneous_reads = Barrier(2)

    def synchronized_initial_rows(rows):
        result = original(rows)
        simultaneous_reads.wait(timeout=5)
        return result

    monkeypatch.setattr(staff, "_initial_triage_rows", synchronized_initial_rows)

    def classify(appointment_id):
        return client.patch(
            f"/enfermagem/agendamentos/{appointment_id}/classificacao-risco",
            headers=setup["headers"],
            json=TRIAGE_PAYLOAD,
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        first_future = pool.submit(classify, first_id)
        second_future = pool.submit(classify, second_id)
        first = first_future.result(timeout=10)
        second = second_future.result(timeout=10)

    assert first.status_code == 200
    assert second.status_code == 409
    assert second.json()["detail"] == "Outro paciente está à frente na fila de triagem"

    monkeypatch.setattr(staff, "_initial_triage_rows", original)
    released = classify(second_id)
    assert released.status_code == 200


def test_triage_without_check_in_remains_blocked(client):
    setup = _setup_prioritized_queue()

    response = client.patch(
        f"/enfermagem/agendamentos/{setup['without_check_in']}/classificacao-risco",
        headers=setup["headers"],
        json=TRIAGE_PAYLOAD,
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "Não é possível classificar risco sem check-in"
