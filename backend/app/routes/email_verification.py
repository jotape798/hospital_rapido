"""Verificação de posse do e-mail usado no cadastro de pacientes."""

from datetime import timedelta
import hmac
import logging
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core import clock
from app.core.security import digest, throttle
from app.models import EmailVerification, User
from app.schemas import (
    EmailVerificationConfirm,
    EmailVerificationCorrection,
    EmailVerificationRequest,
)
from app.services.mailer import (
    MailUnavailable,
    delivery_error_message,
    send_email_verification,
)

router = APIRouter(prefix="/auth/email", tags=["Verificação de e-mail"])
logger = logging.getLogger(__name__)

CODE_TTL_MINUTES = 10
MAX_CODE_ATTEMPTS = 5
RESEND_WAIT_SECONDS = 60
GENERIC_MESSAGE = (
    "Se o cadastro estiver disponível para verificação, enviaremos um código ao e-mail informado."
)


def generate_verification_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_verification_code(user_id: int, code: str) -> str:
    return digest(f"email-verification:{user_id}:{code}")


def generate_correction_token() -> str:
    return secrets.token_urlsafe(32)


def hash_correction_token(token: str) -> str:
    return digest(f"email-verification-correction:{token}")


def verification_code_matches(user_id: int, code: str, encoded: str) -> bool:
    return hmac.compare_digest(encoded, hash_verification_code(user_id, code))


def issue_verification_code(
    user: User, db: Session, correction_token: str | None = None
) -> None:
    """Deliver and persist a new code without ever returning or logging it."""
    code = generate_verification_code()
    send_email_verification(user.email, code)
    now = clock.now_utc_naive()
    correction_token_hash = (
        hash_correction_token(correction_token) if correction_token else None
    )
    if correction_token_hash is None:
        correction_token_hash = db.scalar(
            select(EmailVerification.token_correcao_hash)
            .where(
                EmailVerification.usuario_id == user.id,
                EmailVerification.token_correcao_hash.is_not(None),
            )
            .order_by(EmailVerification.id.desc())
        )
    db.execute(
        update(EmailVerification)
        .where(EmailVerification.usuario_id == user.id)
        .values(utilizado=True)
    )
    db.add(
        EmailVerification(
            usuario_id=user.id,
            codigo_hash=hash_verification_code(user.id, code),
            expira_em=now + timedelta(minutes=CODE_TTL_MINUTES),
            token_correcao_hash=correction_token_hash,
        )
    )


def _user_for_email(email: str, db: Session) -> User | None:
    return db.scalar(
        select(User).where(
            User.email.ilike(email.strip().lower()),
            User.ativo.is_(True),
        )
    )


def _request_code(
    payload: EmailVerificationRequest,
    request: Request,
    db: Session,
    *,
    action: str,
):
    email = str(payload.email).strip().lower()
    attempts = throttle(db, request, action, email, 3)
    user = _user_for_email(email, db)
    pending_user = user if user and not user.email_verificado else None
    latest = (
        db.scalar(
            select(EmailVerification)
            .where(
                EmailVerification.usuario_id == pending_user.id,
                EmailVerification.utilizado.is_(False),
            )
            .order_by(EmailVerification.id.desc())
        )
        if pending_user
        else None
    )
    now = clock.now_utc_naive()
    if latest and latest.criado_em > now - timedelta(seconds=RESEND_WAIT_SECONDS):
        retry_after = max(
            1,
            RESEND_WAIT_SECONDS - int((now - latest.criado_em).total_seconds()),
        )
        raise HTTPException(
            429,
            f"Aguarde {retry_after} segundos antes de reenviar o código.",
            headers={"Retry-After": str(retry_after)},
        )

    try:
        # O mesmo handshake SMTP também é feito para endereços sem conta,
        # reduzindo diferenças observáveis nas respostas públicas.
        if pending_user:
            issue_verification_code(pending_user, db)
        else:
            send_email_verification(None, None)
    except MailUnavailable as error:
        logger.warning(
            "email_verification_delivery status=failed reason=%s timestamp=%s attempts=%s",
            error.reason,
            clock.now_utc().isoformat(),
            attempts,
        )
        raise HTTPException(
            503,
            delivery_error_message(error.reason),
        ) from None

    if pending_user:
        db.commit()
    return {"message": GENERIC_MESSAGE, "resend_after_seconds": RESEND_WAIT_SECONDS}


