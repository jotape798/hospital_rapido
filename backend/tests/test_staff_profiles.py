from datetime import datetime, timedelta

from sqlalchemy import select

from test_integration import client
from app.core import clock
from app.core.database import SessionLocal
from app.core.security import pwd
from app.models import (
    Appointment,
    PriorityCondition,
    ProfessionalProfile,
    RiskClassification,
    Specialty,
    User,
)


def _setup_staff_data():
    with SessionLocal() as db:
        specialty = db.scalar(select(Specialty).where(Specialty.nome == "Clínica Geral"))
        reception = User(
            nome="Recepção Fictícia",
            cpf="98765432100",
            email="recepcao.teste@example.com",
            senha_hash=pwd.hash("Recepcao@123"),
            perfil="recepcao",
            ativo=True,
        )
        professional = User(
            nome="Profissional Fictício",
            cpf="11144477735",
            email="profissional.teste@example.com",
            senha_hash=pwd.hash("Profissional@123"),
            perfil="profissional",
            ativo=True,
        )
        nurse = User(
            nome="Enfermagem Fictícia",
            cpf="39053344705",
            email="enfermagem.teste@example.com",
            senha_hash=pwd.hash("Enfermagem@123"),
            perfil="enfermagem",
            ativo=True,
        )
        patient = User(
            nome="Paciente Fictício",
            cpf="52998224725",
            email="paciente.teste@example.com",
            senha_hash=pwd.hash("Paciente@123"),
            perfil="paciente",
            ativo=True,
            e_prioridade="geral",
        )
        db.add_all([reception, professional, nurse, patient])
        db.flush()
        db.add_all([
            ProfessionalProfile(
                usuario_id=professional.id,
                registro_profissional="TESTE-001",
                especialidade_id=specialty.id,
                autorizado_triagem=False,
                ativo=True,
            ),
            ProfessionalProfile(
                usuario_id=nurse.id,
                registro_profissional="COREN-TESTE-001",
                especialidade_id=specialty.id,
                autorizado_triagem=True,
                ativo=True,
            ),
        ])
        appointment = Appointment(
            paciente_id=patient.id,
            medico_id=professional.id,
            especialidade="Clínica Geral",
            data_horario=clock.now_sao_paulo_naive().replace(
                hour=10, minute=0, second=0, microsecond=0
            ),
            status="agendado",
        )
        db.add(appointment)
        db.commit()
        return appointment.id


