"""Inclusão opcional, transacional e idempotente da equipe fictícia ampliada."""

from collections import Counter
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from pathlib import Path
import secrets

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core import clock
from app.core.extended_demo_staff import EXTENDED_DEMO_STAFF, ExtendedDemoStaff
from app.core.security import pwd
from app.core.specialty import canonical_specialty_name, specialty_key
from app.models import (
    ProfessionalProfile,
    ProfessionalSchedule,
    ScheduleGrid,
    Specialty,
    User,
)


class ExtendedDemoSeedConflict(RuntimeError):
    """Impede que o seed altere silenciosamente uma identidade preexistente."""


@dataclass(frozen=True)
class ExtendedDemoSeedReport:
    created_by_role: dict[str, int]
    existing_users: int
    specialties_created: int
    grids_created: int
    slots_created: int
    access_file: Path


def _email(spec: ExtendedDemoStaff) -> str:
    return f"demo.staff.{spec.key}@ubs-rapida.local"


def _calculate_cpf(base: str) -> str:
    numbers = [int(value) for value in base]
    first = (sum(value * weight for value, weight in zip(numbers, range(10, 1, -1))) * 10) % 11
    first = 0 if first == 10 else first
    numbers.append(first)
    second = (sum(value * weight for value, weight in zip(numbers, range(11, 1, -1))) * 10) % 11
    second = 0 if second == 10 else second
    return base + str(first) + str(second)


def _new_cpf(db: Session, reserved: set[str]) -> str:
    while True:
        base = "".join(str(secrets.randbelow(10)) for _ in range(9))
        if len(set(base)) == 1:
            continue
        candidate = _calculate_cpf(base)
        if candidate in reserved or db.scalar(select(User.id).where(User.cpf == candidate)):
            continue
        reserved.add(candidate)
        return candidate


def _new_password() -> str:
    alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@%+-_"
    return (
        secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ")
        + secrets.choice("abcdefghijkmnopqrstuvwxyz")
        + secrets.choice("23456789")
        + secrets.choice("!@%+-_")
        + "".join(secrets.choice(alphabet) for _ in range(12))
    )


