"""Painéis operacionais protegidos da recepção e da enfermagem."""

from datetime import date, datetime, time, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core import clock
from app.core.risk import RISK_LABELS, RiskLevel
from app.core.specialty import canonical_specialty_name
from app.core.security import require_roles
from app.services.appointments import (
    legal_priority_code,
    legal_priority_label,
    queue_sort_key,
    record_audit_event,
    register_manual_absence,
)
from app.models import (
    Appointment,
    AppointmentStatusHistory,
    PriorityCondition,
    PriorityConditionHistory,
    ProfessionalProfile,
    RiskClassification,
    User,
)
from app.schemas import PriorityValidationInput

router = APIRouter(tags=["recepção e enfermagem"])

class RiskInput(BaseModel):
    level: RiskLevel
    complaint: str = Field(min_length=3, max_length=500)
    vital_signs: str = Field(min_length=3, max_length=500)
    observation: str | None = Field(default=None, max_length=500)


def _day_limits(day: date) -> tuple[datetime, datetime]:
    start = datetime.combine(day, time.min)
    return start, start + timedelta(days=1)


def _risk_record(db: Session, appointment_id: int) -> RiskClassification | None:
    return db.scalar(
        select(RiskClassification).where(
            RiskClassification.consulta_id == appointment_id
        )
    )


def _appointment_payload(db: Session, row: Appointment) -> dict:
    risk = _risk_record(db, row.id)
    return {
        "id": row.id,
        "scheduled_at": row.data_horario,
        "patient": row.paciente.nome,
        "patient_document": _mask_cpf(row.paciente.cpf),
        "specialty": canonical_specialty_name(row.especialidade),
        "professional": row.medico.nome,
        "professional_id": row.medico_id,
        "status": row.status,
        "legal_priority": legal_priority_code(row.paciente),
        "priority_reason": legal_priority_label(row.paciente),
        "risk_classification": risk.nivel_risco if risk else row.classificacao_risco,
        "risk_label": RISK_LABELS.get(
            risk.nivel_risco if risk else row.classificacao_risco or ""
        ),
        "triage_observation": risk.observacao if risk else row.triagem_dados,
        "triage_complaint": risk.queixa_principal if risk else None,
        "vital_signs": risk.sinais_vitais if risk else None,
        "arrived_at": row.chegada_em,
        "missed_at": row.falta_em,
        "triaged_at": risk.classificado_em if risk else row.triagem_em,
        "called_at": row.chamado_em,
        "started_at": row.iniciado_em,
        "completed_at": row.concluido_em,
        "priority_conditions": [
            {
                "condition": item.condicao,
                "status": item.status,
                "reported_at": item.informada_em,
                "validated_at": item.validada_em,
                "validated_by": (
                    item.responsavel_validacao.nome if item.responsavel_validacao else None
                ),
            }
            for item in sorted(
                row.paciente.condicoes_prioritarias, key=lambda value: value.condicao
            )
            if item.status != "retirada"
        ],
    }


def _mask_cpf(cpf: str) -> str:
    return f"***.***.***-{cpf[-2:]}" if len(cpf or "") == 11 else "***"


def _appointment_or_404(db: Session, appointment_id: int) -> Appointment:
    row = db.get(Appointment, appointment_id)
    if not row:
        raise HTTPException(404, "Agendamento não encontrado")
    return row


def _record_status(db: Session, row: Appointment, new_status: str, actor: User):
    previous = row.status
    row.status = new_status
    db.add(
        AppointmentStatusHistory(
            consulta_id=row.id,
            status_anterior=previous,
            status_novo=new_status,
            alterado_por=actor.id,
        )
    )


def _authorized_nurse(actor: User, db: Session) -> ProfessionalProfile:
    if actor.perfil != "enfermagem":
        raise HTTPException(403, "Somente a enfermagem pode registrar classificação de risco")
    profile = db.scalar(
        select(ProfessionalProfile).where(
            ProfessionalProfile.usuario_id == actor.id,
            ProfessionalProfile.ativo.is_(True),
        )
    )
    if not profile or not profile.autorizado_triagem:
        raise HTTPException(403, "Profissional de enfermagem sem autorização ativa")
    return profile


