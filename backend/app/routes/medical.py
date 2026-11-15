"""Fila e atendimento exclusivo do perfil Medico."""

from datetime import date, datetime, time, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.core.database import get_db
from app.core import clock
from app.core.risk import RISK_LABELS
from app.core.specialty import canonical_specialty_name
from app.core.security import require_roles
from app.models import Appointment, AppointmentStatusHistory, RiskClassification, User
from app.schemas import MedicalCareResponse, MedicalCompletion
from app.services.appointments import (
    full_age,
    legal_priority_code,
    legal_priority_label,
    queue_sort_key,
    record_audit_event,
)

router = APIRouter(prefix="/medico", tags=["medico"])
_MISSING_RISK = object()

def _age(patient: User) -> int | None:
    return full_age(patient.data_nascimento) if patient.data_nascimento else None


def _risk(db: Session, appointment_id: int) -> RiskClassification | None:
    return db.scalar(
        select(RiskClassification).where(
            RiskClassification.consulta_id == appointment_id
        )
    )


def _risks(db: Session, appointment_ids: list[int]) -> dict[int, RiskClassification]:
    if not appointment_ids:
        return {}
    return {
        item.consulta_id: item
        for item in db.scalars(
            select(RiskClassification).where(
                RiskClassification.consulta_id.in_(appointment_ids)
            )
        )
    }


def _appointment_options():
    return (
        joinedload(Appointment.paciente).selectinload(User.condicoes_prioritarias),
        joinedload(Appointment.medico),
    )


def _authorized_row(db: Session, appointment_id: int, actor: User) -> Appointment:
    row = db.scalar(
        select(Appointment)
        .options(*_appointment_options())
        .where(Appointment.id == appointment_id)
    )
    if not row:
        raise HTTPException(404, "Atendimento não encontrado")
    if row.medico_id != actor.id:
        raise HTTPException(403, "Acesso permitido apenas aos atendimentos atribuídos")
    return row


def _ensure_triaged(db: Session, row: Appointment) -> RiskClassification:
    risk = _risk(db, row.id)
    if (
        not row.chegada_em
        or not row.triagem_em
        or not row.classificacao_risco
        or not risk
        or not risk.queixa_principal
        or not risk.sinais_vitais
    ):
        raise HTTPException(409, "Paciente ainda não possui triagem concluída")
    return risk


def _payload(
    db: Session,
    row: Appointment,
    risk: RiskClassification | object = _MISSING_RISK,
) -> dict:
    if risk is _MISSING_RISK:
        risk = _ensure_triaged(db, row)
    if not isinstance(risk, RiskClassification):
        raise HTTPException(409, "Paciente ainda não possui triagem concluída")
    return {
        "id": row.id,
        "scheduled_at": row.data_horario,
        "patient": row.paciente.nome,
        "age": _age(row.paciente),
        "specialty": canonical_specialty_name(row.especialidade),
        "professional": row.medico.nome,
        "professional_id": row.medico_id,
        "status": row.status,
        "legal_priority": legal_priority_code(row.paciente),
        "priority_reason": legal_priority_label(row.paciente),
        "risk_classification": risk.nivel_risco,
        "risk_label": RISK_LABELS.get(risk.nivel_risco, risk.nivel_risco),
        "triage_complaint": risk.queixa_principal,
        "vital_signs": risk.sinais_vitais,
        "triage_observation": risk.observacao,
        "arrived_at": row.chegada_em,
        "triaged_at": row.triagem_em,
        "called_at": row.chamado_em,
        "started_at": row.iniciado_em,
        "completed_at": row.concluido_em,
        "care_summary": row.resumo_atendimento,
    }