@router.post("/solicitar-codigo", summary="Enviar código de verificação")
def request_code(
    payload: EmailVerificationRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    return _request_code(payload, request, db, action="email-verification-request")


@router.post("/reenviar-codigo", summary="Reenviar código de verificação")
def resend_code(
    payload: EmailVerificationRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    return _request_code(payload, request, db, action="email-verification-resend")


@router.post("/corrigir", summary="Corrigir e-mail de um cadastro pendente")
def correct_email(
    payload: EmailVerificationCorrection,
    request: Request,
    db: Session = Depends(get_db),
):
    token_hash = hash_correction_token(payload.verification_token)
    throttle(db, request, "email-verification-correct", token_hash, 5)
    verification = db.scalar(
        select(EmailVerification)
        .where(EmailVerification.token_correcao_hash == token_hash)
        .order_by(EmailVerification.id.desc())
    )
    user = db.get(User, verification.usuario_id) if verification else None
    if (
        not user
        or not user.ativo
        or user.perfil != "paciente"
        or user.email_verificado
    ):
        raise HTTPException(
            401,
            "Não foi possível corrigir o e-mail. Refazer o cadastro pode ser necessário.",
        )
    email = str(payload.new_email).strip().lower()
    duplicate = db.scalar(
        select(User.id).where(func.lower(User.email) == email, User.id != user.id)
    )
    if duplicate:
        raise HTTPException(
            409,
            {
                "field": "email",
                "message": "Não foi possível usar este e-mail. Informe outro endereço.",
            },
        )
    user.email = email
    db.execute(
        update(EmailVerification)
        .where(EmailVerification.usuario_id == user.id)
        .values(utilizado=True)
    )
    db.commit()
    return {"message": "E-mail atualizado. Solicite um novo código.", "email": email}


@router.post("/validar-codigo", summary="Validar código e confirmar o e-mail")
def validate_code(
    payload: EmailVerificationConfirm,
    request: Request,
    db: Session = Depends(get_db),
):
    email = str(payload.email).strip().lower()
    user = _user_for_email(email, db)
    row = (
        db.scalar(
            select(EmailVerification)
            .where(EmailVerification.usuario_id == user.id)
            .order_by(EmailVerification.id.desc())
        )
        if user and not user.email_verificado
        else None
    )
    throttle(
        db,
        request,
        "email-verification-validate",
        f"{email}:{row.id if row else 0}",
        MAX_CODE_ATTEMPTS,
    )
    error = HTTPException(
        400,
        "Código inválido, expirado ou sem tentativas disponíveis. Solicite um novo código.",
    )
    now = clock.now_utc_naive()
    if (
        not row
        or row.utilizado
        or row.tentativas >= MAX_CODE_ATTEMPTS
        or row.expira_em <= now
    ):
        raise error
    correct = verification_code_matches(user.id, payload.code, row.codigo_hash)
    updated = db.execute(
        update(EmailVerification)
        .where(
            EmailVerification.id == row.id,
            EmailVerification.tentativas < MAX_CODE_ATTEMPTS,
            EmailVerification.utilizado.is_(False),
            EmailVerification.expira_em > now,
        )
        .values(
            tentativas=EmailVerification.tentativas + 1,
            utilizado=correct,
        )
    )
    if correct and updated.rowcount == 1:
        user.email_verificado = True
        db.execute(
            update(EmailVerification)
            .where(
                EmailVerification.usuario_id == user.id,
                EmailVerification.id != row.id,
            )
            .values(utilizado=True)
        )
        db.commit()
        return {"message": "E-mail validado com sucesso. Você já pode entrar."}
    db.commit()
    raise error
