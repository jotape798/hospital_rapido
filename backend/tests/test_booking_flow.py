"""Regressões do agendamento usando exclusivamente o SQLite temporário de testes."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy import func, select

# Este módulo configura DATABASE_URL temporária antes de importar app.*.
from test_integration import client, future_weekday, header, register

from app.core.database import SessionLocal
from app.core import clock
from app.core.security import make_token, pwd
from app.models import (
    Appointment,
    ProfessionalProfile,
    ProfessionalSchedule,
    Specialty,
    User,
)


def _booking_context(*, slots: int = 2):
    at = future_weekday(hour=9, days=3)
    with SessionLocal() as db:
        specialty = db.scalar(select(Specialty).where(
            func.lower(Specialty.nome) == "clínica geral"
        ))
        specialty.ativo = True
        doctor = User(
            nome="Médico Agenda Fictícia",
            cpf="39053344705",
            email="medico.agenda@example.test",
            senha_hash=pwd.hash("Medico@123"),
            perfil="medico",
            ativo=True,
            email_verificado=True,
        )
        reception = User(
            nome="Recepção Agenda Fictícia",
            cpf="98765432100",
            email="recepcao.agenda@example.test",
            senha_hash=pwd.hash("Recepcao@123"),
            perfil="recepcao",
            ativo=True,
            email_verificado=True,
        )
        db.add_all([doctor, reception])
        db.flush()
        profile = ProfessionalProfile(
            usuario_id=doctor.id,
            registro_profissional="CRM-AGENDA-TESTE",
            especialidade_id=specialty.id,
            ativo=True,
        )
        db.add(profile)
        for offset in range(slots):
            db.add(ProfessionalSchedule(
                medico_id=doctor.id,
                especialidade=specialty.nome,
                data_horario=at + timedelta(hours=offset),
                bloqueado=False,
            ))
        db.commit()
        return {
            "at": at,
            "doctor_id": doctor.id,
            "specialty_id": specialty.id,
            "profile_id": profile.id,
            "reception_headers": {
                "Authorization": f"Bearer {make_token(reception)}"
            },
        }


def _payload(context, at=None):
    return {
        "doctor_id": context["doctor_id"],
        "specialty": "Clínica geral",
        "scheduled_at": (at or context["at"]).isoformat(),
    }


def test_valid_booking_updates_patient_reception_and_availability(client):
    assert register(client).status_code == 201
    patient_headers = header(client)
    context = _booking_context(slots=1)

    dates_before = client.get(
        "/availability/calendar-dates",
        headers=patient_headers,
        params={
            "specialty": "Clínica geral",
            "doctor_id": context["doctor_id"],
        },
    )
    assert dates_before.status_code == 200
    assert dates_before.json() == [context["at"].date().isoformat()]

    created = client.post(
        "/appointments", headers=patient_headers, json=_payload(context)
    )
    assert created.status_code == 201
    appointment_id = created.json()["id"]
    assert appointment_id in {
        item["id"] for item in client.get(
            "/appointments/me", headers=patient_headers
        ).json()
    }
    reception = client.get(
        "/recepcao/agendamentos",
        headers=context["reception_headers"],
        params={"day": context["at"].date().isoformat()},
    )
    assert reception.status_code == 200
    assert appointment_id in {item["id"] for item in reception.json()}

    times = client.get(
        "/availability/calendar-times",
        headers=patient_headers,
        params={
            "specialty": "Clínica geral",
            "doctor_id": context["doctor_id"],
            "day": context["at"].date().isoformat(),
        },
    ).json()
    assert times[0]["availability"] == "already_scheduled"
    assert times[0]["selectable"] is False
    assert client.get(
        "/availability/calendar-dates",
        headers=patient_headers,
        params={
            "specialty": "Clínica geral",
            "doctor_id": context["doctor_id"],
        },
    ).json() == []


def test_occupied_slot_and_second_same_day_specialty_are_rejected(client):
    assert register(client).status_code == 201
    first_headers = header(client)
    context = _booking_context(slots=2)
    assert client.post(
        "/appointments", headers=first_headers, json=_payload(context)
    ).status_code == 201

    same_day = client.post(
        "/appointments",
        headers=first_headers,
        json=_payload(context, context["at"] + timedelta(hours=1)),
    )
    assert same_day.status_code == 409
    assert "RN01" in same_day.json()["detail"]

    assert register(
        client, cpf="12345678909", email="outro.paciente@example.com"
    ).status_code == 201
    second_login = client.post("/auth/login", json={
        "document": "12345678909", "password": "Paciente@123"
    })
    second_headers = {
        "Authorization": f"Bearer {second_login.json()['access_token']}"
    }
    occupied = client.post(
        "/appointments", headers=second_headers, json=_payload(context)
    )
    assert occupied.status_code == 409
    assert "não está disponível" in occupied.json()["detail"]


def test_past_date_is_rejected(client):
    assert register(client).status_code == 201
    patient_headers = header(client)
    context = _booking_context(slots=1)
    past = clock.now_sao_paulo_naive().replace(
        hour=9, minute=0, second=0, microsecond=0
    ) - timedelta(days=1)
    response = client.post(
        "/appointments", headers=patient_headers, json=_payload(context, past)
    )
    assert response.status_code == 422
    assert "futuro" in response.json()["detail"]


@pytest.mark.parametrize("inactive", ["doctor", "specialty", "profile"])
def test_inactive_booking_links_are_hidden_and_rejected(client, inactive):
    assert register(client).status_code == 201
    patient_headers = header(client)
    context = _booking_context(slots=1)
    with SessionLocal() as db:
        if inactive == "doctor":
            db.get(User, context["doctor_id"]).ativo = False
        elif inactive == "specialty":
            db.get(Specialty, context["specialty_id"]).ativo = False
        else:
            db.get(ProfessionalProfile, context["profile_id"]).ativo = False
        db.commit()

    dates = client.get(
        "/availability/calendar-dates",
        headers=patient_headers,
        params={
            "specialty": "Clínica geral",
            "doctor_id": context["doctor_id"],
        },
    )
    assert dates.status_code == 200
    assert dates.json() == []
    response = client.post(
        "/appointments", headers=patient_headers, json=_payload(context)
    )
    assert response.status_code == 422
    assert "ativo e vinculado" in response.json()["detail"]


def test_day_without_free_slots_is_not_offered_as_available_date(client):
    assert register(client).status_code == 201
    patient_headers = header(client)
    context = _booking_context(slots=1)
    with SessionLocal() as db:
        schedule = db.scalar(select(ProfessionalSchedule).where(
            ProfessionalSchedule.medico_id == context["doctor_id"],
            ProfessionalSchedule.data_horario == context["at"],
        ))
        schedule.bloqueado = True
        db.commit()

    assert client.get(
        "/availability/calendar-dates",
        headers=patient_headers,
        params={
            "specialty": "Clínica geral",
            "doctor_id": context["doctor_id"],
        },
    ).json() == []
    times = client.get(
        "/availability/calendar-times",
        headers=patient_headers,
        params={
            "specialty": "Clínica geral",
            "doctor_id": context["doctor_id"],
            "day": context["at"].date().isoformat(),
        },
    ).json()
    assert times[0]["availability"] == "unavailable"
    assert times[0]["selectable"] is False


def test_legacy_schedule_on_national_holiday_is_hidden_and_rejected(client, monkeypatch):
    fixed_now = datetime(2026, 10, 23, 9, 0, 0)
    holiday = datetime(2026, 12, 25, 9, 0, 0)
    monkeypatch.setattr(clock, "now_sao_paulo_naive", lambda: fixed_now)
    monkeypatch.setattr(clock, "today_sao_paulo", lambda: fixed_now.date())

    assert register(client).status_code == 201
    patient_headers = header(client)
    context = _booking_context(slots=0)
    with SessionLocal() as db:
        db.add(ProfessionalSchedule(
            medico_id=context["doctor_id"],
            especialidade="Clínica Geral",
            data_horario=holiday,
            bloqueado=False,
        ))
        db.commit()

    params = {
        "specialty": "Clínica Geral",
        "doctor_id": context["doctor_id"],
    }
    assert client.get(
        "/availability/calendar-dates", headers=patient_headers, params=params
    ).json() == []
    assert client.get(
        "/availability/calendar-times",
        headers=patient_headers,
        params={**params, "day": holiday.date().isoformat()},
    ).json() == []
    response = client.post(
        "/appointments",
        headers=patient_headers,
        json=_payload(context, holiday),
    )
    assert response.status_code == 422
    assert "feriado" in response.json()["detail"]

