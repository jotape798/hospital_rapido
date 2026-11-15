from datetime import datetime, timedelta

from sqlalchemy import func, select

from test_integration import client, register, login
from app.core import clock
from app.core.database import SessionLocal
from app.core.security import pwd
from app.models import (
    Appointment,
    PasswordRecovery,
    ProfessionalProfile,
    ProfessionalSchedule,
    Specialty,
    User,
)


def _email_recovery(client, monkeypatch):
    import app.routes.recovery as recovery_routes

    sent = []
    monkeypatch.setattr(
        recovery_routes,
        "send_recovery",
        lambda email, code: sent.append((email, code)) if email else None,
    )
    assert register(client).status_code == 201
    response = client.post(
        "/auth/esqueci-senha", json={"email": "MARIA@example.com"}
    )
    assert response.status_code == 200
    assert response.json()["message"] == (
        "Se o e-mail estiver cadastrado, enviaremos um código de verificação."
    )
    assert sent and sent[0][0] == "maria@example.com"
    with SessionLocal() as db:
        recovery = db.scalar(select(PasswordRecovery))
        assert recovery.codigo_hash != sent[0][1]
        assert len(recovery.codigo_hash) == 64
        assert recovery.expira_em <= clock.now_utc_naive() + timedelta(minutes=10)
    return sent[0][1]


def test_email_recovery_correct_single_use_and_new_login(client, monkeypatch):
    code = _email_recovery(client, monkeypatch)
    verified = client.post(
        "/auth/validar-codigo-recuperacao",
        json={"email": "maria@example.com", "code": code},
    )
    assert verified.status_code == 200
    body = {
        "recovery_token": verified.json()["recovery_token"],
        "new_password": "NovaSenha@123",
        "confirm_new_password": "NovaSenha@123",
    }
    changed = client.post("/auth/redefinir-senha", json=body)
    assert changed.status_code == 200
    assert changed.json()["message"] == (
        "Senha alterada com sucesso. Faça login com sua nova senha."
    )
    assert client.post("/auth/redefinir-senha", json=body).status_code == 401
    assert client.post(
        "/auth/validar-codigo-recuperacao",
        json={"email": "maria@example.com", "code": code},
    ).status_code == 400
    assert login(client).status_code == 401
    assert login(client, password="NovaSenha@123").status_code == 200
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.email == "maria@example.com"))
        assert user.senha_hash != "NovaSenha@123"
        assert pwd.verify("NovaSenha@123", user.senha_hash)


def test_email_recovery_invalid_expired_weak_and_confirmation(client, monkeypatch):
    code = _email_recovery(client, monkeypatch)
    wrong = "000000" if code != "000000" else "111111"
    assert client.post(
        "/auth/validar-codigo-recuperacao",
        json={"email": "maria@example.com", "code": wrong},
    ).status_code == 400
    with SessionLocal() as db:
        row = db.scalar(select(PasswordRecovery))
        row.expira_em = clock.now_utc_naive() - timedelta(seconds=1)
        db.commit()
    assert client.post(
        "/auth/validar-codigo-recuperacao",
        json={"email": "maria@example.com", "code": code},
    ).status_code == 400

    with SessionLocal() as db:
        row = db.scalar(select(PasswordRecovery))
        row.expira_em = clock.now_utc_naive() + timedelta(minutes=10)
        row.tentativas = 0
        db.commit()
    token = client.post(
        "/auth/validar-codigo-recuperacao",
        json={"email": "maria@example.com", "code": code},
    ).json()["recovery_token"]
    assert client.post("/auth/redefinir-senha", json={
        "recovery_token": token,
        "new_password": "fraca123",
        "confirm_new_password": "fraca123",
    }).status_code == 422
    assert client.post("/auth/redefinir-senha", json={
        "recovery_token": token,
        "new_password": "NovaSenha@123",
        "confirm_new_password": "OutraSenha@123",
    }).status_code == 422