@router.get(
    "/fila",
    response_model=list[MedicalCareResponse],
    summary="Listar fila do profissional de atendimento",
    description=(
        "Perfil autorizado: Médico/Profissional de atendimento. Retorna somente "
        "consultas atribuídas à conta autenticada, com check-in e triagem concluídos."
    ),
    responses={
        401: {"description": "Token ausente ou inválido."},
        403: {"description": "Perfil sem acesso à fila de atendimento."},
    },
)
def medical_queue(
    actor: User = Depends(require_roles("medico")),
    db: Session = Depends(get_db),
):
    start = datetime.combine(clock.today_sao_paulo(), time.min)
    end = start + timedelta(days=1)
    rows = list(
        db.scalars(
            select(Appointment).options(*_appointment_options()).where(
                Appointment.medico_id == actor.id,
                Appointment.data_horario >= start,
                Appointment.data_horario < end,
                Appointment.chegada_em.is_not(None),
                Appointment.triagem_em.is_not(None),
                Appointment.classificacao_risco.is_not(None),
                Appointment.status.in_(["em_triagem", "em_atendimento"]),
            )
        ).unique()
    )
    risk_records = _risks(db, [row.id for row in rows])
    eligible = []
    for row in rows:
        risk = risk_records.get(row.id)
        if risk and risk.queixa_principal and risk.sinais_vitais:
            eligible.append(row)
    return [
        _payload(db, row, risk_records[row.id])
        for row in sorted(eligible, key=queue_sort_key)
    ]


@router.get("/atendimentos/{appointment_id}", response_model=MedicalCareResponse)
def medical_details(
    appointment_id: int,
    actor: User = Depends(require_roles("medico")),
    db: Session = Depends(get_db),
):
    row = _authorized_row(db, appointment_id, actor)
    if row.status not in {"em_triagem", "em_atendimento"}:
        raise HTTPException(409, "Atendimento não está disponível na fila médica")
    return _payload(db, row)


@router.patch("/atendimentos/{appointment_id}/chamar", response_model=MedicalCareResponse)
def call_medical_patient(
    appointment_id: int,
    actor: User = Depends(require_roles("medico")),
    db: Session = Depends(get_db),
):
    row = _authorized_row(db, appointment_id, actor)
    _ensure_triaged(db, row)
    if row.status != "em_triagem":
        raise HTTPException(409, "Somente paciente aguardando Médico pode ser chamado")
    row.chamado_em = clock.now_sao_paulo_naive()
    db.commit()
    return _payload(db, row)


@router.patch("/atendimentos/{appointment_id}/iniciar", response_model=MedicalCareResponse)
def start_medical_care(
    appointment_id: int,
    actor: User = Depends(require_roles("medico")),
    db: Session = Depends(get_db),
):
    row = _authorized_row(db, appointment_id, actor)
    _ensure_triaged(db, row)
    if row.status != "em_triagem":
        raise HTTPException(409, "Somente paciente encaminhado pela triagem pode iniciar atendimento")
    concurrent = db.scalar(
        select(Appointment.id).where(
            Appointment.id != row.id,
            Appointment.paciente_id == row.paciente_id,
            Appointment.status == "em_atendimento",
        )
    )
    if concurrent:
        raise HTTPException(409, "Paciente já está em atendimento com outro Médico")
    now = clock.now_sao_paulo_naive()
    row.iniciado_em = now
    row.atendimento_medico_id = actor.id
    row.status = "em_atendimento"
    db.add(
        AppointmentStatusHistory(
            consulta_id=row.id,
            status_anterior="em_triagem",
            status_novo="em_atendimento",
            alterado_por=actor.id,
        )
    )
    record_audit_event(db, actor, "atendimento_iniciado", "consulta", row.id, {
        "status_anterior": "em_triagem", "status_novo": "em_atendimento",
    })
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Paciente já está em atendimento com outro Médico")
    return _payload(db, row)


@router.patch("/atendimentos/{appointment_id}/concluir", response_model=MedicalCareResponse)
def complete_medical_care(
    appointment_id: int,
    payload: MedicalCompletion,
    actor: User = Depends(require_roles("medico")),
    db: Session = Depends(get_db),
):
    row = _authorized_row(db, appointment_id, actor)
    _ensure_triaged(db, row)
    if row.status != "em_atendimento" or not row.iniciado_em:
        raise HTTPException(409, "Inicie o atendimento antes de concluí-lo")
    if row.atendimento_medico_id != actor.id:
        raise HTTPException(403, "Somente o Médico que iniciou pode concluir o atendimento")
    row.resumo_atendimento = payload.summary
    row.concluido_em = clock.now_sao_paulo_naive()
    row.status = "concluido"
    db.add(
        AppointmentStatusHistory(
            consulta_id=row.id,
            status_anterior="em_atendimento",
            status_novo="concluido",
            alterado_por=actor.id,
        )
    )
    record_audit_event(db, actor, "atendimento_concluido", "consulta", row.id, {
        "status_anterior": "em_atendimento", "status_novo": "concluido",
    })
    db.commit()
    return _payload(db, row)
