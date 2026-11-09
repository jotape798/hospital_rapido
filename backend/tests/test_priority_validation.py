"""Regressões da prioridade legal calculada e da validação presencial."""
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta
from threading import Barrier

import pytest
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


def _validation_case(
    *,
    appointment_status: str = "em_espera",
    condition_status: str = "pendente",
    checked_in: bool = True,
) -> tuple[int, int, dict[str, str]]:
    now = datetime.now()
    with SessionLocal() as db:
        reception = User(
            nome="Recepção Validação", cpf="98765432100",
            email="recepcao.validacao@example.test",
            senha_hash=pwd.hash("Recepcao@123"), perfil="recepcao", ativo=True,
        )
        patient = User(
            nome="Paciente Validação", cpf="52998224725",
            email="paciente.validacao@example.test",
            senha_hash=pwd.hash("Paciente@123"), perfil="paciente", ativo=True,
            data_nascimento=datetime(1990, 1, 1), e_prioridade="geral",
        )
        db.add_all([reception, patient])
        db.flush()
        condition = PriorityCondition(
            paciente_id=patient.id, condicao="pcd", status=condition_status,
        )
        appointment = Appointment(
            paciente_id=patient.id, medico_id=reception.id,
            especialidade="Clínica Geral", data_horario=now,
            status=appointment_status,
            chegada_em=now - timedelta(minutes=5) if checked_in else None,
            chegada_por=reception.id if checked_in else None,
            falta_em=now if appointment_status == "falta" else None,
        )
        db.add_all([condition, appointment])
        db.flush()
        db.add(PriorityConditionHistory(
            condicao_prioritaria_id=condition.id, status_anterior=None,
            status_novo=condition_status, alterado_por=patient.id,
        ))
        appointment_id = appointment.id
        condition_id = condition.id
        headers = _headers(reception)
        db.commit()
    return appointment_id, condition_id, headers


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


def test_confirmed_priority_cannot_be_changed_and_is_audited_with_role(client):
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
            status="em_espera", chegada_em=now - timedelta(minutes=5),
            chegada_por=reception.id,
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
        reception_id = reception.id
        headers = _headers(reception)

    path = f"/recepcao/agendamentos/{appointment_id}/condicoes/pcd/validacao"
    assert client.patch(path, headers=headers, json={"status": "confirmada"}).status_code == 200
    repeated = client.patch(path, headers=headers, json={"status": "rejeitada"})
    assert repeated.status_code == 409
    assert "pendente" in repeated.json()["detail"]

    with SessionLocal() as db:
        condition = db.get(PriorityCondition, condition_id)
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
        assert condition.status == "confirmada"
        assert condition.validada_por == reception_id
        assert condition.validada_em is not None
        validation = db.scalar(select(PriorityConditionHistory).where(
            PriorityConditionHistory.condicao_prioritaria_id == condition_id,
            PriorityConditionHistory.status_novo == "confirmada",
        ))
        assert validation.alterado_por == reception_id
        assert validation.criado_em is not None
        assert audits[0].usuario_id == reception_id
        assert audits[0].criado_em is not None
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

    with SessionLocal() as db:
        condition = db.scalar(select(PriorityCondition))
        history = list(db.scalars(select(PriorityConditionHistory).where(
            PriorityConditionHistory.condicao_prioritaria_id == condition.id
        )))
        assert [event.status_novo for event in history] == [
            "pendente", "confirmada"
        ]


def test_reception_rejects_pending_condition_without_invalidating_appointment(client):
    appointment_id, condition_id, headers = _validation_case()
    path = f"/recepcao/agendamentos/{appointment_id}/condicoes/pcd/validacao"

    rejected = client.patch(path, headers=headers, json={"status": "rejeitada"})
    assert rejected.status_code == 200
    assert rejected.json()["status"] == "em_espera"
    assert rejected.json()["legal_priority"] == "geral"

    changed_again = client.patch(
        path, headers=headers, json={"status": "confirmada"},
    )
    assert changed_again.status_code == 409
    assert "pendente" in changed_again.json()["detail"]
    with SessionLocal() as db:
        condition = db.get(PriorityCondition, condition_id)
        appointment = db.get(Appointment, appointment_id)
        assert condition.status == "rejeitada"
        assert legal_priority_code(appointment.paciente) == "geral"
        assert appointment.status == "em_espera"