def _filtered_day_query(
    day: date,
    specialty: str | None,
    professional_id: int | None,
    status: str | None,
    patient: str | None,
):
    start, end = _day_limits(day)
    query = select(Appointment).where(
        Appointment.data_horario >= start, Appointment.data_horario < end
    )
    if specialty:
        query = query.where(
            func.lower(func.trim(Appointment.especialidade))
            == canonical_specialty_name(specialty).lower()
        )
    if professional_id:
        query = query.where(Appointment.medico_id == professional_id)
    if status:
        query = query.where(Appointment.status == status)
    if patient:
        term = patient.strip().lower()
        cpf = "".join(char for char in term if char.isdigit())
        query = query.join(Appointment.paciente).where(
            or_(
                func.lower(User.nome).contains(term),
                User.cpf.contains(cpf) if cpf else False,
            )
        )
    return query


def _ordered_nursing_rows(db: Session, day: date) -> list[Appointment]:
    """Retorna a fila clínica completa na ordem oficial de atendimento."""
    start, end = _day_limits(day)
    rows = list(
        db.scalars(
            select(Appointment).where(
                Appointment.data_horario >= start,
                Appointment.data_horario < end,
                Appointment.chegada_em.is_not(None),
                Appointment.status.in_(["em_espera", "em_triagem"]),
            )
        ).unique()
    )
    return sorted(rows, key=queue_sort_key)


def _initial_triage_rows(rows: list[Appointment]) -> list[Appointment]:
    """Mantém na fila de início somente quem ainda aguarda a primeira triagem."""
    return [row for row in rows if row.status == "em_espera"]


@router.get("/recepcao/resumo")
def reception_summary(
    day: date = Query(default_factory=clock.today_sao_paulo),
    actor: User = Depends(require_roles("recepcao")),
    db: Session = Depends(get_db),
):
    start, end = _day_limits(day)
    counts = dict(
        db.execute(
            select(Appointment.status, func.count(Appointment.id))
            .where(Appointment.data_horario >= start, Appointment.data_horario < end)
            .group_by(Appointment.status)
        ).all()
    )
    return {
        "scheduled": counts.get("agendado", 0),
        "checked_in": counts.get("em_espera", 0) + counts.get("em_triagem", 0),
        "in_care": counts.get("em_atendimento", 0),
        "completed": counts.get("concluido", 0),
        "absent": counts.get("falta", 0),
    }


@router.get("/recepcao/agendamentos")
def reception_appointments(
    day: date = Query(default_factory=clock.today_sao_paulo),
    specialty: str | None = None,
    professional_id: int | None = None,
    status: str | None = None,
    patient: str | None = None,
    actor: User = Depends(require_roles("recepcao")),
    db: Session = Depends(get_db),
):
    query = _filtered_day_query(
        day, specialty, professional_id, status, patient
    ).order_by(Appointment.data_horario)
    return [_appointment_payload(db, row) for row in db.scalars(query).unique()]


@router.get("/recepcao/agendamentos/{appointment_id}")
def reception_details(
    appointment_id: int,
    actor: User = Depends(require_roles("recepcao")),
    db: Session = Depends(get_db),
):
    return _appointment_payload(db, _appointment_or_404(db, appointment_id))


