"""API da UBS Rápida: autenticação, RBAC e agendamentos."""

from datetime import date, datetime, timedelta
from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path
import sqlite3
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, inspect, or_, select, text, update
from sqlalchemy.orm import Session
from app.core.database import Base, SessionLocal, engine, get_db
from app.core import clock
from app.core.risk import LEGACY_RISK_MAPPING, RISK_LEVELS
from app.core.specialty import GENERAL_SPECIALTY, canonical_specialty_name
from app.models import Appointment, ProfessionalSchedule, User
from app.schemas import (
    AppointmentCreate,
    AppointmentResponse,
    CalendarSlot,
    LoginRequest,
    PatientRegistration,
    PatientPriorityUpdate,
    RescheduleRequest,
    TokenResponse,
    UserResponse,
    RegistrationResponse,
    PatientProfile,
    PatientSummary,
)

from app.core.config import check_config, ORIGINS
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(_app: FastAPI):
    startup()
    yield


app = FastAPI(title="UBS Rápida API", version="2.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
from app.core.security import (
    pwd,
    current_user,
    require_roles,
    make_token,
    throttle,
    DUMMY_HASH,
    canonical_role,
    permissions_for,
)
from app.models import (
    Guardian, PatientGuardian, PriorityCondition, PriorityConditionHistory, Specialty,
)
from sqlalchemy.exc import IntegrityError
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


@app.exception_handler(RequestValidationError)
async def validation_error(request, exc):
    # Não devolver valores de entrada (especialmente senhas) em respostas de erro.
    if any(e["loc"][-1] == "guardian_email" for e in exc.errors()):
        return JSONResponse(
            status_code=422,
            content={
                "detail": {
                    "field": "guardian_email",
                    "message": "Informe o e-mail válido do responsável legal.",
                }
            },
        )
    errors = [
        {"loc": e["loc"], "msg": "Confira o campo informado", "type": e["type"]}
        for e in exc.errors()
    ]
    return JSONResponse(status_code=422, content={"detail": errors})


@app.exception_handler(IntegrityError)
async def integrity_error(request, exc):
    return JSONResponse(
        status_code=409,
        content={
            "detail": "Registro duplicado ou conflito de atualização. Confira os dados."
        },
    )


PRIORITIES, STAFF = {"geral", "idoso_60+", "pcd", "gestante", "lactante"}, {
    "recepcao",
    "enfermagem",
    "medico",
    "admin",
}


def digits(value: str) -> str:
    return "".join(char for char in value if char.isdigit())


def valid_cpf(value: str) -> bool:
    cpf = digits(value)
    if not cpf.isascii() or len(cpf) != 11 or len(set(cpf)) == 1:
        return False
    for pos in (9, 10):
        if (
            (sum(int(cpf[i]) * (pos + 1 - i) for i in range(pos)) * 10) % 11
        ) % 10 != int(cpf[pos]):
            return False
    return True


def is_minor(birth_date: date) -> bool:
    from app.services.appointments import full_age
    return full_age(birth_date) < 18


def valid_password(value: str) -> bool:
    return (
        8 <= len(value) <= 32
        and len(value.encode()) <= 72
        and any(c.isupper() for c in value)
        and any(c.islower() for c in value)
        and any(c.isdigit() for c in value)
        and any(not c.isalnum() for c in value)
    )


def valid_name(value: str) -> bool:
    import re

    return (
        bool(re.fullmatch(r"[^\W\d_]+(?:[- ][^\W\d_]+)+", value.strip()))
        and 3 <= len(value.strip()) <= 80
    )


def as_user(user: User) -> UserResponse:
    return UserResponse(id=user.id, name=user.nome, role=canonical_role(user.perfil), permissions=permissions_for(user))


def as_appointment(item: Appointment, include_risk: bool = False) -> AppointmentResponse:
    return AppointmentResponse(
        id=item.id,
        specialty=canonical_specialty_name(item.especialidade),
        professional=item.medico.nome,
        doctor_id=item.medico_id,
        scheduled_at=item.data_horario,
        status=item.status,
        risk_classification=item.classificacao_risco if include_risk else None,
    )


def as_patient(user: User) -> PatientProfile:
    from app.services.appointments import full_age, legal_priority_code, legal_priority_label

    cpf = user.cpf or ""
    return PatientProfile(
        name=user.nome,
        masked_cpf=f"***.***.***-{cpf[-2:]}" if len(cpf) == 11 else "***",
        cns=user.cns,
        birth_date=user.data_nascimento.date() if user.data_nascimento else None,
        email=user.email,
        phone=user.telefone,
        age=full_age(user.data_nascimento) if user.data_nascimento else None,
        legal_priority=legal_priority_code(user),
        priority_reason=legal_priority_label(user),
        priority_conditions=[
            {
                "condition": item.condicao,
                "status": item.status,
                "reported_at": item.informada_em,
                "validated_at": item.validada_em,
                "validated_by": (
                    item.responsavel_validacao.nome if item.responsavel_validacao else None
                ),
            }
            for item in sorted(user.condicoes_prioritarias, key=lambda value: value.condicao)
            if item.status != "retirada"
        ],
    )


def protected_name(value: str) -> str:
    parts = value.split()
    return parts[0] + (f" {parts[-1][0]}." if len(parts) > 1 else "")


def _backup_before_priority_migration() -> Path | None:
    """Cria uma única cópia consistente antes da migração aditiva de prioridade."""
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    if "usuarios" not in tables or "condicoes_prioritarias" in tables:
        return None
    database = engine.url.database
    if engine.url.get_backend_name() != "sqlite" or not database or database == ":memory:":
        return None
    source = Path(database).resolve()
    if not source.exists():
        return None
    backup_dir = source.parent / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    destination = backup_dir / f"{source.stem}.pre-priority-validation.bak"
    if destination.exists():
        return destination
    with sqlite3.connect(source) as source_db, sqlite3.connect(destination) as backup_db:
        source_db.backup(backup_db)
    return destination


def _backup_before_risk_migration() -> Path | None:
    """Cria uma única cópia do SQLite antes de converter a escala de risco."""
    if engine.url.get_backend_name() != "sqlite" or engine.url.database in {None, ":memory:"}:
        return None
    source = Path(engine.url.database).resolve()
    if not source.exists():
        return None
    backup_dir = source.parent / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    destination = backup_dir / f"{source.stem}.pre-risk-scale.bak"
    if not destination.exists():
        with sqlite3.connect(source) as source_db, sqlite3.connect(destination) as backup_db:
            source_db.backup(backup_db)
    return destination


def migrate_risk_scale() -> int:
    """Converte códigos antigos de risco de forma idempotente e auditável."""
    tables = set(inspect(engine).get_table_names())
    targets = [
        ("consultas", "classificacao_risco"),
        ("classificacoes_risco", "nivel_risco"),
    ]
    present = [(table, column) for table, column in targets if table in tables]
    if not present:
        return 0
    legacy_values = tuple(LEGACY_RISK_MAPPING)
    placeholders = ", ".join(f":legacy_{index}" for index in range(len(legacy_values)))
    parameters = {f"legacy_{index}": value for index, value in enumerate(legacy_values)}
    with engine.connect() as connection:
        has_legacy = any(
            connection.execute(
                text(
                    f"SELECT 1 FROM {table} WHERE lower({column}) IN ({placeholders}) LIMIT 1"
                ),
                parameters,
            ).first()
            for table, column in present
        )
    if not has_legacy:
        logger.info("risk_scale_migration updated_records=0")
        return 0
    backup = _backup_before_risk_migration()
    updated = 0
    with engine.begin() as connection:
        for table, column in present:
            for legacy, official in LEGACY_RISK_MAPPING.items():
                result = connection.execute(
                    text(
                        f"UPDATE {table} SET {column} = :official "
                        f"WHERE lower({column}) = :legacy"
                    ),
                    {"official": official, "legacy": legacy},
                )
                updated += result.rowcount
    logger.info(
        "risk_scale_migration updated_records=%s backup=%s", updated, backup
    )
    return updated


def migrate_database() -> None:
    from app.core.demo_accounts import DEMO_ACCOUNTS

    canonical_demo_cpfs = tuple(account.cpf for account in DEMO_ACCOUNTS)
    _backup_before_priority_migration()
    Base.metadata.create_all(engine)
    existing = {column["name"] for column in inspect(engine).get_columns("usuarios")}
    fields = {
        "ativo": "BOOLEAN DEFAULT 1",
        "token_version": "INTEGER DEFAULT 0",
        "criado_em": "DATETIME",
        "atualizado_em": "DATETIME",
        "data_nascimento": "DATETIME",
        "cns": "VARCHAR(15)",
        "telefone": "VARCHAR(11)",
        "e_menor_idade": "BOOLEAN DEFAULT 0",
        "nome_responsavel": "VARCHAR(120)",
        "cpf_responsavel": "VARCHAR(11)",
        "data_nascimento_responsavel": "DATETIME",
        "parentesco_responsavel": "VARCHAR(40)",
        "outro_parentesco_responsavel": "VARCHAR(80)",
        "telefone_responsavel": "VARCHAR(11)",
        "email_responsavel": "VARCHAR(120)",
        "email_verificado": "BOOLEAN DEFAULT 0",
        "criado_por": "INTEGER",
        "ultima_alteracao_por": "INTEGER",
    }
    email_verification_added = False
    with engine.begin() as connection:
        for name, definition in fields.items():
            if name not in existing:
                connection.execute(
                    text(f"ALTER TABLE usuarios ADD COLUMN {name} {definition}")
                )
                if name == "email_verificado":
                    email_verification_added = True
        if email_verification_added:
            # Toda conta anterior à funcionalidade é tratada como conta de
            # demonstração/legada e continua acessível após a migração.
            connection.execute(text("UPDATE usuarios SET email_verificado = 1"))
    verification_columns = {
        column["name"] for column in inspect(engine).get_columns("verificacoes_email")
    }
    if "token_correcao_hash" not in verification_columns:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "ALTER TABLE verificacoes_email "
                    "ADD COLUMN token_correcao_hash VARCHAR(64)"
                )
            )
    with engine.begin() as connection:
        for table, columns in {
            "consultas": {
                "chegada_em": "DATETIME",
                "chegada_por": "INTEGER",
                "falta_em": "DATETIME",
                "triagem_por": "INTEGER",
                "triagem_dados": "VARCHAR(2000)",
                "triagem_em": "DATETIME",
                "chamado_em": "DATETIME",
                "iniciado_em": "DATETIME",
                "concluido_em": "DATETIME",
                "atendimento_medico_id": "INTEGER",
                "resumo_atendimento": "TEXT",
            },
            "agendas_profissionais": {
                "especialidade": "VARCHAR(80) DEFAULT 'Clínica Geral'"
            },
        }.items():
            known = {c["name"] for c in inspect(engine).get_columns(table)}
            for name, definition in columns.items():
                if name not in known:
                    connection.execute(
                        text(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")
                    )
    with engine.begin() as connection:
        known = {c["name"] for c in inspect(engine).get_columns("responsaveis")}
        if "email" not in known:
            connection.execute(
                text("ALTER TABLE responsaveis ADD COLUMN email VARCHAR(120)")
            )
        specialty_columns = {c["name"] for c in inspect(engine).get_columns("especialidades")}
        if "ativo" not in specialty_columns:
            connection.execute(text("ALTER TABLE especialidades ADD COLUMN ativo BOOLEAN DEFAULT 1"))
        risk_columns = {
            c["name"] for c in inspect(engine).get_columns("classificacoes_risco")
        }
        for name, definition in {
            "queixa_principal": "VARCHAR(500)",
            "sinais_vitais": "VARCHAR(500)",
        }.items():
            if name not in risk_columns:
                connection.execute(
                    text(
                        f"ALTER TABLE classificacoes_risco "
                        f"ADD COLUMN {name} {definition}"
                    )
                )
        # A única vaga ativa por profissional/horário também fica protegida no SQLite.
        connection.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_consulta_vaga_ativa "
            "ON consultas(medico_id, data_horario) WHERE status != 'cancelado'"
        ))
        connection.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_consulta_paciente_status_data "
            "ON consultas(paciente_id, status, data_horario)"
        ))
        duplicate_active_care = connection.execute(text(
            "SELECT paciente_id FROM consultas WHERE status = 'em_atendimento' "
            "GROUP BY paciente_id HAVING COUNT(*) > 1 LIMIT 1"
        )).first()
        if not duplicate_active_care:
            connection.execute(text(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_paciente_em_atendimento "
                "ON consultas(paciente_id) WHERE status = 'em_atendimento'"
            ))
        connection.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_agenda_especialidade_data "
            "ON agendas_profissionais(especialidade, data_horario)"
        ))
    migrate_risk_scale()
    with SessionLocal() as db:
        from app.services.appointments import full_age

        db.execute(
            update(User)
            .where(
                User.perfil == "profissional",
                User.cpf.not_in(canonical_demo_cpfs),
            )
            .values(perfil="medico")
        )
        db.execute(
            update(User)
            .where(
                User.criado_em.is_(None),
                User.cpf.not_in(canonical_demo_cpfs),
            )
            .values(
                criado_em=clock.now_utc_naive(),
                atualizado_em=clock.now_utc_naive(),
            )
        )
        if not db.scalar(
            select(Specialty).where(
                func.lower(func.trim(Specialty.nome)) == GENERAL_SPECIALTY.lower()
            )
        ):
            db.add(Specialty(nome=GENERAL_SPECIALTY))
        for user in db.scalars(select(User).where(User.cpf_responsavel.is_not(None))):
            if not user.nome_responsavel:
                continue
            guardian = db.scalar(
                select(Guardian).where(Guardian.cpf == user.cpf_responsavel)
            )
            if not guardian:
                guardian = Guardian(
                    nome=user.nome_responsavel,
                    cpf=user.cpf_responsavel,
                    telefone=user.telefone_responsavel,
                    email=user.email_responsavel,
                )
                db.add(guardian)
                db.flush()
            if not guardian.email and user.email_responsavel:
                guardian.email = user.email_responsavel.strip().lower()
            if not db.get(PatientGuardian, (user.id, guardian.id)):
                db.add(
                    PatientGuardian(
                        paciente_id=user.id,
                        responsavel_id=guardian.id,
                        parentesco=user.parentesco_responsavel or "Responsável legal",
                    )
                )
        # O campo legado permanece apenas para compatibilidade. Idoso deriva
        # exclusivamente da data; condições antigas sem evidência viram pendentes.
        for user in db.scalars(
            select(User).where(
                User.perfil == "paciente",
                User.cpf.not_in(canonical_demo_cpfs),
            )
        ).unique():
            legacy = user.e_prioridade
            if legacy in {"pcd", "gestante", "lactante"}:
                condition = db.scalar(select(PriorityCondition).where(
                    PriorityCondition.paciente_id == user.id,
                    PriorityCondition.condicao == legacy,
                ))
                if not condition:
                    condition = PriorityCondition(
                        paciente_id=user.id, condicao=legacy, status="pendente"
                    )
                    db.add(condition)
                    db.flush()
                    db.add(PriorityConditionHistory(
                        condicao_prioritaria_id=condition.id,
                        status_anterior=None,
                        status_novo="pendente",
                        alterado_por=user.id,
                    ))
            user.e_prioridade = (
                "idoso_60+"
                if user.data_nascimento and full_age(user.data_nascimento) >= 60
                else "geral"
            )
        db.commit()


