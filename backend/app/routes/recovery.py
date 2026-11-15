from datetime import timedelta
import hmac
import secrets
from fastapi import APIRouter, Depends, HTTPException, Request
from jose import jwt, JWTError
from sqlalchemy import select, update
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core import clock
from app.models import User, PasswordRecovery
from app.schemas import (
    PasswordChange,
    EmailPasswordRecoveryRequest,
    EmailPasswordRecoveryVerify,
    EmailPasswordReset,
)
from app.core.security import digest, throttle, pwd, current_user
from app.core.config import SECRET, ALGORITHM
from app.services.mailer import send_recovery, MailUnavailable
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth")
EMAIL_GENERIC = "Se o e-mail estiver cadastrado, enviaremos um código de verificação."
RESEND_WAIT_SECONDS = 60


@router.post("/change-password")
def change_password(
    payload: PasswordChange,
    request: Request,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    from app.main import valid_password

    throttle(db, request, "change-password", str(user.id), 5)
    if not pwd.verify(payload.current_password, user.senha_hash):
        raise HTTPException(400, "Senha atual incorreta")
    if not valid_password(payload.password):
        raise HTTPException(
            422,
            "Senha deve ter 8 a 32 caracteres, maiúscula, minúscula, número e símbolo",
        )
    if pwd.verify(payload.password, user.senha_hash):
        raise HTTPException(422, "A nova senha deve ser diferente da senha atual")
    changed = db.execute(
        update(User)
        .where(User.id == user.id, User.token_version == user.token_version)
        .values(
            senha_hash=pwd.hash(payload.password), token_version=User.token_version + 1
        )
    )
    if changed.rowcount != 1:
        db.rollback()
        raise HTTPException(401, "Sessão inválida ou expirada")
    db.execute(
        update(PasswordRecovery)
        .where(PasswordRecovery.usuario_id == user.id)
        .values(utilizado=True)
    )
    db.commit()
    return {"message": "Senha alterada com sucesso. Entre novamente."}


def _email_user(email: str, db: Session):
    return db.scalar(
        select(User).where(
            User.email.ilike(email.strip().lower()),
            User.ativo.is_(True),
        )
    )


@router.post("/esqueci-senha")
def forgot_by_email(
    payload: EmailPasswordRecoveryRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Solicita um código sem revelar se o endereço pertence a uma conta."""
    email = str(payload.email).strip().lower()
    attempts = throttle(db, request, "email-recovery", email, 3)
    user = _email_user(email, db)
    if user and not user.email_verificado:
        raise HTTPException(
            403,
            "Confirme seu e-mail antes de solicitar a recuperação de senha.",
        )
    if user:
        latest = db.scalar(
            select(PasswordRecovery)
            .where(
                PasswordRecovery.usuario_id == user.id,
                PasswordRecovery.utilizado.is_(False),
            )
            .order_by(PasswordRecovery.id.desc())
        )
        if latest and latest.criado_em > clock.now_utc_naive() - timedelta(
            seconds=RESEND_WAIT_SECONDS
        ):
            # Mantém a mesma verificação de disponibilidade usada para contas
            # desconhecidas, reduzindo diferenças observáveis entre respostas.
            try:
                send_recovery(None, None)
            except MailUnavailable:
                raise HTTPException(
                    503,
                    "Serviço de e-mail temporariamente indisponível. Tente novamente mais tarde.",
                ) from None
            return {"message": EMAIL_GENERIC, "resend_after_seconds": RESEND_WAIT_SECONDS}

    code = f"{secrets.randbelow(1000000):06d}" if user else None
    try:
        send_recovery(email if user else None, code)
    except MailUnavailable as error:
        logger.warning(
            "email_recovery_delivery status=failed reason=%s timestamp=%s attempts=%s",
            error.reason,
            clock.now_utc().isoformat(),
            attempts,
        )
        raise HTTPException(
            503,
            "Serviço de e-mail temporariamente indisponível. Tente novamente mais tarde.",
        ) from None

    if user:
        db.execute(
            update(PasswordRecovery)
            .where(PasswordRecovery.usuario_id == user.id)
            .values(utilizado=True)
        )
        db.add(
            PasswordRecovery(
                usuario_id=user.id,
                codigo_hash=digest(f"{user.id}:{code}"),
                expira_em=clock.now_utc_naive() + timedelta(minutes=10),
            )
        )
        db.commit()
    return {"message": EMAIL_GENERIC, "resend_after_seconds": RESEND_WAIT_SECONDS}


@router.post("/validar-codigo-recuperacao")
def verify_email_recovery(
    payload: EmailPasswordRecoveryVerify,
    request: Request,
    db: Session = Depends(get_db),
):
    email = str(payload.email).strip().lower()
    throttle(db, request, "email-recovery-verify", email, 5)
    user = _email_user(email, db)
    row = (
        db.scalar(
            select(PasswordRecovery)
            .where(PasswordRecovery.usuario_id == user.id)
            .order_by(PasswordRecovery.id.desc())
        )
        if user
        else None
    )
    error = HTTPException(400, "Código inválido ou expirado. Solicite um novo código.")
    now = clock.now_utc_naive()
    if (
        not row
        or row.utilizado
        or row.verificado
        or row.tentativas >= 5
        or row.expira_em <= now
    ):
        raise error
    correct = hmac.compare_digest(
        row.codigo_hash, digest(f"{user.id}:{payload.code}")
    )
    updated = db.execute(
        update(PasswordRecovery)
        .where(
            PasswordRecovery.id == row.id,
            PasswordRecovery.tentativas < 5,
            PasswordRecovery.verificado.is_(False),
            PasswordRecovery.utilizado.is_(False),
            PasswordRecovery.expira_em > now,
        )
        .values(tentativas=PasswordRecovery.tentativas + 1, verificado=correct)
    )
    db.commit()
    if not correct or updated.rowcount != 1:
        raise error
    token = jwt.encode(
        {
            "sub": str(user.id),
            "rid": row.id,
            "purpose": "password_recovery",
            "exp": row.expira_em.replace(tzinfo=clock.UTC),
        },
        SECRET,
        algorithm=ALGORITHM,
    )
    return {"recovery_token": token}


@router.post("/redefinir-senha")
def reset_email_password(payload: EmailPasswordReset, db: Session = Depends(get_db)):
    from app.main import valid_password

    try:
        data = jwt.decode(payload.recovery_token, SECRET, algorithms=[ALGORITHM])
        if data.get("purpose") != "password_recovery":
            raise ValueError()
        user = db.get(User, int(data["sub"]))
        row = db.get(PasswordRecovery, int(data["rid"]))
        if (
            not user
            or not user.ativo
            or not row
            or row.usuario_id != user.id
            or not row.verificado
            or row.utilizado
            or row.expira_em <= clock.now_utc_naive()
        ):
            raise ValueError()
    except (JWTError, ValueError, KeyError, TypeError):
        raise HTTPException(401, "Recuperação inválida ou expirada")

    if payload.new_password != payload.confirm_new_password:
        raise HTTPException(
            422,
            {"field": "confirm_new_password", "message": "As senhas não conferem."},
        )
    if not valid_password(payload.new_password):
        raise HTTPException(
            422,
            "Senha deve ter no mínimo 8 caracteres, maiúscula, minúscula, número e símbolo",
        )

    consumed = db.execute(
        update(PasswordRecovery)
        .where(
            PasswordRecovery.id == row.id,
            PasswordRecovery.utilizado.is_(False),
        )
        .values(utilizado=True)
    )
    if consumed.rowcount != 1:
        db.rollback()
        raise HTTPException(401, "Recuperação inválida ou expirada")
    user.senha_hash = pwd.hash(payload.new_password)
    user.token_version += 1
    db.execute(
        update(PasswordRecovery)
        .where(PasswordRecovery.usuario_id == user.id)
        .values(utilizado=True)
    )
    db.commit()
    return {
        "message": "Senha alterada com sucesso. Faça login com sua nova senha."
    }