@router.patch(
    "/recepcao/agendamentos/{appointment_id}/check-in",
    summary="Registrar check-in presencial",
    description=(
        "Confirma a chegada presencial e move a consulta agendada para a fila de espera. "
        "Perfis autorizados: Recepção e Administrador. A consulta deve existir, estar "
        "agendada para o dia atual da UBS e ainda não possuir check-in."
    ),
    responses={
        401: {"description": "Token de autenticação ausente ou inválido."},
        403: {"description": "Perfil sem autorização para registrar check-in."},
        404: {"description": "Consulta inexistente."},
        409: {
            "description": (
                "Consulta fora do dia, em estado incompatível ou com check-in já realizado."
            )
        },
    },
)
def reception_check_in(
    appointment_id: int,
    actor: User = Depends(require_roles("recepcao", "admin")),
    db: Session = Depends(get_db),
):
    row = _appointment_or_404(db, appointment_id)
    if row.data_horario.date() != clock.today_sao_paulo():
        raise HTTPException(409, "Check-in permitido somente no dia da consulta")
    if row.status != "agendado" or row.chegada_em:
        raise HTTPException(409, "Consulta já recebeu check-in ou possui status incompatível")
    row.chegada_em = clock.now_sao_paulo_naive()
    row.chegada_por = actor.id
    _record_status(db, row, "em_espera", actor)
    record_audit_event(db, actor, "chegada_confirmada", "consulta", row.id, {
        "status_anterior": "agendado", "status_novo": "em_espera",
    })
    db.commit()
    return _appointment_payload(db, row)

@router.patch("/recepcao/agendamentos/{appointment_id}/nao-compareceu")
def reception_absence(
    appointment_id: int,
    actor: User = Depends(require_roles("recepcao")),
    db: Session = Depends(get_db),
):
    row = _appointment_or_404(db, appointment_id)
    register_manual_absence(db, row, actor)
    return _appointment_payload(db, row)


@router.patch(
    "/recepcao/agendamentos/{appointment_id}/condicoes/{condition_name}/validacao"
)
def validate_priority_condition(
    appointment_id: int,
    condition_name: Literal["pcd", "gestante", "lactante"],
    payload: PriorityValidationInput,
    actor: User = Depends(require_roles("recepcao")),
    db: Session = Depends(get_db),
):
    row = _appointment_or_404(db, appointment_id)
    condition = db.scalar(select(PriorityCondition).where(
        PriorityCondition.paciente_id == row.paciente_id,
        PriorityCondition.condicao == condition_name,
    ))
    if not condition:
        raise HTTPException(404, "Condição prioritária não informada pelo paciente")
    previous = condition.status
    if previous == payload.status:
        return _appointment_payload(db, row)
    now = clock.now_sao_paulo_naive()
    condition.status = payload.status
    condition.validada_por = actor.id
    condition.validada_em = now
    db.add(PriorityConditionHistory(
        condicao_prioritaria_id=condition.id,
        status_anterior=previous,
        status_novo=payload.status,
        alterado_por=actor.id,
        criado_em=clock.now_utc_naive(),
    ))
    record_audit_event(
        db,
        actor,
        "validar_condicao_prioritaria",
        "condicao_prioritaria",
        condition.id,
        {
            "condicao": condition_name,
            "status_anterior": previous,
            "status_novo": payload.status,
        },
    )
    db.commit()
    return _appointment_payload(db, row)


@router.get("/enfermagem/resumo")
def nursing_summary(
    day: date = Query(default_factory=clock.today_sao_paulo),
    actor: User = Depends(require_roles("enfermagem")),
    db: Session = Depends(get_db),
):
    _authorized_nurse(actor, db)
    start, end = _day_limits(day)
    rows = list(
        db.scalars(
            select(Appointment).where(
                Appointment.data_horario >= start,
                Appointment.data_horario < end,
                Appointment.chegada_em.is_not(None),
                Appointment.status.in_(["em_espera", "em_triagem"]),
            )
        ).unique()
    )
    risks = {key: 0 for key in RISK_LABELS}
    for row in rows:
        record = _risk_record(db, row.id)
        level = record.nivel_risco if record else row.classificacao_risco
        if level in risks:
            risks[level] += 1
    return {
        "awaiting_triage": sum(row.status == "em_espera" for row in rows),
        "in_care": 0,
        "completed": 0,
        "risk_counts": risks,
    }