def seed(db: Session) -> None:
    from app.services.demo_seed import (
        ensure_canonical_demo_accounts,
        ensure_canonical_demo_schedules,
    )

    try:
        ensure_canonical_demo_accounts(db)
        ensure_canonical_demo_schedules(db)
        db.commit()
    except Exception:
        db.rollback()
        raise


GENERAL_HOURS = (7, 8, 9, 10, 11, 13, 14, 15, 16, 17)


def ensure_future_general_schedule(db: Session) -> int:
    """Completa, sem duplicar, os próximos 14 dias úteis da agenda do MVP."""
    from app.models import ProfessionalProfile, Specialty

    now = clock.now_sao_paulo_naive()
    specialty = db.scalar(
        select(Specialty).where(
            Specialty.ativo.is_(True),
            func.lower(func.trim(Specialty.nome)) == GENERAL_SPECIALTY.lower(),
        )
    )
    if not specialty:
        return 0
    doctor = db.scalar(
        select(User)
        .join(ProfessionalProfile, ProfessionalProfile.usuario_id == User.id)
        .where(
            User.perfil.in_(["profissional", "medico"]),
            User.ativo.is_(True),
            ProfessionalProfile.ativo.is_(True),
            ProfessionalProfile.especialidade_id == specialty.id,
        )
        .order_by(User.id)
    )
    if not doctor:
        return 0
    created = 0
    day = now.date() + timedelta(days=1)
    weekdays = 0
    end = day + timedelta(days=24)
    existing = {
        row.data_horario
        for row in db.scalars(
            select(ProfessionalSchedule).where(
                ProfessionalSchedule.medico_id == doctor.id,
                ProfessionalSchedule.data_horario >= datetime.combine(day, datetime.min.time()),
                ProfessionalSchedule.data_horario < datetime.combine(end, datetime.min.time()),
            )
        )
    }
    while weekdays < 14:
        if day.weekday() < 5:
            for hour in GENERAL_HOURS:
                at = datetime.combine(day, datetime.min.time()).replace(hour=hour)
                if at in existing:
                    continue
                db.add(
                    ProfessionalSchedule(
                        medico_id=doctor.id,
                        especialidade=GENERAL_SPECIALTY,
                        data_horario=at,
                    )
                )
                existing.add(at)
                created += 1
            weekdays += 1
        day += timedelta(days=1)
    db.commit()
    return created