def _login(client, cpf, password):
    response = client.post(
        "/auth/login", json={"document": cpf, "password": password}
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_reception_panel_permissions_and_status_rules(client):
    appointment_id = _setup_staff_data()
    reception = _login(client, "98765432100", "Recepcao@123")

    assert client.get("/recepcao/resumo", headers=reception).status_code == 200
    listing = client.get("/recepcao/agendamentos", headers=reception)
    assert listing.status_code == 200
    assert listing.json()[0]["patient_document"] == "***.***.***-25"
    assert (
        client.get(
            f"/recepcao/agendamentos/{appointment_id}", headers=reception
        ).status_code
        == 200
    )
    check_in = client.patch(
        f"/recepcao/agendamentos/{appointment_id}/check-in", headers=reception
    )
    assert check_in.status_code == 200
    assert check_in.json()["status"] == "em_espera"
    assert check_in.json()["arrived_at"] is not None
    assert (
        client.patch(
            f"/recepcao/agendamentos/{appointment_id}/check-in", headers=reception
        ).status_code
        == 409
    )
    assert client.get("/enfermagem/fila", headers=reception).status_code == 403
    assert client.get("/admin/users", headers=reception).status_code == 403


def test_nursing_manual_risk_and_complete_workflow(client):
    appointment_id = _setup_staff_data()
    reception = _login(client, "98765432100", "Recepcao@123")
    nurse = _login(client, "39053344705", "Enfermagem@123")
    professional = _login(client, "11144477735", "Profissional@123")

    assert (
        client.patch(
            f"/medico/atendimentos/{appointment_id}/iniciar",
            headers=professional,
        ).status_code
        == 409
    )
    assert (
        client.patch(
            f"/recepcao/agendamentos/{appointment_id}/check-in", headers=reception
        ).status_code
        == 200
    )
    invalid = client.patch(
        f"/enfermagem/agendamentos/{appointment_id}/classificacao-risco",
        headers=nurse,
        json={"level": "automatico", "observation": "Inválida"},
    )
    assert invalid.status_code == 422
    classified = client.patch(
        f"/enfermagem/agendamentos/{appointment_id}/classificacao-risco",
        headers=nurse,
        json={
            "level": "alto",
            "complaint": "Dor de cabeça fictícia.",
            "vital_signs": "PA 120/80; temperatura 36,5 °C.",
            "observation": "Observação fictícia curta.",
        },
    )
    assert classified.status_code == 200
    assert classified.json()["status"] == "em_triagem"
    assert classified.json()["risk_label"] == "Alto"
    assert client.patch(
        f"/enfermagem/agendamentos/{appointment_id}/classificacao-risco",
        headers=professional,
        json={
            "level": "baixo",
            "complaint": "Queixa fictícia.",
            "vital_signs": "PA fictícia 120/80.",
        },
    ).status_code == 403
    assert client.patch(
        f"/medico/atendimentos/{appointment_id}/iniciar",
        headers=nurse,
    ).status_code == 403
    assert client.get("/admin/users", headers=nurse).status_code == 403
    called = client.patch(
        f"/medico/atendimentos/{appointment_id}/chamar",
        headers=professional,
    )
    assert called.status_code == 200
    assert called.json()["called_at"] is not None
    started = client.patch(
        f"/medico/atendimentos/{appointment_id}/iniciar",
        headers=professional,
    )
    assert started.status_code == 200
    assert started.json()["started_at"] is not None
    completed = client.patch(
        f"/medico/atendimentos/{appointment_id}/concluir",
        headers=professional,
        json={"summary": "Atendimento fictício concluído."},
    )
    assert completed.status_code == 200
    assert completed.json()["completed_at"] is not None
    assert (
        client.patch(
            f"/medico/atendimentos/{appointment_id}/concluir",
            headers=professional,
            json={"summary": "Tentativa fictícia repetida."},
        ).status_code
        == 409
    )
    assert client.get("/admin/users", headers=professional).status_code == 403
    with SessionLocal() as db:
        appointment = db.get(Appointment, appointment_id)
        risk = db.scalar(
            select(RiskClassification).where(
                RiskClassification.consulta_id == appointment_id
            )
        )
        assert appointment.status == "concluido"
        assert appointment.iniciado_em and appointment.concluido_em
        assert risk.nivel_risco == "alto"
        assert risk.queixa_principal == "Dor de cabeça fictícia."
        assert risk.sinais_vitais == "PA 120/80; temperatura 36,5 °C."


def test_only_official_risk_levels_are_accepted_and_reach_medical_queue(client):
    appointment_id = _setup_staff_data()
    reception = _login(client, "98765432100", "Recepcao@123")
    nurse = _login(client, "39053344705", "Enfermagem@123")
    professional = _login(client, "11144477735", "Profissional@123")
    assert client.patch(
        f"/recepcao/agendamentos/{appointment_id}/check-in", headers=reception
    ).status_code == 200

    path = f"/enfermagem/agendamentos/{appointment_id}/classificacao-risco"
    for level in ("muito_alto", "alto", "moderado", "baixo"):
        response = client.patch(
            path,
            headers=nurse,
            json={
                "level": level,
                "complaint": "Queixa fictícia para validação.",
                "vital_signs": "Sinais vitais fictícios estáveis.",
            },
        )
        assert response.status_code == 200
        assert response.json()["risk_classification"] == level
        medical = client.get("/medico/fila", headers=professional)
        assert medical.status_code == 200
        assert medical.json()[0]["risk_classification"] == level

    for invalid in ("vermelho", "laranja", "amarelo", "verde", "qualquer"):
        assert client.patch(
            path,
            headers=nurse,
            json={
                "level": invalid,
                "complaint": "Queixa fictícia para validação.",
                "vital_signs": "Sinais vitais fictícios estáveis.",
            },
        ).status_code == 422


def test_queue_orders_risk_legal_priority_and_arrival(client):
    _setup_staff_data()
    now = clock.now_sao_paulo_naive()
    with SessionLocal() as db:
        professional = db.scalar(select(User).where(User.perfil == "profissional"))
        cases = [
            ("Risco Máximo", "geral", None, "muito_alto", 1),
            ("Pessoa Idosa", "geral", datetime(1950, 1, 1), "alto", 2),
            ("Pessoa PCD", "pcd", None, "alto", 3),
            ("Pessoa Gestante", "gestante", None, "alto", 4),
            ("Pessoa Lactante", "lactante", None, "alto", 5),
            ("Prioridade Geral", "geral", None, "alto", 10),
            ("Risco Moderado", "geral", None, "moderado", 1),
            ("Risco Baixo", "geral", None, "baixo", 1),
        ]
        hours = [7, 8, 9, 11, 13, 14, 15, 16]
        for index, (name, priority, birth, risk_level, minutes) in enumerate(cases):
            patient = User(
                nome=name,
                cpf=f"80000000{index:03d}",
                email=f"fila{index}@example.com",
                senha_hash=pwd.hash("Paciente@123"),
                perfil="paciente",
                ativo=True,
                e_prioridade=priority,
                data_nascimento=birth,
            )
            db.add(patient)
            db.flush()
            if priority in {"pcd", "gestante", "lactante"}:
                db.add(PriorityCondition(
                    paciente_id=patient.id,
                    condicao=priority,
                    status="confirmada",
                    validada_por=professional.id,
                    validada_em=now,
                ))
            appointment = Appointment(
                paciente_id=patient.id,
                medico_id=professional.id,
                especialidade="Clínica Geral",
                data_horario=now.replace(
                    hour=hours[index], minute=0, second=0, microsecond=0
                ),
                status="em_triagem",
                classificacao_risco=risk_level,
                chegada_em=now - timedelta(minutes=minutes),
                triagem_em=now,
            )
            db.add(appointment)
            db.flush()
            db.add(
                RiskClassification(
                    consulta_id=appointment.id,
                    profissional_id=professional.id,
                    nivel_risco=risk_level,
                    queixa_principal="Queixa fictícia.",
                    sinais_vitais="Sinais vitais fictícios.",
                )
            )
        db.commit()

    professional_headers = _login(client, "11144477735", "Profissional@123")
    response = client.get("/medico/fila", headers=professional_headers)
    assert response.status_code == 200
    rows = response.json()
    assert [row["patient"] for row in rows] == [case[0] for case in cases]
    assert rows[1]["priority_reason"].startswith("Pessoa idosa —")
    assert rows[2]["priority_reason"] == "Pessoa com deficiência (PCD) — confirmado presencialmente"


def test_health_professional_cannot_use_nursing_routes(client):
    _setup_staff_data()
    with SessionLocal() as db:
        user = User(
            nome="Profissional Não Autorizado",
            cpf="70000000744",
            email="nao.autorizado@example.com",
            senha_hash=pwd.hash("Profissional@123"),
            perfil="profissional",
            ativo=True,
        )
        specialty = db.scalar(select(Specialty))
        db.add(user)
        db.flush()
        db.add(
            ProfessionalProfile(
                usuario_id=user.id,
                registro_profissional="TESTE-002",
                especialidade_id=specialty.id,
                autorizado_triagem=False,
                ativo=True,
            )
        )
        db.commit()
    unauthorized = _login(client, "70000000744", "Profissional@123")
    assert client.get("/enfermagem/resumo", headers=unauthorized).status_code == 403