@router.get("/enfermagem/fila")
def nursing_queue(
    day: date = Query(default_factory=clock.today_sao_paulo),
    specialty: str | None = None,
    status: str | None = None,
    risk: str | None = None,
    actor: User = Depends(require_roles("enfermagem")),
    db: Session = Depends(get_db),
):
    _authorized_nurse(actor, db)
    ordered_rows = _ordered_nursing_rows(db, day)
    initial_rows = _initial_triage_rows(ordered_rows)
    first_id = initial_rows[0].id if initial_rows else None
    rows = ordered_rows
    if specialty:
        canonical = canonical_specialty_name(specialty).casefold()
        rows = [
            row
            for row in rows
            if canonical_specialty_name(row.especialidade).casefold() == canonical
        ]
    if status:
        rows = [row for row in rows if row.status == status]
    if risk:
        if risk not in RISK_LABELS:
            raise HTTPException(422, "Classificação de risco inválida")
        filtered = []
        for row in rows:
            record = _risk_record(db, row.id)
            level = record.nivel_risco if record else row.classificacao_risco
            if level == risk:
                filtered.append(row)
        rows = filtered

    result = []
    for row in rows:
        payload = _appointment_payload(db, row)
        allowed = row.status == "em_triagem" or row.id == first_id
        payload["triage_action_allowed"] = allowed
        payload["triage_block_reason"] = (
            None if allowed else "Outro paciente está à frente na fila."
        )
        result.append(payload)
    return result


@router.get("/enfermagem/agendamentos/{appointment_id}")
def nursing_details(
    appointment_id: int,
    actor: User = Depends(require_roles("enfermagem")),
    db: Session = Depends(get_db),
):
    _authorized_nurse(actor, db)
    row = _appointment_or_404(db, appointment_id)
    if not row.chegada_em:
        raise HTTPException(409, "Paciente ainda não realizou check-in")
    return _appointment_payload(db, row)


@router.patch("/enfermagem/agendamentos/{appointment_id}/classificacao-risco")
def classify_risk(
    appointment_id: int,
    payload: RiskInput,
    actor: User = Depends(require_roles("enfermagem")),
    db: Session = Depends(get_db),
):
    _authorized_nurse(actor, db)
    row = _appointment_or_404(db, appointment_id)
    if not row.chegada_em:
        raise HTTPException(409, "Não é possível classificar risco sem check-in")
    if row.status not in {"em_espera", "em_triagem"}:
        raise HTTPException(409, "Classificação incompatível com o status atual")
    if row.status == "em_espera":
        ordered_rows = _ordered_nursing_rows(db, row.data_horario.date())
        initial_rows = _initial_triage_rows(ordered_rows)
        if not initial_rows or initial_rows[0].id != row.id:
            raise HTTPException(409, "Outro paciente está à frente na fila de triagem")
    now = clock.now_sao_paulo_naive()
    record = _risk_record(db, row.id)
    if record:
        record.nivel_risco = payload.level
        record.queixa_principal = payload.complaint.strip()
        record.sinais_vitais = payload.vital_signs.strip()
        record.observacao = payload.observation.strip() if payload.observation else None
        record.profissional_id = actor.id
        record.classificado_em = now
    else:
        db.add(
            RiskClassification(
                consulta_id=row.id,
                profissional_id=actor.id,
                nivel_risco=payload.level,
                queixa_principal=payload.complaint.strip(),
                sinais_vitais=payload.vital_signs.strip(),
                observacao=payload.observation.strip() if payload.observation else None,
                classificado_em=now,
            )
        )
    row.classificacao_risco = payload.level
    triage_parts = [
        f"Queixa: {payload.complaint.strip()}",
        f"Sinais vitais: {payload.vital_signs.strip()}",
    ]
    if payload.observation:
        triage_parts.append(f"Observação: {payload.observation.strip()}")
    row.triagem_dados = "\n".join(triage_parts)
    row.triagem_por = actor.id
    row.triagem_em = now
    previous_status = row.status
    if row.status == "em_espera":
        _record_status(db, row, "em_triagem", actor)
    record_audit_event(db, actor, "triagem_registrada", "consulta", row.id, {
        "status_anterior": previous_status, "status_novo": row.status,
    })
    db.commit()
    return _appointment_payload(db, row)

# Fim das rotas oficiais da recepção e da enfermagem.