def _read_access_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def _write_access_file(
    path: Path,
    credentials: dict[str, tuple[str, str]],
) -> None:
    lines = [
        "# ACESSO LOCAL — EQUIPE FICTÍCIA AMPLIADA",
        "# Arquivo ignorado pelo Git. Não enviar, publicar ou versionar.",
        "# Login único: use o CPF e a senha correspondentes.",
        "",
    ]
    for spec in EXTENDED_DEMO_STAFF:
        cpf, password = credentials[spec.key]
        prefix = spec.key.upper()
        details = f"{spec.profession}"
        if spec.specialty:
            details += f" — {canonical_specialty_name(spec.specialty)}"
        lines.extend(
            [
                f"# {spec.name} | {details} | perfil de acesso: {spec.role}",
                f"{prefix}_CPF={cpf}",
                f"{prefix}_SENHA={password}",
                "",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text("\n".join(lines), encoding="utf-8")
    temporary.replace(path)


def _credentials(db: Session, access_file: Path) -> dict[str, tuple[str, str]]:
    saved = _read_access_file(access_file)
    reserved: set[str] = set()
    result: dict[str, tuple[str, str]] = {}
    for spec in EXTENDED_DEMO_STAFF:
        prefix = spec.key.upper()
        cpf = saved.get(f"{prefix}_CPF", "")
        password = saved.get(f"{prefix}_SENHA", "")
        existing = db.scalar(
            select(User).where(func.lower(User.email) == _email(spec).casefold())
        )
        if not cpf and existing:
            cpf = existing.cpf
        if not cpf:
            cpf = _new_cpf(db, reserved)
        if not password:
            if existing:
                raise ExtendedDemoSeedConflict(
                    f"A conta fictícia '{spec.name}' existe, mas o arquivo local de acesso "
                    "não contém sua senha. Preserve ou restaure o arquivo local antes de executar."
                )
            password = _new_password()
        reserved.add(cpf)
        result[spec.key] = (cpf, password)
    return result


def _specialties(db: Session) -> tuple[dict[str, Specialty], int]:
    requested = {
        canonical_specialty_name(spec.specialty)
        for spec in EXTENDED_DEMO_STAFF
        if spec.specialty
    }
    existing: dict[str, Specialty] = {}
    for row in db.scalars(select(Specialty)):
        key = specialty_key(row.nome)
        if key in existing:
            raise ExtendedDemoSeedConflict(
                f"Há especialidades duplicadas para a grafia canônica '{row.nome}'."
            )
        existing[key] = row
    created = 0
    result: dict[str, Specialty] = {}
    for name in sorted(requested):
        key = specialty_key(name)
        row = existing.get(key)
        if row and not row.ativo:
            raise ExtendedDemoSeedConflict(
                f"A especialidade '{name}' já existe, mas está desativada."
            )
        if not row:
            row = Specialty(nome=name, ativo=True)
            db.add(row)
            db.flush()
            existing[key] = row
            created += 1
        result[name] = row
    return result, created


def _validate_user(
    db: Session,
    spec: ExtendedDemoStaff,
    user: User,
    cpf: str,
    password: str,
) -> None:
    checks = (
        (user.cpf == cpf, "CPF diferente do arquivo local"),
        (user.nome == spec.name, "nome diferente"),
        (user.perfil == spec.role, "perfil de acesso diferente"),
        (user.email.casefold() == _email(spec).casefold(), "e-mail técnico diferente"),
        (user.ativo is True, "conta desativada"),
        (pwd.verify(password, user.senha_hash), "senha diferente do arquivo local"),
    )
    for valid, reason in checks:
        if not valid:
            raise ExtendedDemoSeedConflict(
                f"Conflito na conta fictícia '{spec.name}': {reason}."
            )
    profile = db.scalar(
        select(ProfessionalProfile).where(ProfessionalProfile.usuario_id == user.id)
    )
    if spec.specialty:
        if not profile:
            raise ExtendedDemoSeedConflict(
                f"Conflito na conta fictícia '{spec.name}': perfil profissional ausente."
            )
        specialty = db.get(Specialty, profile.especialidade_id)
        if (
            profile.registro_profissional != spec.registration
            or not specialty
            or specialty_key(specialty.nome) != specialty_key(spec.specialty)
            or profile.autorizado_triagem != (spec.role == "enfermagem")
            or profile.ativo is not True
        ):
            raise ExtendedDemoSeedConflict(
                f"Conflito na conta fictícia '{spec.name}': vínculo profissional diferente."
            )
    elif profile:
        raise ExtendedDemoSeedConflict(
            f"Conflito na conta fictícia '{spec.name}': Recepção não deve ter perfil clínico."
        )


def _next_service_days(amount: int = 5) -> list[datetime]:
    from app.routes.admin import is_holiday

    result: list[datetime] = []
    day = clock.today_sao_paulo()
    while len(result) < amount:
        day += timedelta(days=1)
        if day.weekday() < 5 and not is_holiday(day):
            result.append(datetime.combine(day, time.min))
    return result


def _ensure_schedules(
    db: Session,
    users: dict[str, User],
    specialties: dict[str, Specialty],
    creator_id: int,
) -> tuple[int, int]:
    grids_created = 0
    slots_created = 0
    service_days = _next_service_days()
    hours = (7, 8, 9, 10, 11, 13, 14, 15, 16, 17)
    for spec in (item for item in EXTENDED_DEMO_STAFF if item.role == "medico"):
        user = users[spec.key]
        specialty = specialties[canonical_specialty_name(spec.specialty)]
        for day in service_days:
            grids = list(db.scalars(select(ScheduleGrid).where(
                ScheduleGrid.profissional_id == user.id,
                ScheduleGrid.data == day,
                ScheduleGrid.ativo.is_(True),
            )))
            if grids:
                if len(grids) != 1 or any(
                    grid.especialidade_id != specialty.id
                    or grid.horario_inicio != "07:00"
                    or grid.horario_fim != "18:00"
                    or grid.duracao_minutos != 60
                    or grid.quantidade_vagas != 1
                    or grid.intervalo_inicio != "12:00"
                    or grid.intervalo_fim != "13:00"
                    for grid in grids
                ):
                    raise ExtendedDemoSeedConflict(
                        f"A grade existente de '{spec.name}' em {day.date()} é incompatível."
                    )
            else:
                db.add(ScheduleGrid(
                    profissional_id=user.id,
                    especialidade_id=specialty.id,
                    data=day,
                    horario_inicio="07:00",
                    horario_fim="18:00",
                    duracao_minutos=60,
                    quantidade_vagas=1,
                    intervalo_inicio="12:00",
                    intervalo_fim="13:00",
                    ativo=True,
                    criado_por=creator_id,
                ))
                grids_created += 1
            for hour in hours:
                at = day.replace(hour=hour)
                slot = db.scalar(select(ProfessionalSchedule).where(
                    ProfessionalSchedule.medico_id == user.id,
                    ProfessionalSchedule.data_horario == at,
                ))
                if slot:
                    if specialty_key(slot.especialidade) != specialty_key(specialty.nome):
                        raise ExtendedDemoSeedConflict(
                            f"O horário de '{spec.name}' em {at} possui outra especialidade."
                        )
                    continue
                db.add(ProfessionalSchedule(
                    medico_id=user.id,
                    especialidade=specialty.nome,
                    data_horario=at,
                    bloqueado=False,
                ))
                slots_created += 1
    db.flush()
    return grids_created, slots_created


def ensure_extended_demo_staff(
    db: Session,
    access_file: Path,
) -> ExtendedDemoSeedReport:
    """Inclui somente a equipe fictícia ampliada e suas agendas futuras."""

    credentials = _credentials(db, access_file)
    specialties, specialties_created = _specialties(db)
    created_by_role: Counter[str] = Counter()
    existing_users = 0
    users: dict[str, User] = {}

    for spec in EXTENDED_DEMO_STAFF:
        cpf, password = credentials[spec.key]
        by_cpf = db.scalar(select(User).where(User.cpf == cpf))
        by_email = db.scalar(
            select(User).where(func.lower(User.email) == _email(spec).casefold())
        )
        if by_cpf and by_email and by_cpf.id != by_email.id:
            raise ExtendedDemoSeedConflict(
                f"CPF e e-mail técnico de '{spec.name}' pertencem a contas diferentes."
            )
        user = by_cpf or by_email
        if user:
            _validate_user(db, spec, user, cpf, password)
            existing_users += 1
        else:
            user = User(
                nome=spec.name,
                cpf=cpf,
                email=_email(spec),
                senha_hash=pwd.hash(password),
                perfil=spec.role,
                ativo=True,
                email_verificado=True,
            )
            db.add(user)
            db.flush()
            if spec.specialty:
                specialty = specialties[canonical_specialty_name(spec.specialty)]
                db.add(ProfessionalProfile(
                    usuario_id=user.id,
                    registro_profissional=spec.registration,
                    especialidade_id=specialty.id,
                    autorizado_triagem=spec.role == "enfermagem",
                    ativo=True,
                ))
                db.flush()
            created_by_role[spec.role] += 1
        users[spec.key] = user

    creator = db.scalar(select(User).where(
        User.perfil == "admin", User.ativo.is_(True)
    ).order_by(User.id))
    if not creator:
        raise ExtendedDemoSeedConflict(
            "É necessário manter ao menos um administrador ativo para registrar as grades."
        )
    grids_created, slots_created = _ensure_schedules(
        db, users, specialties, creator.id
    )
    _write_access_file(access_file, credentials)
    return ExtendedDemoSeedReport(
        created_by_role=dict(created_by_role),
        existing_users=existing_users,
        specialties_created=specialties_created,
        grids_created=grids_created,
        slots_created=slots_created,
        access_file=access_file,
    )
