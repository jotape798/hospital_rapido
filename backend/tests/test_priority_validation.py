"""Regressões da prioridade legal calculada e da validação presencial."""
from datetime import date, datetime, timedelta

from sqlalchemy import func, select

# Este import configura DATABASE_URL temporária antes de qualquer módulo app.*.
from test_integration import client, data, register

from app.core.database import SessionLocal
from app.core.security import make_token, pwd
from app.main import migrate_database
from app.models import AuditLog, Appointment, PriorityCondition, PriorityConditionHistory, User
from app.services.appointments import full_age, legal_priority_code, queue_sort_key
from seed_demonstracao import ensure_demo_accounts, ensure_demo_workflow


def _headers(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {make_token(user)}"}


def _data(**overrides) -> dict:
    payload = data()
    payload.update(overrides)
    return payload


def _birth_for_age(age: int, *, birthday_delta_days: int = 0) -> date:
    today = date.today()
    birthday = today + timedelta(days=birthday_delta_days)
    return birthday.replace(year=birthday.year - age)


def test_full_age_handles_59_exactly_60_future_birthday_and_over_60():
    today = date.today()
    assert full_age(_birth_for_age(59), today) == 59
    assert full_age(_birth_for_age(60), today) == 60
    assert full_age(_birth_for_age(60, birthday_delta_days=1), today) == 59
    assert full_age(_birth_for_age(67), today) == 67


def test_registration_ignores_client_as_authority_and_derives_elderly(client):
    young = _data(birth_date=_birth_for_age(41).isoformat(), priority="idoso_60+")
    response = client.post("/auth/register", json=young)
    assert response.status_code == 422
    assert "calculada automaticamente" in response.json()["detail"]

    old = _data(
        cpf="16899535009",
        email="idosa@example.com",
        birth_date=_birth_for_age(67).isoformat(),
        priority="geral",
    )
    assert client.post("/auth/register", json=old).status_code == 201
    with SessionLocal() as db:
        patient = db.scalar(select(User).where(User.cpf == "16899535009"))
        assert legal_priority_code(patient) == "idoso_60+"


def test_tampered_update_cannot_grant_elderly_priority(client):
    assert register(client).status_code == 201
    login = client.post("/auth/login", json={
        "document": "52998224725", "password": "Paciente@123"
    }).json()
    headers = {"Authorization": f"Bearer {login['access_token']}"}
    response = client.patch(
        "/patients/me/priority-conditions",
        headers=headers,
        json={"priority": "idoso_60+", "priority_conditions": []},
    )
    assert response.status_code == 422
    assert client.get("/patients/me", headers=headers).json()["legal_priority"] == "geral"


def test_condition_starts_pending_and_patient_cannot_confirm(client):
    payload = _data(priority_conditions=["pcd", "gestante"])
    assert client.post("/auth/register", json=payload).status_code == 201
    with SessionLocal() as db:
        patient = db.scalar(select(User).where(User.cpf == "52998224725"))
        states = {item.condicao: item.status for item in patient.condicoes_prioritarias}
        assert states == {"pcd": "pendente", "gestante": "pendente"}
        patient_headers = _headers(patient)
        appointment = Appointment(
            paciente_id=patient.id, medico_id=patient.id,
            especialidade="Clínica Geral", data_horario=datetime.now(),
            status="em_espera", chegada_em=datetime.now(),
        )
        db.add(appointment)
        db.commit()
        appointment_id = appointment.id
    response = client.patch(
        f"/recepcao/agendamentos/{appointment_id}/condicoes/pcd/validacao",
        headers=patient_headers,
        json={"status": "confirmada"},
    )
    assert response.status_code == 403


def test_patient_can_withdraw_pending_condition_without_erasing_history(client):
    assert register(
        client, priority_conditions=["pcd", "gestante", "lactante"]
    ).status_code == 201
    token = client.post("/auth/login", json={
        "document": "52998224725", "password": "Paciente@123",
    }).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    response = client.patch(
        "/patients/me/priority-conditions",
        headers=headers,
        json={"priority_conditions": ["gestante", "lactante"]},
    )
    assert response.status_code == 200
    assert {item["condition"] for item in response.json()["priority_conditions"]} == {
        "gestante", "lactante",
    }
    with SessionLocal() as db:
        pcd = db.scalar(select(PriorityCondition).where(
            PriorityCondition.condicao == "pcd"
        ))
        assert pcd.status == "retirada"
        history = list(db.scalars(select(PriorityConditionHistory).where(
            PriorityConditionHistory.condicao_prioritaria_id == pcd.id
        ).order_by(PriorityConditionHistory.id)))
        assert [event.status_novo for event in history] == ["pendente", "retirada"]


def test_repeated_priority_confirmation_is_idempotent_and_audited_with_role(client):
    now = datetime.now()
    with SessionLocal() as db:
        reception = User(
            nome="Recepção Idempotente", cpf="98765432100",
            email="recepcao.idempotente@example.test",
            senha_hash=pwd.hash("Recepcao@123"), perfil="recepcao", ativo=True,
        )
        patient = User(
            nome="Paciente Idempotente", cpf="52998224725",
            email="paciente.idempotente@example.test",
            senha_hash=pwd.hash("Paciente@123"), perfil="paciente", ativo=True,
            data_nascimento=datetime(1990, 1, 1),
        )
        db.add_all([reception, patient])
        db.flush()
        condition = PriorityCondition(
            paciente_id=patient.id, condicao="pcd", status="pendente"
        )
        appointment = Appointment(
            paciente_id=patient.id, medico_id=reception.id,
            especialidade="Clínica Geral", data_horario=now,
            status="agendado",
        )
        db.add_all([condition, appointment])
        db.flush()
        db.add(PriorityConditionHistory(
            condicao_prioritaria_id=condition.id, status_anterior=None,
            status_novo="pendente", alterado_por=patient.id,
        ))
        db.commit()
        appointment_id = appointment.id
        condition_id = condition.id
        headers = _headers(reception)

    path = f"/recepcao/agendamentos/{appointment_id}/condicoes/pcd/validacao"
    assert client.patch(path, headers=headers, json={"status": "confirmada"}).status_code == 200
    assert client.patch(path, headers=headers, json={"status": "confirmada"}).status_code == 200

    with SessionLocal() as db:
        history_count = db.scalar(select(func.count(PriorityConditionHistory.id)).where(
            PriorityConditionHistory.condicao_prioritaria_id == condition_id
        ))
        audits = list(db.scalars(select(AuditLog).where(
            AuditLog.tipo_registro == "condicao_prioritaria",
            AuditLog.registro_id == condition_id,
            AuditLog.acao == "validar_condicao_prioritaria",
        )))
        assert history_count == 2
        assert len(audits) == 1
        assert '"perfil_responsavel": "recepcao"' in audits[0].detalhes


def test_reception_confirms_and_rejects_with_audit_and_queue_effect(client):
    now = datetime.now()
    with SessionLocal() as db:
        reception = User(
            nome="Recepção Teste", cpf="98765432100", email="r@example.com",
            senha_hash=pwd.hash("Recepcao@123"), perfil="recepcao", ativo=True,
        )
        first = User(
            nome="Paciente Geral", cpf="52998224725", email="g@example.com",
            senha_hash=pwd.hash("Paciente@123"), perfil="paciente", ativo=True,
            data_nascimento=datetime(1990, 1, 1), e_prioridade="geral",
        )
        pending = User(
            nome="Paciente PCD", cpf="16899535009", email="p@example.com",
            senha_hash=pwd.hash("Paciente@123"), perfil="paciente", ativo=True,
            data_nascimento=datetime(1990, 1, 1), e_prioridade="geral",
        )
        db.add_all([reception, first, pending])
        db.flush()
        condition = PriorityCondition(
            paciente_id=pending.id, condicao="pcd", status="pendente"
        )
        db.add(condition)
        db.flush()
        db.add(PriorityConditionHistory(
            condicao_prioritaria_id=condition.id, status_anterior=None,
            status_novo="pendente", alterado_por=pending.id,
        ))
        older = Appointment(
            paciente_id=first.id, medico_id=reception.id,
            especialidade="Clínica Geral", data_horario=now + timedelta(minutes=1),
            status="em_espera", classificacao_risco="alto",
            chegada_em=now - timedelta(minutes=10),
        )
        newer = Appointment(
            paciente_id=pending.id, medico_id=reception.id,
            especialidade="Clínica Geral", data_horario=now,
            status="em_espera", classificacao_risco="alto",
            chegada_em=now - timedelta(minutes=2),
        )
        db.add_all([older, newer])
        db.commit()
        reception_headers = _headers(reception)
        newer_id = newer.id
        assert sorted([newer, older], key=queue_sort_key)[0].paciente_id == first.id

    confirmed = client.patch(
        f"/recepcao/agendamentos/{newer_id}/condicoes/pcd/validacao",
        headers=reception_headers, json={"status": "confirmada"},
    )
    assert confirmed.status_code == 200
    item = confirmed.json()["priority_conditions"][0]
    assert item["status"] == "confirmada"
    assert item["validated_by"] == "Recepção Teste"
    assert item["validated_at"]
    queue = client.get("/queue", headers=reception_headers).json()
    assert queue[0]["id"] == newer_id

    rejected = client.patch(
        f"/recepcao/agendamentos/{newer_id}/condicoes/pcd/validacao",
        headers=reception_headers, json={"status": "rejeitada"},
    )
    assert rejected.status_code == 200
    queue = client.get("/queue", headers=reception_headers).json()
    assert queue[0]["patient"].startswith("Paciente G")
    with SessionLocal() as db:
        condition = db.scalar(select(PriorityCondition))
        history = list(db.scalars(select(PriorityConditionHistory).where(
            PriorityConditionHistory.condicao_prioritaria_id == condition.id
        )))
        assert [event.status_novo for event in history] == [
            "pendente", "confirmada", "rejeitada"
        ]


def test_migration_repairs_false_elderly_and_keeps_true_elderly(client):
    with SessionLocal() as db:
        young = User(
            nome="Fictício 41 Anos", cpf="70000000159", email="41@example.com",
            senha_hash="hash", perfil="paciente", data_nascimento=datetime(1985, 1, 1),
            e_prioridade="idoso_60+",
        )
        old = User(
            nome="Fictício Idoso", cpf="70000000230", email="67@example.com",
            senha_hash="hash", perfil="paciente", data_nascimento=datetime(1950, 1, 1),
            e_prioridade="geral",
        )
        legacy_pcd = User(
            nome="Fictício PCD", cpf="70000000310", email="pcd@example.com",
            senha_hash="hash", perfil="paciente", data_nascimento=datetime(1990, 1, 1),
            e_prioridade="pcd",
        )
        db.add_all([young, old, legacy_pcd])
        db.commit()
    migrate_database()
    migrate_database()  # idempotência
    with SessionLocal() as db:
        young = db.scalar(select(User).where(User.cpf == "70000000159"))
        old = db.scalar(select(User).where(User.cpf == "70000000230"))
        legacy_pcd = db.scalar(select(User).where(User.cpf == "70000000310"))
        assert young.e_prioridade == "geral"
        assert old.e_prioridade == "idoso_60+"
        assert [(x.condicao, x.status) for x in legacy_pcd.condicoes_prioritarias] == [
            ("pcd", "pendente")
        ]


def test_demo_seed_is_idempotent_and_has_real_elderly_and_validation_examples(client):
    ensure_demo_accounts()
    ensure_demo_workflow()
    with SessionLocal() as db:
        first_counts = (
            db.scalar(select(func.count(User.id))),
            db.scalar(select(func.count(Appointment.id))),
            db.scalar(select(func.count(PriorityCondition.id))),
        )
    ensure_demo_accounts()
    ensure_demo_workflow()
    with SessionLocal() as db:
        second_counts = (
            db.scalar(select(func.count(User.id))),
            db.scalar(select(func.count(Appointment.id))),
            db.scalar(select(func.count(PriorityCondition.id))),
        )
        elderly = db.scalar(select(User).where(User.cpf == "70000000159"))
        states = set(db.execute(select(
            PriorityCondition.condicao, PriorityCondition.status
        )).all())
        false_elderly = db.scalar(select(User).where(User.cpf == "70000000582"))
        assert legal_priority_code(elderly) == "idoso_60+"
        assert legal_priority_code(false_elderly) != "idoso_60+"
        assert {("pcd", "pendente"), ("gestante", "confirmada")} <= states
    assert second_counts == first_counts