def test_unknown_email_has_same_response_and_no_recovery(client, monkeypatch):
    import app.routes.recovery as recovery_routes

    monkeypatch.setattr(recovery_routes, "send_recovery", lambda email, code: None)
    assert register(client).status_code == 201
    known = client.post("/auth/esqueci-senha", json={"email": "maria@example.com"})
    unknown = client.post("/auth/esqueci-senha", json={"email": "ninguem@example.com"})
    assert known.status_code == unknown.status_code == 200
    assert known.json() == unknown.json()


def test_unverified_email_is_blocked_without_creating_recovery(client, monkeypatch):
    import app.routes.recovery as recovery_routes

    sent = []
    monkeypatch.setattr(
        recovery_routes,
        "send_recovery",
        lambda email, code: sent.append((email, code)),
    )
    response = client.post(
        "/auth/register",
        json={
            "name": "Paciente Não Confirmada",
            "cpf": "16899535009",
            "cns": "123456789012346",
            "birth_date": "1992-04-10",
            "email": "nao-confirmada@example.com",
            "phone": "11988887777",
            "password": "Paciente@123",
            "password_confirmation": "Paciente@123",
        },
    )
    assert response.status_code == 201

    blocked = client.post(
        "/auth/esqueci-senha", json={"email": "nao-confirmada@example.com"}
    )
    assert blocked.status_code == 403
    assert blocked.json() == {
        "detail": "Confirme seu e-mail antes de solicitar a recuperação de senha."
    }
    assert sent == []
    with SessionLocal() as db:
        assert db.scalar(select(func.count(PasswordRecovery.id))) == 0


def test_email_recovery_resend_wait_and_release(client, monkeypatch):
    import app.routes.recovery as recovery_routes

    sent = []
    monkeypatch.setattr(
        recovery_routes,
        "send_recovery",
        lambda email, code: sent.append((email, code)) if email else None,
    )
    assert register(client).status_code == 201

    first = client.post(
        "/auth/esqueci-senha", json={"email": "maria@example.com"}
    )
    immediate = client.post(
        "/auth/esqueci-senha", json={"email": "maria@example.com"}
    )
    assert first.status_code == immediate.status_code == 200
    assert first.json() == immediate.json()
    assert len(sent) == 1
    with SessionLocal() as db:
        assert db.scalar(select(func.count(PasswordRecovery.id))) == 1
        row = db.scalar(select(PasswordRecovery))
        row.criado_em = clock.now_utc_naive() - timedelta(seconds=61)
        db.commit()

    released = client.post(
        "/auth/esqueci-senha", json={"email": "maria@example.com"}
    )
    assert released.status_code == 200
    assert released.json() == first.json()
    assert len(sent) == 2
    with SessionLocal() as db:
        rows = list(db.scalars(select(PasswordRecovery).order_by(PasswordRecovery.id)))
        assert len(rows) == 2
        assert rows[0].utilizado is True
        assert rows[1].utilizado is False


def test_email_recovery_attempt_limit_and_reset_requires_token(client, monkeypatch):
    code = _email_recovery(client, monkeypatch)
    wrong = "000000" if code != "000000" else "111111"
    for _ in range(5):
        response = client.post(
            "/auth/validar-codigo-recuperacao",
            json={"email": "maria@example.com", "code": wrong},
        )
        assert response.status_code == 400

    blocked = client.post(
        "/auth/validar-codigo-recuperacao",
        json={"email": "maria@example.com", "code": code},
    )
    assert blocked.status_code == 429
    assert "código" not in blocked.text.lower()
    with SessionLocal() as db:
        row = db.scalar(select(PasswordRecovery))
        assert row.tentativas == 5
        assert row.verificado is False

    assert client.post(
        "/auth/redefinir-senha",
        json={
            "recovery_token": "token-invalido",
            "new_password": "NovaSenha@123",
            "confirm_new_password": "NovaSenha@123",
        },
    ).status_code == 401
    assert client.post(
        "/auth/redefinir-senha",
        json={
            "new_password": "NovaSenha@123",
            "confirm_new_password": "NovaSenha@123",
        },
    ).status_code == 422