def test_priority_validation_before_checkin_is_blocked(client):
    appointment_id, condition_id, headers = _validation_case(
        appointment_status="agendado", checked_in=False,
    )
    response = client.patch(
        f"/recepcao/agendamentos/{appointment_id}/condicoes/pcd/validacao",
        headers=headers,
        json={"status": "confirmada"},
    )
    assert response.status_code == 409
    assert "após o check-in" in response.json()["detail"]
    with SessionLocal() as db:
        assert db.get(PriorityCondition, condition_id).status == "pendente"


@pytest.mark.parametrize(
    ("status", "message"),
    [
        ("cancelado", "cancelada"),
        ("concluido", "concluída"),
        ("falta", "ausência"),
        ("em_triagem", "aguarda triagem"),
        ("em_atendimento", "aguarda triagem"),
    ],
)
def test_priority_validation_in_incompatible_appointment_is_blocked(
    client, status, message,
):
    appointment_id, condition_id, headers = _validation_case(
        appointment_status=status,
    )
    response = client.patch(
        f"/recepcao/agendamentos/{appointment_id}/condicoes/pcd/validacao",
        headers=headers,
        json={"status": "confirmada"},
    )
    assert response.status_code == 409
    assert message in response.json()["detail"]
    with SessionLocal() as db:
        assert db.get(PriorityCondition, condition_id).status == "pendente"


def test_only_reception_can_validate_priority_condition(client):
    appointment_id, condition_id, reception_headers = _validation_case()
    path = f"/recepcao/agendamentos/{appointment_id}/condicoes/pcd/validacao"
    with SessionLocal() as db:
        users = []
        for index, role in enumerate(
            ["paciente", "enfermagem", "medico", "administrador"], start=1,
        ):
            user = User(
                nome=f"Perfil {role}", cpf=f"70000000{index:03d}",
                email=f"{role}@example.test", senha_hash="hash",
                perfil=role, ativo=True,
            )
            db.add(user)
            users.append(user)
        db.flush()
        other_headers = [_headers(user) for user in users]
        db.commit()

    for headers in other_headers:
        response = client.patch(
            path, headers=headers, json={"status": "confirmada"},
        )
        assert response.status_code == 403
    with SessionLocal() as db:
        assert db.get(PriorityCondition, condition_id).status == "pendente"

    allowed = client.patch(
        path, headers=reception_headers, json={"status": "confirmada"},
    )
    assert allowed.status_code == 200


def test_concurrent_priority_validations_have_one_consistent_winner(client):
    appointment_id, condition_id, headers = _validation_case()
    path = f"/recepcao/agendamentos/{appointment_id}/condicoes/pcd/validacao"
    ready = Barrier(2)

    def validate(status: str):
        ready.wait(timeout=5)
        return client.patch(path, headers=headers, json={"status": status})

    with ThreadPoolExecutor(max_workers=2) as pool:
        confirmed = pool.submit(validate, "confirmada")
        rejected = pool.submit(validate, "rejeitada")
        responses = [confirmed.result(timeout=10), rejected.result(timeout=10)]

    assert sorted(response.status_code for response in responses) == [200, 409]
    winner = next(response for response in responses if response.status_code == 200)
    with SessionLocal() as db:
        condition = db.get(PriorityCondition, condition_id)
        histories = list(db.scalars(select(PriorityConditionHistory).where(
            PriorityConditionHistory.condicao_prioritaria_id == condition_id,
        )))
        audits = list(db.scalars(select(AuditLog).where(
            AuditLog.acao == "validar_condicao_prioritaria",
            AuditLog.registro_id == condition_id,
        )))
        assert condition.status in {"confirmada", "rejeitada"}
        assert winner.json()["legal_priority"] == (
            "pcd" if condition.status == "confirmada" else "geral"
        )
        assert [event.status_novo for event in histories].count(condition.status) == 1
        assert len(audits) == 1
        assert f'"consulta_id": {appointment_id}' in audits[0].detalhes
        assert f'"resultado": "{condition.status}"' in audits[0].detalhes


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