def startup() -> None:
    check_config()
    demo_enabled = os.getenv("SEED_DEMO_DATA", "false").lower() == "true"
    if demo_enabled:
        from app.services.demo_seed import validate_canonical_demo_accounts

        tables = set(inspect(engine).get_table_names())
        if {"usuarios", "especialidades", "perfis_profissionais"} <= tables:
            with SessionLocal() as validation_db:
                validate_canonical_demo_accounts(validation_db)
    migrate_database()
    db = SessionLocal()
    try:
        if demo_enabled:
            seed(db)
        if os.getenv("SEED_FUTURE_SCHEDULE", "true").lower() == "true":
            ensure_future_general_schedule(db)
    finally:
        db.close()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)):
    document = digits(payload.document)
    throttle(db, request, "login", document)
    valid = valid_cpf(document)
    if any(c not in "0123456789.- " for c in payload.document):
        valid = False
    user = db.scalar(select(User).where(User.cpf == document)) if valid else None
    matches = pwd.verify(payload.password, user.senha_hash if user else DUMMY_HASH)
    if not user or not matches or not user.ativo:
        raise HTTPException(401, "CPF ou senha inválidos")
    if user.perfil == "paciente" and not user.email_verificado:
        raise HTTPException(403, "Confirme seu e-mail antes de entrar.")
    permissions = permissions_for(user)
    return TokenResponse(access_token=make_token(user), user=as_user(user), permissions=permissions)


