"""Administração, agenda diária e auditoria com autorização no servidor."""
from datetime import date, datetime, time, timedelta
import json
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import and_, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from app.core.database import get_db
from app.core import clock
from app.core.risk import RISK_LEVELS
from app.core.specialty import GENERAL_SPECIALTY, canonical_specialty_name, specialty_key
from app.core.security import canonical_role, pwd, require_roles
from app.models import (
    Appointment, AuditLog, ProfessionalProfile,
    ProfessionalSchedule, PriorityCondition, PriorityConditionHistory,
    ScheduleBlock, ScheduleGrid, Specialty, User,
)
from app.schemas import (
    AccessReset,
    CatalogItem,
    DoctorCreate,
    DoctorResponse,
    DoctorUpdate,
    InternalUserCreate,
    InternalUserResponse,
    InternalUserUpdate,
)
from app.services.appointments import (
    legal_priority_code, legal_priority_label, mark_overdue_absences,
    record_audit_event, register_manual_absence,
)

router = APIRouter(prefix="/admin", tags=["administração"])

APPOINTMENT_STATUSES = {
    "agendado", "em_espera", "em_triagem", "em_atendimento",
    "concluido", "cancelado", "falta",
}


def audit(db: Session, actor: User, action: str, kind: str, record_id: int | None, details: dict | None = None):
    record_audit_event(db, actor, action, kind, record_id, details)


def mask_cpf(cpf: str) -> str:
    return f"***.***.***-{cpf[-2:]}" if len(cpf or "") == 11 else "***"


def professional_label(user: User, profile: ProfessionalProfile | None) -> str:
    role = canonical_role(user.perfil)
    if role == "recepcao":
        return "Recepção"
    if role == "enfermagem":
        return "Enfermagem"
    if role == "medico" and profile:
        registration = profile.registro_profissional.upper()
        if registration.startswith("CRO-") or specialty_key(profile.especialidade.nome) == specialty_key("Odontologia"):
            return "Dentista"
    return "Médico" if role == "medico" else role.title()


def doctor_response(db: Session, user: User) -> DoctorResponse:
    profile = db.scalar(
        select(ProfessionalProfile).where(ProfessionalProfile.usuario_id == user.id)
    )
    return DoctorResponse(
        id=user.id,
        name=user.nome,
        masked_cpf=mask_cpf(user.cpf),
        active=user.ativo,
        specialty=(canonical_specialty_name(profile.especialidade.nome)
                   if profile else GENERAL_SPECIALTY),
        profession=professional_label(user, profile),
    )


def general_specialty(db: Session) -> Specialty:
    specialty = db.scalar(
        select(Specialty).where(
            func.lower(func.trim(Specialty.nome)) == GENERAL_SPECIALTY.lower()
        )
    )
    if not specialty:
        specialty = Specialty(nome=GENERAL_SPECIALTY, ativo=True)
        db.add(specialty)
        db.flush()
    elif not specialty.ativo:
        specialty.ativo = True
    return specialty


def technical_doctor_email(cpf: str) -> str:
    return f"medico.{cpf}@ubs-rapida.local"


def internal_response(db: Session, user: User) -> InternalUserResponse:
    profile = db.scalar(select(ProfessionalProfile).where(ProfessionalProfile.usuario_id == user.id))
    return InternalUserResponse(
        id=user.id, name=user.nome, masked_cpf=mask_cpf(user.cpf), email=user.email,
        role=canonical_role(user.perfil), active=user.ativo, created_at=user.criado_em,
        profession=professional_label(user, profile),
        updated_at=user.atualizado_em,
        professional_registration=(profile.registro_profissional if profile and
                                   not profile.registro_profissional.startswith("SEM-REGISTRO-") else None),
        specialty_id=profile.especialidade_id if profile else None,
        specialty=profile.especialidade.nome if profile else None,
        can_triage=profile.autorizado_triagem if profile else user.perfil == "enfermagem",
    )


def validate_identity(name: str, cpf: str, password: str | None = None):
    from app.main import digits, valid_cpf, valid_name, valid_password
    normalized = digits(cpf)
    if not valid_name(name):
        raise HTTPException(422, {"field": "name", "message": "Informe nome e sobrenome, apenas letras, espaços e acentos."})
    if any(c not in "0123456789.- " for c in cpf) or not valid_cpf(normalized):
        raise HTTPException(422, {"field": "cpf", "message": "CPF inválido."})
    if password is not None and not valid_password(password):
        raise HTTPException(422, {"field": "password", "message": "A senha deve ter 8 a 32 caracteres, maiúscula, minúscula, número e símbolo."})
    return normalized


def ensure_professional_fields(db: Session, role: str, registration: str | None, specialty_id: int | None):
    if role not in {"medico", "enfermagem"}:
        return None
    specialty = db.get(Specialty, specialty_id) if specialty_id else None
    if not specialty or not specialty.ativo:
        raise HTTPException(422, {"field": "specialty_id", "message": "Selecione uma especialidade ativa."})
    return specialty