def _next_weekday():
    day = (clock.now_sao_paulo_naive() + timedelta(days=2)).replace(
        hour=7, minute=0, second=0, microsecond=0
    )
    while day.weekday() >= 5:
        day += timedelta(days=1)
    return day


def test_calendar_states_and_invalid_periods(client):
    assert register(client).status_code == 201
    assert register(client, cpf="12345678909", email="outro@example.com").status_code == 201
    first_token = login(client).json()["access_token"]
    with SessionLocal() as db:
        patients = list(db.scalars(select(User).where(User.perfil == "paciente").order_by(User.id)))
        doctor = User(
            nome="Dra. Clínica Geral",
            cpf="11144477735",
            email="clinica@example.com",
            senha_hash=pwd.hash("Medico@123"),
            perfil="medico",
        )
        db.add(doctor)
        db.flush()
        base = _next_weekday()
        slots = [base.replace(hour=hour) for hour in (7, 8, 9, 10, 17)]
        for at in slots:
            db.add(ProfessionalSchedule(
                medico_id=doctor.id,
                especialidade="Clínica Geral",
                data_horario=at,
                bloqueado=at.hour == 10,
            ))
        db.add_all([
            Appointment(
                paciente_id=patients[1].id,
                medico_id=doctor.id,
                especialidade="Clínica Geral",
                data_horario=slots[1],
                status="agendado",
            ),
            Appointment(
                paciente_id=patients[0].id,
                medico_id=doctor.id,
                especialidade="Clínica Geral",
                data_horario=slots[2],
                status="agendado",
            ),
        ])
        db.commit()
        doctor_id = doctor.id
    headers = {"Authorization": f"Bearer {first_token}"}
    day = base.date().isoformat()
    response = client.get(
        f"/availability/calendar-times?specialty=Cl%C3%ADnica%20Geral&doctor_id={doctor_id}&day={day}",
        headers=headers,
    )
    assert response.status_code == 200
    states = {item["scheduled_at"][11:13]: item["label"] for item in response.json()}
    assert states == {
        "07": "Disponível",
        "08": "Indisponível",
        "09": "Já agendado",
        "10": "Indisponível",
        "17": "Disponível",
    }
    assert all("patient" not in item for item in response.json())
    weekend = base
    while weekend.weekday() < 5:
        weekend += timedelta(days=1)
    assert client.get(
        f"/availability/calendar-times?specialty=Cl%C3%ADnica%20Geral&doctor_id={doctor_id}&day={weekend.date().isoformat()}",
        headers=headers,
    ).json() == []
    past = (clock.now_sao_paulo_naive() - timedelta(days=1)).date().isoformat()
    assert client.get(
        f"/availability/calendar-times?specialty=Cl%C3%ADnica%20Geral&doctor_id={doctor_id}&day={past}",
        headers=headers,
    ).json() == []


def test_initial_schedule_has_fourteen_weekdays_including_17h(client):
    from app.main import ensure_future_general_schedule

    with SessionLocal() as db:
        doctor = User(
            nome="Dra. Agenda Futura",
            cpf="11144477735",
            email="agenda@example.com",
            senha_hash=pwd.hash("Medico@123"),
            perfil="medico",
        )
        db.add(doctor)
        db.flush()
        specialty = db.scalar(select(Specialty).where(
            func.lower(Specialty.nome) == "clínica geral"
        ))
        db.add(ProfessionalProfile(
            usuario_id=doctor.id,
            registro_profissional="CRM-AGENDA-FUTURA",
            especialidade_id=specialty.id,
            ativo=True,
        ))
        db.commit()
        assert ensure_future_general_schedule(db) == 140
        assert ensure_future_general_schedule(db) == 0
        rows = list(db.scalars(select(ProfessionalSchedule).where(
            ProfessionalSchedule.medico_id == doctor.id)))
        assert len(rows) == 140
        assert len({row.data_horario.date() for row in rows}) == 14
        assert {row.data_horario.hour for row in rows} == {
            7, 8, 9, 10, 11, 13, 14, 15, 16, 17
        }
        assert all(row.data_horario.weekday() < 5 for row in rows)