@app.post("/auth/register", response_model=RegistrationResponse, status_code=201)
def register(
    payload: PatientRegistration, request: Request, db: Session = Depends(get_db)
):
    throttle(
        db, request, "register", request.client.host if request.client else "local", 20
    )
    db.execute(text("BEGIN IMMEDIATE"))
    cpf, phone = digits(payload.cpf), digits(payload.phone)
    minor, guardian_cpf = is_minor(payload.birth_date), digits(
        payload.guardian_cpf or ""
    )
    if not valid_name(payload.name):
        raise HTTPException(
            422,
            "Nome completo deve ter 3 a 80 caracteres e conter apenas letras e espaços",
        )
    if payload.birth_date > clock.today_sao_paulo() or payload.birth_date < date(1900, 1, 1):
        raise HTTPException(422, "Data de nascimento inválida")
    if any(c not in "0123456789.- " for c in payload.cpf) or not valid_cpf(cpf):
        raise HTTPException(422, "CPF inválido")
    if not valid_password(payload.password):
        raise HTTPException(
            422,
            "Senha deve ter 8 a 32 caracteres, maiúscula, minúscula, número e caractere especial",
        )
    if payload.password != payload.password_confirmation:
        raise HTTPException(
            422,
            {
                "field": "password_confirmation",
                "message": "As senhas não coincidem.",
            },
        )
    if any(c not in "0123456789 ()-" for c in payload.phone) or len(phone) not in {
        10,
        11,
    }:
        raise HTTPException(422, "Telefone deve ter DDD e 10 ou 11 dígitos")
    if payload.priority and payload.priority not in PRIORITIES:
        raise HTTPException(422, "Perfil prioritário inválido")
    if payload.priority == "idoso_60+":
        raise HTTPException(
            422,
            "A prioridade para pessoa idosa é calculada automaticamente pela data de nascimento.",
        )
    if (
        payload.guardian_birth_date
        and not date(1900, 1, 1) <= payload.guardian_birth_date <= clock.today_sao_paulo()
    ):
        raise HTTPException(422, "Data de nascimento do responsável inválida")
    if minor and any(c not in "0123456789 ()-" for c in (payload.guardian_phone or "")):
        raise HTTPException(422, "Telefone do responsável inválido")
    if minor:
        from app.core.identity import validate_guardian

        validate_guardian(payload)
    if db.scalar(select(User).where(User.cpf == cpf)):
        raise HTTPException(409, {"field": "cpf", "message": "CPF já cadastrado"})
    normalized_email = str(payload.email).lower()
    if db.scalar(select(User).where(func.lower(User.email) == normalized_email)):
        raise HTTPException(
            409, "CPF ou e-mail já cadastrado. Entre com sua conta ou use outros dados."
        )
    from app.services.appointments import full_age

    priority = "idoso_60+" if full_age(payload.birth_date) >= 60 else "geral"
    declared_conditions = set(payload.priority_conditions)
    if payload.priority in {"pcd", "gestante", "lactante"}:
        declared_conditions.add(payload.priority)
    user = User(
        nome=payload.name.strip(),
        cpf=cpf,
        data_nascimento=payload.birth_date,
        email=normalized_email,
        telefone=phone,
        senha_hash=pwd.hash(payload.password),
        perfil="paciente",
        email_verificado=False,
        e_prioridade=priority,
        e_menor_idade=minor,
        nome_responsavel=(
            payload.guardian_name.strip()
            if minor and payload.guardian_name
            else None
        ),
        cpf_responsavel=guardian_cpf if minor else None,
        data_nascimento_responsavel=(
            payload.guardian_birth_date if minor else None
        ),
        parentesco_responsavel=(
            payload.guardian_relationship if minor else None
        ),
        outro_parentesco_responsavel=(
            payload.guardian_other_relationship if minor else None
        ),
        telefone_responsavel=(
            (digits(payload.guardian_phone or "") or None) if minor else None
        ),
        email_responsavel=(
            str(payload.guardian_email).lower()
            if minor and payload.guardian_email
            else None
        ),
    )
    db.add(user)
    try:
        db.flush()
        for name in sorted(declared_conditions):
            condition = PriorityCondition(
                paciente_id=user.id, condicao=name, status="pendente"
            )
            db.add(condition)
            db.flush()
            db.add(PriorityConditionHistory(
                condicao_prioritaria_id=condition.id,
                status_anterior=None,
                status_novo="pendente",
                alterado_por=user.id,
            ))
        if minor:
            guardian = db.scalar(select(Guardian).where(Guardian.cpf == guardian_cpf))
            if not guardian:
                guardian = Guardian(
                    nome=payload.guardian_name.strip(),
                    cpf=guardian_cpf,
                    telefone=digits(payload.guardian_phone),
                    email=str(payload.guardian_email).lower(),
                )
                db.add(guardian)
                db.flush()
            elif guardian.email and guardian.email.strip().casefold() != str(
                payload.guardian_email
            ).strip().casefold():
                raise HTTPException(
                    422,
                    {
                        "field": "guardian_email",
                        "message": "Os dados do responsável não conferem.",
                    },
                )
            elif not guardian.email:
                guardian.email = str(payload.guardian_email).strip().lower()
            db.add(
                PatientGuardian(
                    paciente_id=user.id,
                    responsavel_id=guardian.id,
                    parentesco=payload.guardian_other_relationship
                    or payload.guardian_relationship,
                )
            )
        from app.routes.email_verification import (
            generate_correction_token,
            issue_verification_code,
        )

        verification_token = generate_correction_token()
        issue_verification_code(user, db, verification_token)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            409, "CPF ou e-mail já cadastrado. Entre com sua conta ou use outros dados."
        )
    except Exception as error:
        from app.services.mailer import MailUnavailable, delivery_error_message

        db.rollback()
        if isinstance(error, MailUnavailable):
            logger.warning(
                "registration_email_delivery status=failed reason=%s timestamp=%s",
                error.reason,
                clock.now_utc().isoformat(),
            )
            raise HTTPException(503, delivery_error_message(error.reason)) from None
        raise
    db.refresh(user)
    return RegistrationResponse(
        **as_user(user).model_dump(),
        email=user.email,
        verification_token=verification_token,
    )