@router.get("/users", response_model=list[InternalUserResponse])
def list_users(q: str | None = None, role: str | None = None, active: bool | None = None,
               actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    query = select(User).where(User.perfil != "paciente")
    if q:
        term = q.strip().lower()
        cpf = "".join(char for char in term if char.isdigit())
        query = query.where(
            or_(func.lower(User.nome).contains(term), User.cpf.contains(cpf) if cpf else False)
        )
    if role:
        values = ["profissional", "medico"] if role in {"profissional", "medico"} else [role]
        query = query.where(User.perfil.in_(values))
    if active is not None:
        query = query.where(User.ativo.is_(active))
    return [internal_response(db, row) for row in db.scalars(query.order_by(User.nome))]


@router.get("/medicos", response_model=list[DoctorResponse])
def list_doctors(
    q: str | None = None,
    active: bool | None = None,
    actor: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    query = select(User).where(User.perfil.in_(["medico", "profissional"]))
    if q:
        term = q.strip().lower()
        cpf = "".join(char for char in term if char.isdigit())
        query = query.where(
            or_(func.lower(User.nome).contains(term), User.cpf.contains(cpf) if cpf else False)
        )
    if active is not None:
        query = query.where(User.ativo.is_(active))
    return [doctor_response(db, row) for row in db.scalars(query.order_by(User.nome))]


@router.post("/medicos", response_model=DoctorResponse, status_code=201)
def create_doctor(
    payload: DoctorCreate,
    actor: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    cpf = validate_identity(payload.name, payload.cpf, payload.password)
    if payload.password != payload.password_confirmation:
        raise HTTPException(
            422,
            {"field": "password_confirmation", "message": "As senhas não coincidem."},
        )
    if db.scalar(select(User.id).where(User.cpf == cpf)):
        raise HTTPException(409, {"field": "cpf", "message": "CPF já cadastrado."})
    specialty = general_specialty(db)
    user = User(
        nome=payload.name.strip(),
        cpf=cpf,
        email=technical_doctor_email(cpf),
        senha_hash=pwd.hash(payload.password),
        perfil="medico",
        ativo=payload.active,
        email_verificado=True,
        criado_por=actor.id,
        ultima_alteracao_por=actor.id,
    )
    try:
        db.add(user)
        db.flush()
        db.add(
            ProfessionalProfile(
                usuario_id=user.id,
                registro_profissional=f"MEDICO-{cpf}",
                especialidade_id=specialty.id,
                autorizado_triagem=False,
                ativo=payload.active,
            )
        )
        audit(db, actor, "medico_criado", "usuario", user.id, {"ativo": payload.active})
        db.commit()
        db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "CPF já cadastrado")
    return doctor_response(db, user)


@router.put("/medicos/{user_id}", response_model=DoctorResponse)
def update_doctor(
    user_id: int,
    payload: DoctorUpdate,
    actor: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    user = db.get(User, user_id)
    if not user or canonical_role(user.perfil) != "medico":
        raise HTTPException(404, "Médico não encontrado")
    if payload.name is not None:
        validate_identity(payload.name, user.cpf)
        user.nome = payload.name.strip()
    if payload.cpf is not None:
        cpf = validate_identity(user.nome, payload.cpf)
        if db.scalar(select(User.id).where(User.cpf == cpf, User.id != user.id)):
            raise HTTPException(409, {"field": "cpf", "message": "CPF já cadastrado."})
        user.cpf = cpf
        user.email = technical_doctor_email(cpf)
        profile = db.scalar(
            select(ProfessionalProfile).where(ProfessionalProfile.usuario_id == user.id)
        )
        if profile and profile.registro_profissional.startswith("MEDICO-"):
            profile.registro_profissional = f"MEDICO-{cpf}"
        user.token_version += 1
    if payload.active is not None and payload.active != user.ativo:
        user.ativo = payload.active
        user.token_version += 1
        profile = db.scalar(
            select(ProfessionalProfile).where(ProfessionalProfile.usuario_id == user.id)
        )
        if profile:
            profile.ativo = payload.active
    user.perfil = "medico"
    user.ultima_alteracao_por = actor.id
    audit(db, actor, "medico_alterado", "usuario", user.id, {"ativo": user.ativo})
    try:
        db.commit()
        db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "CPF já cadastrado")
    return doctor_response(db, user)


@router.post("/medicos/{user_id}/activate", response_model=DoctorResponse)
def activate_doctor(
    user_id: int,
    actor: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    user = db.get(User, user_id)
    if not user or canonical_role(user.perfil) != "medico":
        raise HTTPException(404, "Médico não encontrado")
    change_active(user_id, True, actor, db)
    return doctor_response(db, db.get(User, user_id))


@router.post("/medicos/{user_id}/deactivate", response_model=DoctorResponse)
def deactivate_doctor(
    user_id: int,
    actor: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    user = db.get(User, user_id)
    if not user or canonical_role(user.perfil) != "medico":
        raise HTTPException(404, "Médico não encontrado")
    change_active(user_id, False, actor, db)
    return doctor_response(db, db.get(User, user_id))


@router.post("/users", response_model=InternalUserResponse, status_code=201)
def create_user(payload: InternalUserCreate, actor: User = Depends(require_roles("admin")),
                db: Session = Depends(get_db)):
    role = canonical_role(payload.role)
    cpf = validate_identity(payload.name, payload.cpf, payload.password)
    if payload.password != payload.password_confirmation:
        raise HTTPException(422, {"field": "password_confirmation", "message": "As senhas não coincidem."})
    ensure_professional_fields(db, role, payload.professional_registration, payload.specialty_id)
    email = str(payload.email).strip().lower()
    if db.scalar(select(User.id).where(or_(User.cpf == cpf, func.lower(User.email) == email))):
        field = "cpf" if db.scalar(select(User.id).where(User.cpf == cpf)) else "email"
        raise HTTPException(409, {"field": field, "message": "CPF já cadastrado." if field == "cpf" else "E-mail já cadastrado."})
    user = User(nome=payload.name.strip(), cpf=cpf, email=email, senha_hash=pwd.hash(payload.password),
                perfil=role, ativo=payload.active, email_verificado=True,
                criado_por=actor.id, ultima_alteracao_por=actor.id)
    try:
        db.add(user); db.flush()
        if role in {"medico", "enfermagem"}:
            registration = (payload.professional_registration or "").strip() or f"SEM-REGISTRO-{user.id}"
            db.add(ProfessionalProfile(usuario_id=user.id,
                registro_profissional=registration,
                especialidade_id=payload.specialty_id,
                autorizado_triagem=role == "enfermagem",
                ativo=payload.active))
        audit(db, actor, "usuario_criado", "usuario", user.id,
              {"perfil": role, "ativo": payload.active})
        db.commit(); db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "CPF, e-mail ou registro profissional já cadastrado")
    return internal_response(db, user)


@router.put("/users/{user_id}", response_model=InternalUserResponse)
def update_user(user_id: int, payload: InternalUserUpdate,
                actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if not user or user.perfil == "paciente":
        raise HTTPException(404, "Usuário interno não encontrado")
    if user.id == actor.id and payload.role and payload.role != canonical_role(user.perfil):
        raise HTTPException(409, "O administrador não pode retirar o próprio perfil")
    if user.perfil == "admin" and payload.role:
        raise HTTPException(409, "Administradores são gerenciados pela ação protegida específica")
    role = canonical_role(payload.role) if payload.role else canonical_role(user.perfil)
    if payload.name is not None:
        validate_identity(payload.name, user.cpf)
        user.nome = payload.name.strip()
    if payload.email is not None:
        email = str(payload.email).strip().lower()
        if db.scalar(select(User.id).where(func.lower(User.email) == email, User.id != user.id)):
            raise HTTPException(409, {"field": "email", "message": "E-mail já cadastrado."})
        user.email = email
    profile = db.scalar(select(ProfessionalProfile).where(ProfessionalProfile.usuario_id == user.id))
    if role in {"medico", "enfermagem"}:
        registration = ((payload.professional_registration or "").strip()
                        or (profile.registro_profissional if profile else None)
                        or f"SEM-REGISTRO-{user.id}")
        specialty_id = payload.specialty_id or (profile.especialidade_id if profile else None)
        ensure_professional_fields(db, role, registration, specialty_id)
        if profile is None:
            profile = ProfessionalProfile(usuario_id=user.id, registro_profissional=registration,
                especialidade_id=specialty_id,
                autorizado_triagem=role == "enfermagem", ativo=user.ativo)
            db.add(profile)
        else:
            profile.registro_profissional = registration
            profile.especialidade_id = specialty_id
            profile.autorizado_triagem = role == "enfermagem"
    elif profile:
        profile.ativo = False
    previous_role = canonical_role(user.perfil)
    user.perfil = role
    user.ultima_alteracao_por = actor.id
    if previous_role != role:
        user.token_version += 1
    audit(db, actor, "usuario_alterado", "usuario", user.id,
          {"perfil_anterior": previous_role, "perfil_novo": role})
    try:
        db.commit(); db.refresh(user)
    except IntegrityError:
        db.rollback(); raise HTTPException(409, "E-mail ou registro profissional já cadastrado")
    return internal_response(db, user)


def change_active(user_id: int, active: bool, actor: User, db: Session):
    user = db.get(User, user_id)
    if not user or user.perfil == "paciente":
        raise HTTPException(404, "Usuário interno não encontrado")
    if not active and user.perfil == "admin":
        active_admins = db.scalar(select(func.count(User.id)).where(User.perfil == "admin", User.ativo.is_(True)))
        if active_admins <= 1:
            raise HTTPException(409, "O último administrador ativo não pode ser desativado")
    if not active and user.id == actor.id:
        raise HTTPException(409, "Você não pode desativar a própria conta")
    user.ativo = active
    user.token_version += 1
    user.ultima_alteracao_por = actor.id
    profile = db.scalar(select(ProfessionalProfile).where(ProfessionalProfile.usuario_id == user.id))
    if profile: profile.ativo = active
    audit(db, actor, "usuario_ativado" if active else "usuario_desativado", "usuario", user.id,
          {"ativo": active})
    db.commit()
    return internal_response(db, user)


@router.post("/users/{user_id}/activate", response_model=InternalUserResponse)
def activate_user(user_id: int, actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    return change_active(user_id, True, actor, db)


@router.post("/users/{user_id}/deactivate", response_model=InternalUserResponse)
def deactivate_user(user_id: int, actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    return change_active(user_id, False, actor, db)


@router.post("/users/{user_id}/reset-access", status_code=204)
def reset_access(user_id: int, payload: AccessReset, actor: User = Depends(require_roles("admin")),
                 db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if not user or user.perfil == "paciente": raise HTTPException(404, "Usuário interno não encontrado")
    validate_identity(user.nome, user.cpf, payload.password)
    if payload.password != payload.password_confirmation:
        raise HTTPException(422, {"field": "password_confirmation", "message": "As senhas não coincidem."})
    user.senha_hash = pwd.hash(payload.password); user.token_version += 1
    user.ultima_alteracao_por = actor.id
    audit(db, actor, "acesso_redefinido", "usuario", user.id)
    db.commit()


@router.get("/summary")
def summary(day: date = Query(default_factory=clock.today_sao_paulo), actor: User = Depends(require_roles("admin")),
            db: Session = Depends(get_db)):
    mark_overdue_absences(db, actor)
    start, end = datetime.combine(day, time.min), datetime.combine(day + timedelta(days=1), time.min)
    rows = db.execute(select(Appointment.status, func.count(Appointment.id)).where(
        Appointment.data_horario >= start, Appointment.data_horario < end).group_by(Appointment.status)).all()
    counts = dict(rows)
    available = db.scalar(select(func.count(ProfessionalSchedule.id)).where(
        ProfessionalSchedule.data_horario >= start,
        ProfessionalSchedule.data_horario < end,
        ProfessionalSchedule.bloqueado.is_(False),
        ~select(Appointment.id).where(
            Appointment.medico_id == ProfessionalSchedule.medico_id,
            Appointment.data_horario == ProfessionalSchedule.data_horario,
            Appointment.status != "cancelado",
        ).exists(),
    )) or 0
    return {"scheduled": counts.get("agendado", 0), "checked_in": counts.get("em_espera", 0),
            "waiting": counts.get("em_espera", 0) + counts.get("em_triagem", 0),
            "in_care": counts.get("em_atendimento", 0), "completed": counts.get("concluido", 0),
            "cancelled": counts.get("cancelado", 0), "available": available,
            "absent": counts.get("falta", 0)}


@router.get("/schedule-professionals", response_model=list[CatalogItem])
def schedule_professionals(
    actor: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    rows = db.scalars(
        select(User).where(
            User.ativo.is_(True),
            User.perfil.in_(["medico", "profissional", "enfermagem"]),
        ).order_by(User.nome)
    )
    return [{"id": row.id, "name": row.nome} for row in rows]


@router.get(
    "/appointments",
    summary="Listar agenda administrativa",
    description=(
        "Perfis autorizados: Administrador, Recepção e Profissional de atendimento. "
        "O profissional visualiza somente consultas atribuídas a ele."
    ),
    responses={
        401: {"description": "Token ausente ou inválido."},
        403: {"description": "Perfil sem acesso ou consulta de outro profissional."},
        422: {"description": "Data, status ou classificação de risco inválida."},
    },
)
def agenda(day: date = Query(default_factory=clock.today_sao_paulo), specialty: str | None = None,
           professional_id: int | None = None, status: str | None = None,
           risk: str | None = None, patient: str | None = None,
           actor: User = Depends(require_roles("admin", "recepcao", "profissional")), db: Session = Depends(get_db)):
    mark_overdue_absences(db, actor)
    specialty = specialty.strip() if specialty else None
    status = status.strip() if status else None
    risk = risk.strip() if risk else None
    patient = patient.strip() if patient else None
    if status and status not in APPOINTMENT_STATUSES:
        raise HTTPException(422, "Status de consulta inválido")
    if risk and risk not in RISK_LEVELS:
        raise HTTPException(422, "Classificação de risco inválida")
    start, end = datetime.combine(day, time.min), datetime.combine(day + timedelta(days=1), time.min)
    query = select(Appointment).where(Appointment.data_horario >= start, Appointment.data_horario < end)
    if canonical_role(actor.perfil) == "profissional": query = query.where(Appointment.medico_id == actor.id)
    if specialty: query = query.where(
        func.lower(func.trim(Appointment.especialidade))
        == canonical_specialty_name(specialty).lower()
    )
    if professional_id: query = query.where(Appointment.medico_id == professional_id)
    if status: query = query.where(Appointment.status == status)
    if risk: query = query.where(Appointment.classificacao_risco == risk)
    if patient:
        term = patient.lower()
        cpf = "".join(c for c in term if c.isdigit())
        if len(term) == 5 and term[2] == ":" and term.replace(":", "").isdigit():
            query = query.where(func.strftime("%H:%M", Appointment.data_horario) == term)
        else:
            query = query.join(Appointment.paciente).where(or_(
                func.lower(User.nome).contains(term),
                User.cpf.contains(cpf) if cpf else False,
            ))
    return [{"id": x.id, "scheduled_at": x.data_horario, "patient": x.paciente.nome,
             "patient_document": mask_cpf(x.paciente.cpf), "specialty": canonical_specialty_name(x.especialidade),
             "professional": x.medico.nome, "professional_id": x.medico_id, "status": x.status,
             "legal_priority": legal_priority_code(x.paciente), "risk_classification": x.classificacao_risco,
             "arrived_at": x.chegada_em} for x in db.scalars(query.order_by(Appointment.data_horario)).unique()]


@router.post("/appointments/{appointment_id}/absence")
def register_absence(appointment_id: int, actor: User = Depends(require_roles("admin", "recepcao")),
                     db: Session = Depends(get_db)):
    row = db.get(Appointment, appointment_id)
    if not row: raise HTTPException(404, "Agendamento não encontrado")
    register_manual_absence(db, row, actor)
    return {"id": row.id, "status": row.status}


@router.get("/appointments/{appointment_id}")
def appointment_details(appointment_id: int,
                        actor: User = Depends(require_roles("admin", "recepcao", "profissional")),
                        db: Session = Depends(get_db)):
    row = db.get(Appointment, appointment_id)
    if not row: raise HTTPException(404, "Agendamento não encontrado")
    if canonical_role(actor.perfil) == "profissional" and row.medico_id != actor.id:
        raise HTTPException(403, "Acesso permitido apenas às consultas atribuídas")
    return {"id": row.id, "scheduled_at": row.data_horario, "patient": row.paciente.nome,
            "patient_document": mask_cpf(row.paciente.cpf), "specialty": canonical_specialty_name(row.especialidade),
            "professional": row.medico.nome, "status": row.status,
            "legal_priority": legal_priority_code(row.paciente),
            "priority_reason": legal_priority_label(row.paciente),
            "priority_conditions": [{
                "condition": item.condicao,
                "status": item.status,
                "validated_by": item.responsavel_validacao.nome if item.responsavel_validacao else None,
                "validated_at": item.validada_em,
            } for item in row.paciente.condicoes_prioritarias
              if item.status != "retirada"],
            "risk_classification": row.classificacao_risco, "arrived_at": row.chegada_em}


def _history_date_bounds(
    date_from: date | None,
    date_to: date | None,
) -> tuple[datetime | None, datetime | None, datetime | None, datetime | None]:
    if date_from and date_to and date_from > date_to:
        raise HTTPException(422, "A data inicial não pode ser posterior à data final")
    local_start = datetime.combine(date_from, time.min) if date_from else None
    local_end = (
        datetime.combine(date_to + timedelta(days=1), time.min) if date_to else None
    )
    utc_start = (
        local_start.replace(tzinfo=clock.SAO_PAULO)
        .astimezone(clock.UTC)
        .replace(tzinfo=None)
        if local_start
        else None
    )
    utc_end = (
        local_end.replace(tzinfo=clock.SAO_PAULO)
        .astimezone(clock.UTC)
        .replace(tzinfo=None)
        if local_end
        else None
    )
    return local_start, local_end, utc_start, utc_end


@router.get(
    "/audit",
    summary="Consultar auditoria administrativa",
    description=(
        "Perfil autorizado: Administrador. Permite combinar paciente, profissional, "
        "intervalo de datas e tipo de ação, com paginação limitada."
    ),
    responses={
        401: {"description": "Token ausente ou inválido."},
        403: {"description": "Acesso exclusivo do Administrador."},
        422: {"description": "Filtro ou intervalo de datas inválido."},
    },
)
def audit_history(
    patient: str | None = Query(None, max_length=120),
    professional: str | None = Query(None, max_length=120),
    date_from: date | None = None,
    date_to: date | None = None,
    action: str | None = Query(None, max_length=80),
    offset: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    actor: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    del actor
    _local_start, _local_end, utc_start, utc_end = _history_date_bounds(
        date_from, date_to
    )
    audit_actor = aliased(User)
    appointment = aliased(Appointment)
    appointment_patient = aliased(User)
    appointment_professional = aliased(User)
    condition = aliased(PriorityCondition)
    condition_patient = aliased(User)
    target_user = aliased(User)
    query = (
        select(
            AuditLog,
            audit_actor,
            appointment_patient,
            appointment_professional,
            condition_patient,
        )
        .join(audit_actor, audit_actor.id == AuditLog.usuario_id)
        .outerjoin(
            appointment,
            and_(
                AuditLog.tipo_registro == "consulta",
                appointment.id == AuditLog.registro_id,
            ),
        )
        .outerjoin(appointment_patient, appointment_patient.id == appointment.paciente_id)
        .outerjoin(
            appointment_professional,
            appointment_professional.id == appointment.medico_id,
        )
        .outerjoin(
            condition,
            and_(
                AuditLog.tipo_registro == "condicao_prioritaria",
                condition.id == AuditLog.registro_id,
            ),
        )
        .outerjoin(condition_patient, condition_patient.id == condition.paciente_id)
        .outerjoin(
            target_user,
            and_(
                AuditLog.tipo_registro == "usuario",
                target_user.id == AuditLog.registro_id,
            ),
        )
    )
    patient_term = patient.strip().lower() if patient else None
    if patient_term:
        pattern = f"%{patient_term}%"
        query = query.where(or_(
            func.lower(appointment_patient.nome).like(pattern),
            func.lower(condition_patient.nome).like(pattern),
            and_(
                target_user.perfil == "paciente",
                func.lower(target_user.nome).like(pattern),
            ),
        ))
    professional_term = professional.strip().lower() if professional else None
    if professional_term:
        pattern = f"%{professional_term}%"
        query = query.where(or_(
            func.lower(audit_actor.nome).like(pattern),
            func.lower(appointment_professional.nome).like(pattern),
        ))
    if action and action.strip():
        query = query.where(AuditLog.acao == action.strip())
    if utc_start:
        query = query.where(AuditLog.criado_em >= utc_start)
    if utc_end:
        query = query.where(AuditLog.criado_em < utc_end)
    rows = db.execute(
        query.order_by(AuditLog.criado_em.desc(), AuditLog.id.desc())
        .offset(offset)
        .limit(limit)
    ).all()
    return [{
        "id": row.id,
        "actor": who.nome if who else "Usuário removido",
        "action": row.acao,
        "record_type": row.tipo_registro,
        "record_id": row.registro_id,
        "patient": (appointment_patient_row or condition_patient_row).nome
        if (appointment_patient_row or condition_patient_row)
        else None,
        "professional": appointment_professional_row.nome
        if appointment_professional_row
        else None,
        "details": json.loads(row.detalhes) if row.detalhes else None,
        "created_at": clock.utc_naive_to_sao_paulo_naive(row.criado_em),
    } for (
        row,
        who,
        appointment_patient_row,
        appointment_professional_row,
        condition_patient_row,
    ) in rows]


@router.get(
    "/priority-validations",
    summary="Consultar histórico de condições prioritárias",
    description=(
        "Perfil autorizado: Administrador. Permite combinar paciente, responsável "
        "pela validação, intervalo de datas e status."
    ),
    responses={
        401: {"description": "Token ausente ou inválido."},
        403: {"description": "Acesso exclusivo do Administrador."},
        422: {"description": "Filtro ou intervalo de datas inválido."},
    },
)
def priority_validations(
    patient: str | None = Query(None, max_length=120),
    professional: str | None = Query(None, max_length=120),
    date_from: date | None = None,
    date_to: date | None = None,
    status: Literal["pendente", "confirmada", "rejeitada", "retirada"] | None = None,
    offset: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    actor: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    del actor
    local_start, local_end, utc_start, utc_end = _history_date_bounds(
        date_from, date_to
    )
    patient_user = aliased(User)
    validator = aliased(User)
    query = (
        select(PriorityCondition, patient_user, validator)
        .join(patient_user, patient_user.id == PriorityCondition.paciente_id)
        .outerjoin(validator, validator.id == PriorityCondition.validada_por)
    )
    if patient and patient.strip():
        query = query.where(
            func.lower(patient_user.nome).like(f"%{patient.strip().lower()}%")
        )
    if professional and professional.strip():
        query = query.where(
            func.lower(validator.nome).like(f"%{professional.strip().lower()}%")
        )
    if status:
        query = query.where(PriorityCondition.status == status)
    if local_start and utc_start:
        query = query.where(or_(
            PriorityCondition.validada_em >= local_start,
            and_(
                PriorityCondition.validada_em.is_(None),
                PriorityCondition.informada_em >= utc_start,
            ),
        ))
    if local_end and utc_end:
        query = query.where(or_(
            PriorityCondition.validada_em < local_end,
            and_(
                PriorityCondition.validada_em.is_(None),
                PriorityCondition.informada_em < utc_end,
            ),
        ))
    rows = db.execute(
        query.order_by(PriorityCondition.informada_em.desc(), PriorityCondition.id.desc())
        .offset(offset)
        .limit(limit)
    ).all()
    ids = [item.id for item, _patient, _validator in rows]
    history_by_condition: dict[int, list[dict]] = {item_id: [] for item_id in ids}
    if ids:
        history_actor = aliased(User)
        history_rows = db.execute(
            select(PriorityConditionHistory, history_actor)
            .outerjoin(history_actor, history_actor.id == PriorityConditionHistory.alterado_por)
            .where(PriorityConditionHistory.condicao_prioritaria_id.in_(ids))
            .order_by(PriorityConditionHistory.criado_em)
        ).all()
        for event, event_actor in history_rows:
            history_by_condition[event.condicao_prioritaria_id].append({
                "previous_status": event.status_anterior,
                "new_status": event.status_novo,
                "actor": event_actor.nome if event_actor else "Usuário removido",
                "created_at": event.criado_em,
            })
    return [
        {
            "id": item.id,
            "patient": patient_row.nome,
            "condition": item.condicao,
            "status": item.status,
            "reported_at": item.informada_em,
            "validated_by": validator_row.nome if validator_row else None,
            "validated_at": item.validada_em,
            "history": history_by_condition[item.id],
        }
        for item, patient_row, validator_row in rows
    ]


class SpecialtyInput(BaseModel):
    name: str


def normalized_specialty_name(value: str) -> str:
    name = canonical_specialty_name(value)
    if not name:
        raise HTTPException(
            422,
            {"field": "name", "message": "Informe o nome da especialidade."},
        )
    if len(name) > 80:
        raise HTTPException(
            422,
            {
                "field": "name",
                "message": "O nome da especialidade deve ter no máximo 80 caracteres.",
            },
        )
    return name


def specialty_name_exists(db: Session, name: str, *, except_id: int | None = None) -> bool:
    normalized = specialty_key(name)
    return any(
        specialty_key(row.nome) == normalized
        for row in db.scalars(select(Specialty))
        if row.id != except_id
    )


@router.get("/specialties")
def list_specialties(actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    return [{"id": row.id, "name": canonical_specialty_name(row.nome), "active": row.ativo}
            for row in db.scalars(select(Specialty).order_by(Specialty.nome))]


class AdminCreate(BaseModel):
    name: str = Field(min_length=3, max_length=80)
    cpf: str = Field(min_length=11, max_length=32)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    password_confirmation: str = Field(min_length=8, max_length=128)


@router.post("/admins", response_model=InternalUserResponse, status_code=201)
def create_admin(payload: AdminCreate, actor: User = Depends(require_roles("admin")),
                 db: Session = Depends(get_db)):
    cpf = validate_identity(payload.name, payload.cpf, payload.password)
    if payload.password != payload.password_confirmation:
        raise HTTPException(422, {"field": "password_confirmation", "message": "As senhas não coincidem."})
    email = str(payload.email).strip().lower()
    if db.scalar(select(User.id).where(or_(User.cpf == cpf, func.lower(User.email) == email))):
        raise HTTPException(409, "CPF ou e-mail já cadastrado")
    user = User(nome=payload.name.strip(), cpf=cpf, email=email, senha_hash=pwd.hash(payload.password),
                perfil="admin", ativo=True, email_verificado=True,
                criado_por=actor.id, ultima_alteracao_por=actor.id)
    try:
        db.add(user); db.flush()
        audit(db, actor, "administrador_criado", "usuario", user.id, {"perfil": "admin"})
        db.commit(); db.refresh(user)
    except IntegrityError:
        db.rollback(); raise HTTPException(409, "CPF ou e-mail já cadastrado")
    return internal_response(db, user)


@router.post("/specialties", status_code=201)
def create_specialty(payload: SpecialtyInput, actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    name = normalized_specialty_name(payload.name)
    if specialty_name_exists(db, name):
        raise HTTPException(409, "Especialidade já cadastrada")
    row = Specialty(nome=name, ativo=True)
    try:
        db.add(row); db.flush()
        audit(db, actor, "especialidade_criada", "especialidade", row.id, {"nome": name})
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Especialidade já cadastrada")
    return {"id": row.id, "name": canonical_specialty_name(row.nome), "active": row.ativo}


@router.put("/specialties/{specialty_id}")
def update_specialty(specialty_id: int, payload: SpecialtyInput,
                     actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    row = db.get(Specialty, specialty_id)
    if not row: raise HTTPException(404, "Especialidade não encontrada")
    name = normalized_specialty_name(payload.name)
    if specialty_name_exists(db, name, except_id=row.id):
        raise HTTPException(409, "Especialidade já cadastrada")
    old = row.nome
    row.nome = name
    # Grades e perfis mantêm o vínculo pelo id. Horários e consultas armazenam
    # o nome para preservar o histórico, portanto precisam acompanhar a edição.
    for schedule in db.scalars(select(ProfessionalSchedule).where(
            func.lower(func.trim(ProfessionalSchedule.especialidade)) == old.strip().lower())):
        schedule.especialidade = name
    for appointment in db.scalars(select(Appointment).where(
            func.lower(func.trim(Appointment.especialidade)) == old.strip().lower())):
        appointment.especialidade = name
    audit(db, actor, "especialidade_alterada", "especialidade", row.id,
          {"nome_anterior": old, "nome_novo": name})
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Especialidade já cadastrada")
    return {"id": row.id, "name": canonical_specialty_name(row.nome), "active": row.ativo}


@router.post("/specialties/{specialty_id}/{action}")
def set_specialty_active(specialty_id: int, action: Literal["activate", "deactivate"],
                         actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    row = db.get(Specialty, specialty_id)
    if not row: raise HTTPException(404, "Especialidade não encontrada")
    row.ativo = action == "activate"
    audit(db, actor, "especialidade_ativada" if row.ativo else "especialidade_desativada",
          "especialidade", row.id, {"ativo": row.ativo})
    db.commit()
    return {"id": row.id, "name": canonical_specialty_name(row.nome), "active": row.ativo}


class GridInput(BaseModel):
    professional_id: int
    specialty_id: int
    day: date
    start_time: time
    end_time: time
    duration_minutes: int = Field(gt=0, le=480)
    capacity: int = Field(ge=1, le=20)
    break_start: time | None = None
    break_end: time | None = None


def build_slots(payload: GridInput):
    if payload.day < clock.today_sao_paulo(): raise HTTPException(422, "Não é permitido cadastrar grade em data passada")
    if payload.day.weekday() >= 5: raise HTTPException(422, "Atendimento permitido somente de segunda a sexta")
    if is_holiday(payload.day): raise HTTPException(422, "Não é permitido cadastrar grade em feriado nacional")
    if payload.duration_minutes != 60: raise HTTPException(422, "Cada consulta deve durar exatamente 60 minutos")
    if payload.capacity != 1: raise HTTPException(422, "Cada profissional possui uma vaga por horário")
    start = datetime.combine(payload.day, payload.start_time); end = datetime.combine(payload.day, payload.end_time)
    if end <= start: raise HTTPException(422, "O horário final deve ser posterior ao inicial")
    if (payload.break_start is None) != (payload.break_end is None): raise HTTPException(422, "Informe o início e o fim do intervalo")
    break_start = datetime.combine(payload.day, payload.break_start) if payload.break_start else None
    break_end = datetime.combine(payload.day, payload.break_end) if payload.break_end else None
    if break_start and (break_end <= break_start or break_start < start or break_end > end):
        raise HTTPException(422, "Intervalo fora dos limites da grade")
    slots, cursor = [], start
    allowed = {time(hour, 0) for hour in (7, 8, 9, 10, 11, 13, 14, 15, 16, 17)}
    while cursor + timedelta(minutes=payload.duration_minutes) <= end:
        slot_end = cursor + timedelta(minutes=payload.duration_minutes)
        in_break = break_start and not (slot_end <= break_start or cursor >= break_end)
        if not in_break:
            if cursor.time() not in allowed:
                raise HTTPException(422, "Use somente os horários permitidos entre 07:00 e 17:00, exceto 12:00")
            slots.append(cursor)
        cursor = slot_end
    if not slots: raise HTTPException(422, "A grade deve gerar pelo menos um horário válido")
    return start, end, slots


def easter_sunday(year: int) -> date:
    a, b, c = year % 19, year // 100, year % 100
    d, e, f = b // 4, b % 4, (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    return date(year, month, (h + l - 7 * m + 114) % 31 + 1)


def is_holiday(day: date) -> bool:
    fixed = {(1, 1), (4, 21), (5, 1), (9, 7), (10, 12), (11, 2),
             (11, 15), (11, 20), (12, 25)}
    easter = easter_sunday(day.year)
    return (day.month, day.day) in fixed or day in {easter - timedelta(days=2), easter + timedelta(days=60)}


@router.get("/grids")
def list_grids(actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    return [{"id": x.id, "professional_id": x.profissional_id, "professional": x.profissional.nome,
             "specialty_id": x.especialidade_id, "specialty": canonical_specialty_name(x.especialidade.nome),
             "day": x.data.date(), "start_time": x.horario_inicio, "end_time": x.horario_fim,
             "duration_minutes": x.duracao_minutos, "capacity": x.quantidade_vagas,
             "break_start": x.intervalo_inicio, "break_end": x.intervalo_fim, "active": x.ativo}
            for x in db.scalars(select(ScheduleGrid).order_by(ScheduleGrid.data.desc())).unique()]


@router.post("/grids", status_code=201)
def create_grid(payload: GridInput, actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    start, end, slots = build_slots(payload)
    professional = db.get(User, payload.professional_id); specialty = db.get(Specialty, payload.specialty_id)
    if (
        not professional
        or not professional.ativo
        or (
            canonical_role(professional.perfil) != "medico"
            and professional.perfil != "enfermagem"
        )
    ):
        raise HTTPException(422, "Profissional inválido")
    if not specialty or not specialty.ativo: raise HTTPException(422, "Especialidade inválida")
    profile = db.scalar(select(ProfessionalProfile).where(
        ProfessionalProfile.usuario_id == professional.id,
        ProfessionalProfile.especialidade_id == specialty.id,
        ProfessionalProfile.ativo.is_(True),
    ))
    if not profile:
        raise HTTPException(422, "Profissional não está vinculado à especialidade")
    overlap = db.scalar(select(ScheduleGrid.id).where(ScheduleGrid.profissional_id == professional.id,
        ScheduleGrid.ativo.is_(True), ScheduleGrid.data == datetime.combine(payload.day, time.min),
        ScheduleGrid.horario_inicio < payload.end_time.strftime("%H:%M"),
        ScheduleGrid.horario_fim > payload.start_time.strftime("%H:%M")))
    if overlap: raise HTTPException(409, "A grade se sobrepõe a outro período do profissional")
    grid = ScheduleGrid(profissional_id=professional.id, especialidade_id=specialty.id,
        data=datetime.combine(payload.day, time.min), horario_inicio=payload.start_time.strftime("%H:%M"),
        horario_fim=payload.end_time.strftime("%H:%M"), duracao_minutos=payload.duration_minutes,
        quantidade_vagas=payload.capacity, intervalo_inicio=payload.break_start.strftime("%H:%M") if payload.break_start else None,
        intervalo_fim=payload.break_end.strftime("%H:%M") if payload.break_end else None, criado_por=actor.id)
    db.add(grid); db.flush()
    for at in slots:
        for _ in range(payload.capacity):
            if not db.scalar(select(ProfessionalSchedule.id).where(ProfessionalSchedule.medico_id == professional.id,
                    ProfessionalSchedule.data_horario == at)):
                db.add(ProfessionalSchedule(medico_id=professional.id, especialidade=specialty.nome,
                                            data_horario=at, bloqueado=False))
                break
    audit(db, actor, "grade_criada", "grade", grid.id, {"data": payload.day.isoformat(), "vagas": len(slots)})
    db.commit()
    return {"id": grid.id, "slots": len(slots)}


@router.delete("/grids/{grid_id}", status_code=204)
def remove_grid(grid_id: int, actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    grid = db.get(ScheduleGrid, grid_id)
    if not grid: raise HTTPException(404, "Grade não encontrada")
    day_start = grid.data
    day_end = day_start + timedelta(days=1)
    occupied = db.scalar(select(Appointment.id).where(
        Appointment.medico_id == grid.profissional_id,
        Appointment.data_horario >= day_start,
        Appointment.data_horario < day_end,
        Appointment.status != "cancelado",
    ))
    if occupied: raise HTTPException(409, "A grade possui consultas vinculadas; desative o profissional ou preserve os horários")
    grid.ativo = False
    for slot in db.scalars(select(ProfessionalSchedule).where(
            ProfessionalSchedule.medico_id == grid.profissional_id,
            ProfessionalSchedule.data_horario >= day_start,
            ProfessionalSchedule.data_horario < day_end)):
        slot.bloqueado = True
    audit(db, actor, "grade_desativada", "grade", grid.id)
    db.commit()


class BlockInput(BaseModel):
    professional_id: int
    start: datetime
    end: datetime
    reason: Literal["intervalo", "folga", "indisponibilidade", "outro"]


@router.post("/blocks", status_code=201)
def block_period(payload: BlockInput, actor: User = Depends(require_roles("admin")), db: Session = Depends(get_db)):
    if payload.start.tzinfo or payload.end.tzinfo or payload.end <= payload.start or payload.start < clock.now_sao_paulo_naive():
        raise HTTPException(422, "Período de bloqueio inválido")
    professional = db.get(User, payload.professional_id)
    if (
        not professional
        or not professional.ativo
        or (
            canonical_role(professional.perfil) != "medico"
            and professional.perfil != "enfermagem"
        )
    ):
        raise HTTPException(422, "Profissional inválido")
    occupied = db.scalar(select(Appointment.id).where(Appointment.medico_id == payload.professional_id,
        Appointment.data_horario >= payload.start, Appointment.data_horario < payload.end,
        Appointment.status != "cancelado"))
    if occupied: raise HTTPException(409, "O período possui agendamento e não pode ser bloqueado")
    row = ScheduleBlock(profissional_id=payload.professional_id, inicio=payload.start, fim=payload.end,
                        motivo=payload.reason, criado_por=actor.id)
    db.add(row)
    for slot in db.scalars(select(ProfessionalSchedule).where(ProfessionalSchedule.medico_id == payload.professional_id,
            ProfessionalSchedule.data_horario >= payload.start, ProfessionalSchedule.data_horario < payload.end)):
        slot.bloqueado = True
    db.flush(); audit(db, actor, "periodo_bloqueado", "bloqueio", row.id, {"motivo": payload.reason}); db.commit()
    return {"id": row.id}