@app.get("/auth/me", response_model=UserResponse)
def me(user: User = Depends(current_user)):
    return as_user(user)


@app.get("/patients/me", response_model=PatientProfile, response_model_exclude_none=True)
def patient_me(user: User = Depends(require_roles("paciente"))):
    return as_patient(user)


@app.patch(
    "/patients/me/priority-conditions",
    response_model=PatientProfile,
    response_model_exclude_none=True,
)
def update_patient_priority_conditions(
    payload: PatientPriorityUpdate,
    user: User = Depends(require_roles("paciente")),
    db: Session = Depends(get_db),
):
    if payload.priority == "idoso_60+":
        raise HTTPException(
            422,
            "A prioridade para pessoa idosa é calculada automaticamente pela data de nascimento.",
        )
    if payload.priority and payload.priority not in PRIORITIES:
        raise HTTPException(422, "Condição prioritária inválida")
    requested = set(payload.priority_conditions)
    if payload.priority in {"pcd", "gestante", "lactante"}:
        requested.add(payload.priority)
    from app.services.appointments import record_audit_event

    existing = {
        condition.condicao: condition
        for condition in db.scalars(select(PriorityCondition).where(
            PriorityCondition.paciente_id == user.id,
        ))
    }
    for name, condition in existing.items():
        if name not in requested and condition.status == "pendente":
            condition.status = "retirada"
            db.add(PriorityConditionHistory(
                condicao_prioritaria_id=condition.id,
                status_anterior="pendente",
                status_novo="retirada",
                alterado_por=user.id,
            ))
            record_audit_event(
                db,
                user,
                "condicao_prioritaria_retirada",
                "condicao_prioritaria",
                condition.id,
                {
                    "condicao": name,
                    "status_anterior": "pendente",
                    "status_novo": "retirada",
                },
            )
    for name in sorted(requested):
        condition = existing.get(name)
        previous = condition.status if condition else None
        if not condition:
            condition = PriorityCondition(
                paciente_id=user.id, condicao=name, status="pendente"
            )
            db.add(condition)
            db.flush()
        elif condition.status != "confirmada":
            condition.status = "pendente"
            condition.informada_em = clock.now_utc_naive()
            condition.validada_por = None
            condition.validada_em = None
        if previous != condition.status:
            db.add(PriorityConditionHistory(
                condicao_prioritaria_id=condition.id,
                status_anterior=previous,
                status_novo=condition.status,
                alterado_por=user.id,
            ))
            record_audit_event(
                db,
                user,
                "condicao_prioritaria_informada",
                "condicao_prioritaria",
                condition.id,
                {
                    "condicao": name,
                    "status_anterior": previous,
                    "status_novo": condition.status,
                },
            )
    db.commit()
    db.refresh(user)
    return as_patient(user)


@app.get("/patients/me/summary", response_model=PatientSummary, response_model_exclude_none=True)
def patient_summary(
    user: User = Depends(require_roles("paciente")), db: Session = Depends(get_db)
):
    next_item = db.scalar(
        select(Appointment)
        .where(
            Appointment.paciente_id == user.id,
            Appointment.data_horario > clock.now_sao_paulo_naive(),
            Appointment.status.not_in(["cancelado", "concluido", "falta"]),
        )
        .order_by(Appointment.data_horario)
        .limit(1)
    )
    return PatientSummary(
        patient=as_patient(user),
        next_appointment=as_appointment(next_item) if next_item else None,
    )


@app.get("/appointments/me", response_model=list[AppointmentResponse], response_model_exclude_none=True)
def patient_appointments(
    user: User = Depends(require_roles("paciente")), db: Session = Depends(get_db)
):
    return [
        as_appointment(item)
        for item in db.scalars(
            select(Appointment)
            .where(Appointment.paciente_id == user.id)
            .order_by(Appointment.data_horario)
        )
    ]


@app.get("/queue")
def queue(
    day: date = Query(default_factory=clock.today_sao_paulo),
    specialty: str | None = None,
    professional_id: int | None = None,
    status: str | None = None,
    risk: str | None = None,
    patient: str | None = None,
    user: User = Depends(require_roles(*STAFF)),
    db: Session = Depends(get_db),
):
    from app.services.appointments import legal_priority_code, mark_overdue_absences, queue_sort_key
    valid_statuses = {
        "agendado", "em_espera", "em_triagem", "em_atendimento",
        "concluido", "cancelado", "falta",
    }
    specialty = specialty.strip() if specialty else None
    status = status.strip() if status else None
    risk = risk.strip() if risk else None
    patient = patient.strip() if patient else None
    if status and status not in valid_statuses:
        raise HTTPException(422, "Status de consulta inválido")
    if risk and risk not in RISK_LEVELS:
        raise HTTPException(422, "Classificação de risco inválida")
    if canonical_role(user.perfil) != "medico":
        mark_overdue_absences(db, user)
    start = datetime.combine(day, datetime.min.time())
    end = start + timedelta(days=1)
    query = (
        select(Appointment)
        .where(
            Appointment.data_horario >= start,
            Appointment.data_horario < end,
            Appointment.status.in_(["em_espera", "em_triagem", "em_atendimento"]),
        )
        .order_by(Appointment.data_horario)
    )
    if canonical_role(user.perfil) == "medico":
        query = query.where(
            Appointment.medico_id == user.id,
            Appointment.triagem_em.is_not(None),
            Appointment.status.in_(["em_triagem", "em_atendimento"]),
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
    if risk:
        query = query.where(Appointment.classificacao_risco == risk)
    if patient:
        term = patient.lower()
        cpf = "".join(char for char in term if char.isdigit())
        can_search_cpf = user.perfil in {"admin", "recepcao"}
        query = query.join(Appointment.paciente).where(or_(
            func.lower(User.nome).contains(term),
            User.cpf.contains(cpf) if cpf and can_search_cpf else False,
        ))
    ordered = sorted(db.scalars(query).unique(), key=queue_sort_key)
    return [
        {
            "position": position,
            "id": item.id,
            "patient": protected_name(item.paciente.nome),
            "professional": item.medico.nome,
            "professional_id": item.medico_id,
            "specialty": canonical_specialty_name(item.especialidade),
            "status": item.status,
            "risk_classification": item.classificacao_risco,
            "legal_priority": legal_priority_code(item.paciente),
            "scheduled_at": item.data_horario,
            "arrived_at": item.chegada_em,
        }
        for position, item in enumerate(ordered, start=1)
    ]


@app.get("/availability/calendar-dates", response_model=list[date])
def calendar_dates(
    specialty: str,
    doctor_id: int,
    user: User = Depends(require_roles("paciente")),
    db: Session = Depends(get_db),
):
    from app.routes.admin import is_holiday
    from app.services.appointments import active_booking_link

    if not active_booking_link(db, doctor_id, specialty):
        return []
    rows = db.scalars(
        select(ProfessionalSchedule).where(
            ProfessionalSchedule.medico_id == doctor_id,
            func.lower(func.trim(ProfessionalSchedule.especialidade))
            == canonical_specialty_name(specialty).lower(),
            ProfessionalSchedule.data_horario > clock.now_sao_paulo_naive(),
            ProfessionalSchedule.bloqueado.is_(False),
        )
    )
    return sorted(
        {
            row.data_horario.date()
            for row in rows
            if row.data_horario.weekday() < 5
            and not is_holiday(row.data_horario.date())
            and row.data_horario.hour in GENERAL_HOURS
            and row.data_horario.minute == 0
            and not db.scalar(select(Appointment.id).where(
                Appointment.medico_id == doctor_id,
                Appointment.data_horario == row.data_horario,
                Appointment.status != "cancelado",
            ))
        }
    )


@app.get("/availability/calendar-times", response_model=list[CalendarSlot])
def calendar_times(
    specialty: str,
    doctor_id: int,
    day: date,
    user: User = Depends(require_roles("paciente")),
    db: Session = Depends(get_db),
):
    from app.routes.admin import is_holiday
    from app.services.appointments import active_booking_link

    if (
        day < clock.today_sao_paulo()
        or day.weekday() >= 5
        or is_holiday(day)
        or not active_booking_link(db, doctor_id, specialty)
    ):
        return []
    start = datetime.combine(day, datetime.min.time())
    end = start + timedelta(days=1)
    schedules = list(
        db.scalars(
            select(ProfessionalSchedule)
            .where(
                ProfessionalSchedule.medico_id == doctor_id,
                func.lower(func.trim(ProfessionalSchedule.especialidade))
                == canonical_specialty_name(specialty).lower(),
                ProfessionalSchedule.data_horario >= start,
                ProfessionalSchedule.data_horario < end,
                ProfessionalSchedule.data_horario > clock.now_sao_paulo_naive(),
            )
            .order_by(ProfessionalSchedule.data_horario)
        )
    )
    result = []
    for schedule in schedules:
        at = schedule.data_horario
        if at.hour not in GENERAL_HOURS or at.minute != 0:
            continue
        appointment = db.scalar(
            select(Appointment).where(
                Appointment.medico_id == doctor_id,
                Appointment.data_horario == at,
                Appointment.status != "cancelado",
            )
        )
        if schedule.bloqueado:
            availability, label, selectable = "unavailable", "Indisponível", False
        elif appointment and appointment.paciente_id == user.id:
            availability, label, selectable = (
                "already_scheduled",
                "Já agendado",
                False,
            )
        elif appointment:
            availability, label, selectable = "unavailable", "Indisponível", False
        else:
            availability, label, selectable = "available", "Disponível", True
        result.append(
            CalendarSlot(
                doctor_id=doctor_id,
                doctor_name=schedule.medico.nome,
                specialty=schedule.especialidade,
                scheduled_at=at,
                availability=availability,
                label=label,
                selectable=selectable,
            )
        )
    return result


@app.get("/appointments/{appointment_id:int}", response_model=AppointmentResponse, response_model_exclude_none=True)
def appointment_detail(
    appointment_id: int,
    user: User = Depends(require_roles("paciente")),
    db: Session = Depends(get_db),
):
    return as_appointment(owned(db, appointment_id, user))


def slot_free(db: Session, doctor_id: int, at: datetime, specialty: str) -> None:
    from app.routes.admin import is_holiday
    from app.services.appointments import active_booking_link

    if at.tzinfo is not None or at <= clock.now_sao_paulo_naive():
        raise HTTPException(422, "Informe um horário local futuro")
    if at.weekday() >= 5:
        raise HTTPException(422, "Atendimento permitido somente de segunda a sexta")
    if is_holiday(at.date()):
        raise HTTPException(422, "Atendimento não permitido em feriado nacional")
    if at.minute != 0 or at.second != 0 or at.microsecond != 0 or at.hour not in GENERAL_HOURS:
        raise HTTPException(422, "Horário permitido: 07h–11h ou 13h–17h")
    if not active_booking_link(db, doctor_id, specialty):
        raise HTTPException(
            422,
            "Profissional ou especialidade não está ativo e vinculado para agendamento.",
        )
    slot = db.scalar(
        select(ProfessionalSchedule).where(
            func.lower(func.trim(ProfessionalSchedule.especialidade))
            == canonical_specialty_name(specialty).lower(),
            ProfessionalSchedule.medico_id == doctor_id,
            ProfessionalSchedule.data_horario == at,
            ProfessionalSchedule.bloqueado.is_(False),
        )
    )
    used = db.scalar(
        select(Appointment).where(
            Appointment.medico_id == doctor_id,
            Appointment.data_horario == at,
            Appointment.status != "cancelado",
        )
    )
    if not slot or used:
        raise HTTPException(409, "Horário não está disponível.")


@app.post("/appointments", response_model=AppointmentResponse, response_model_exclude_none=True, status_code=201)
def create_appointment(
    payload: AppointmentCreate,
    user: User = Depends(require_roles("paciente")),
    db: Session = Depends(get_db),
):
    db.execute(text("BEGIN IMMEDIATE"))
    if payload.scheduled_at.tzinfo:
        raise HTTPException(422, "Informe horário local sem fuso")
    from app.services.appointments import full_age
    age = full_age(user.data_nascimento) if user.data_nascimento else None
    if user.e_menor_idade or (age is not None and age < 18):
        guardian = db.scalar(
            select(Guardian)
            .join(PatientGuardian, PatientGuardian.responsavel_id == Guardian.id)
            .where(PatientGuardian.paciente_id == user.id)
        )
        if (
            not guardian
            or not valid_name(guardian.nome)
            or not valid_cpf(digits(guardian.cpf))
        ):
            raise HTTPException(
                409,
                "Menor deve possuir responsável legal com nome e CPF válidos vinculado",
            )
    duplicate = db.scalar(
        select(Appointment).where(
            Appointment.paciente_id == user.id,
            func.lower(func.trim(Appointment.especialidade))
            == canonical_specialty_name(payload.specialty).lower(),
            func.date(Appointment.data_horario) == payload.scheduled_at.date(),
            Appointment.status.not_in(["cancelado", "concluido", "falta"]),
        )
    )
    if duplicate:
        raise HTTPException(
            409, "Já existe consulta ativa desta especialidade para o paciente (RN01)"
        )
    slot_free(db, payload.doctor_id, payload.scheduled_at, payload.specialty)
    item = Appointment(
        paciente_id=user.id,
        medico_id=payload.doctor_id,
        especialidade=payload.specialty,
        data_horario=payload.scheduled_at,
        status="agendado",
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return as_appointment(item)


def owned(db: Session, appointment_id: int, user: User) -> Appointment:
    item = db.get(Appointment, appointment_id)
    if not item:
        raise HTTPException(404, "Consulta não encontrada")
    if user.perfil == "paciente" and item.paciente_id != user.id:
        raise HTTPException(403, "Acesso permitido apenas às próprias consultas")
    return item


@app.post("/appointments/{appointment_id}/cancel", response_model=AppointmentResponse, response_model_exclude_none=True)
def cancel(
    appointment_id: int,
    user: User = Depends(require_roles("paciente")),
    db: Session = Depends(get_db),
):
    item = owned(db, appointment_id, user)
    if item.status != "agendado":
        raise HTTPException(
            409, "Somente consultas agendadas podem ser canceladas ou reagendadas"
        )
    if item.data_horario - clock.now_sao_paulo_naive() < timedelta(hours=24):
        raise HTTPException(
            409, "Cancelamento permitido apenas com 24 horas de antecedência."
        )
    from app.services.appointments import record_audit_event
    previous_status = item.status
    item.status = "cancelado"
    record_audit_event(db, user, "consulta_cancelada", "consulta", item.id, {
        "status_anterior": previous_status, "status_novo": item.status,
    })
    db.commit()
    db.refresh(item)
    result = as_appointment(item)
    result.message = "Consulta cancelada. O horário está disponível novamente."
    return result


@app.post(
    "/appointments/{appointment_id}/reschedule", response_model=AppointmentResponse, response_model_exclude_none=True
)
def reschedule(
    appointment_id: int,
    payload: RescheduleRequest,
    user: User = Depends(require_roles("paciente")),
    db: Session = Depends(get_db),
):
    item = owned(db, appointment_id, user)
    if item.status != "agendado":
        raise HTTPException(
            409, "Somente consultas agendadas podem ser canceladas ou reagendadas"
        )
    db.execute(text("BEGIN IMMEDIATE"))
    if payload.scheduled_at.tzinfo:
        raise HTTPException(422, "Informe horário local sem fuso")
    now = clock.now_sao_paulo_naive()
    if item.data_horario - now < timedelta(
        hours=12
    ) or payload.scheduled_at - now < timedelta(hours=12):
        raise HTTPException(
            409, "Reagendamento exige antecedência mínima de 12 horas (RN03)"
        )
    duplicate = db.scalar(
        select(Appointment).where(
            Appointment.id != item.id,
            Appointment.paciente_id == item.paciente_id,
            Appointment.especialidade == item.especialidade,
            func.date(Appointment.data_horario) == payload.scheduled_at.date(),
            Appointment.status.not_in(["cancelado", "concluido", "falta"]),
        )
    )
    if duplicate:
        raise HTTPException(409, "Já existe consulta ativa desta especialidade para o paciente")
    slot_free(db, payload.doctor_id, payload.scheduled_at, item.especialidade)
    from app.services.appointments import record_audit_event
    previous_doctor_id = item.medico_id
    previous_scheduled_at = item.data_horario
    previous_status = item.status
    item.medico_id, item.data_horario, item.status = (
        payload.doctor_id,
        payload.scheduled_at,
        "agendado",
    )
    record_audit_event(db, user, "consulta_reagendada", "consulta", item.id, {
        "status_anterior": previous_status,
        "status_novo": item.status,
        "medico_anterior_id": previous_doctor_id,
        "medico_novo_id": item.medico_id,
        "horario_anterior": previous_scheduled_at.isoformat(),
        "horario_novo": item.data_horario.isoformat(),
    })
    db.commit()
    db.refresh(item)
    return as_appointment(item)


@app.patch("/schedules/{schedule_id}/block")
def block(
    schedule_id: int,
    blocked: bool = True,
    user: User = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    item = db.get(ProfessionalSchedule, schedule_id)
    if not item:
        raise HTTPException(404, "Agenda não encontrada")
    item.bloqueado = blocked
    db.commit()
    return {"id": item.id, "blocked": item.bloqueado}


from app.routes.recovery import router as recovery_router

app.include_router(recovery_router)
from app.routes.email_verification import router as email_verification_router

app.include_router(email_verification_router)
from app.routes.operations import router as operations_router

app.include_router(operations_router)
from app.routes.admin import router as admin_router

app.include_router(admin_router)
from app.routes.staff import router as staff_router

app.include_router(staff_router)
from app.routes.medical import router as medical_router

app.include_router(medical_router)
