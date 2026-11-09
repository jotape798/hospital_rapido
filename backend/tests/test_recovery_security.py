import logging
import smtplib
import pytest
from sqlalchemy import select, func
from test_integration import client, register, login
from app.core.database import SessionLocal
from app.models import User, Guardian, PatientGuardian, PasswordRecovery
from app.services import mailer
from app.routes import recovery as routes

GUARDIAN = dict(
    birth_date="2015-03-15",
    guardian_name="Ana Souza",
    guardian_cpf="11144477735",
    guardian_birth_date="1980-01-01",
    guardian_phone="11977776666",
    guardian_email="ana@example.com",
    guardian_relationship="Mãe",
)


@pytest.mark.parametrize(
    "field,value,message",
    [
        (
            "guardian_cpf",
            "529.982.247-25",
            "O CPF do responsável deve ser diferente do CPF do paciente.",
        ),
        (
            "guardian_name",
            "  MÁRIA-SILVA   SANTOS  ",
            "O nome do responsável deve ser diferente do nome do paciente.",
        ),
        (
            "guardian_email",
            " MARIA@EXAMPLE.COM ",
            "O e-mail do responsável deve ser diferente do e-mail do paciente.",
        ),
        (
            "guardian_phone",
            "(11) 99999-8888",
            "O telefone do responsável deve ser diferente do telefone do paciente.",
        ),
        ("guardian_email", "", "Informe o e-mail válido do responsável legal."),
        ("guardian_email", "invalido", "Informe o e-mail válido do responsável legal."),
        ("guardian_cpf", "", "Informe o CPF válido do responsável legal."),
        ("guardian_cpf", "11111111111", "Informe o CPF válido do responsável legal."),
        (
            "guardian_birth_date",
            "2012-01-01",
            "O responsável legal deve ter pelo menos 18 anos.",
        ),
    ],
)
def test_guardian_specific_error(client, field, value, message):
    response = register(client, **{**GUARDIAN, field: value})
    assert response.status_code == 422
    assert response.json()["detail"] == {"field": field, "message": message}
    with SessionLocal() as db:
        assert db.scalar(select(func.count(User.id))) == 0


def test_cns_ignored_and_old_values_preserved(client):
    assert register(client).status_code == 201
    with SessionLocal() as db:
        u = db.scalar(select(User))
        assert u.cns is None
        u.cns = "123456789012345"
        db.commit()
    from app.main import migrate_database

    migrate_database()
    with SessionLocal() as db:
        assert db.scalar(select(User)).cns == "123456789012345"
    assert login(client, document="123456789012345").status_code == 401


def test_shared_guardian_email_must_match_recovery_destination(client):
    assert register(client, **GUARDIAN).status_code == 201
    second = dict(GUARDIAN, cpf="12345678909", email="second@example.com")
    mismatch = register(client, **dict(second, guardian_email="wrong@example.com"))
    assert mismatch.status_code == 422
    assert mismatch.json()["detail"]["field"] == "guardian_email"
    with SessionLocal() as db:
        assert db.scalar(select(func.count(User.id))) == 1
        assert db.scalar(select(func.count(Guardian.id))) == 1
    assert register(client, **second).status_code == 201
    with SessionLocal() as db:
        assert db.scalar(select(func.count(Guardian.id))) == 1
        assert db.scalar(select(func.count(PatientGuardian.paciente_id))) == 2


@pytest.fixture
def smtp(monkeypatch):
    for key, value in {
        "SMTP_HOST": "smtp.example.com",
        "SMTP_PORT": "587",
        "SMTP_USER": "sender@example.com",
        "SMTP_PASSWORD": "mock-only-value",
        "SMTP_FROM": "sender@example.com",
        "SMTP_USE_TLS": "true",
    }.items():
        monkeypatch.setenv(key, value)
    events = []

    class FakeSMTP:
        def __init__(self, *args, **kwargs):
            events.append(("connect", args, kwargs))

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def ehlo(self):
            events.append(("ehlo",))

        def starttls(self, **kwargs):
            events.append(("tls", kwargs))

        def login(self, *args):
            events.append(("login",))

        def send_message(self, message):
            events.append(("message", message))
            return {}

    monkeypatch.setattr(mailer.smtplib, "SMTP", FakeSMTP)
    monkeypatch.setattr(mailer.smtplib, "SMTP_SSL", FakeSMTP)
    return events, FakeSMTP


def test_mail_tls_message_and_no_secret_logging(smtp, monkeypatch, caplog, capsys):
    monkeypatch.setenv("DEV_SHOW_RECOVERY_CODE", "true")
    with caplog.at_level(logging.INFO):
        mailer.send_recovery("test@example.com", "123456")
    events, _ = smtp
    assert [e[0] for e in events] == [
        "connect",
        "ehlo",
        "tls",
        "ehlo",
        "login",
        "message",
    ]
    message = events[-1][1]
    assert "123456" in message.get_content() and "10 minutos" in message.get_content()
    assert message["Subject"] == "Código para recuperação de senha - UBS Rápida"
    assert "123456" not in caplog.text + capsys.readouterr().out
    assert "mock-only-value" not in caplog.text
    assert events[2][1]["context"].check_hostname
    assert events[0][2]["timeout"] == 10


def test_implicit_tls(smtp, monkeypatch):
    monkeypatch.setenv("SMTP_PORT", "465")
    mailer.send_recovery("test@example.com", "123456")
    events, _ = smtp
    assert events[0][2]["context"].check_hostname
    assert not any(e[0] == "tls" for e in events)


@pytest.mark.parametrize(
    "case,expected",
    [
        ("missing", "SMTP_CONFIG_MISSING"),
        ("auth", "SMTP_AUTH_FAILED"),
        ("offline", "SMTP_UNAVAILABLE"),
        ("email", "SMTP_INVALID_ADDRESS"),
        ("tls", "SMTP_TLS_REQUIRED"),
        ("port", "SMTP_PORT_INVALID"),
        ("disabled", "SMTP_DISABLED"),
    ],
)
def test_mail_failures(smtp, monkeypatch, case, expected):
    _, fake = smtp
    recipient = "test@example.com"
    if case == "missing":
        monkeypatch.delenv("SMTP_USER")
    if case == "tls":
        monkeypatch.setenv("SMTP_USE_TLS", "false")
    if case == "port":
        monkeypatch.setenv("SMTP_PORT", "25")
    if case == "disabled":
        monkeypatch.setenv("SMTP_ENABLED", "false")
    if case == "email":
        recipient = "invalid"

    def fail_auth(*a):
        raise smtplib.SMTPAuthenticationError(535, b"details secret")

    def offline(*a, **k):
        raise OSError("details secret")

    if case == "auth":
        monkeypatch.setattr(fake, "login", fail_auth)
    if case == "offline":
        monkeypatch.setattr(mailer.smtplib, "SMTP", offline)
    with pytest.raises(mailer.MailUnavailable) as error:
        mailer.send_recovery(recipient, "123456")
    assert error.value.reason == expected and "secret" not in str(error.value)


def test_placeholder_configuration_names_fields_without_leaking_values(
    smtp, monkeypatch, caplog
):
    monkeypatch.setenv("SMTP_USER", "COLOQUE_SEU_EMAIL_AQUI")
    monkeypatch.setenv("SMTP_PASSWORD", "COLOQUE_A_CREDENCIAL_AQUI")
    monkeypatch.setenv("SMTP_FROM", "COLOQUE_SEU_EMAIL_AQUI")

    with caplog.at_level(logging.ERROR), pytest.raises(mailer.MailUnavailable) as error:
        mailer.send_email_verification("patient@example.com", "123456")

    assert error.value.reason == "SMTP_CONFIG_MISSING"
    assert "SMTP_USER,SMTP_PASSWORD,SMTP_FROM" in caplog.text
    assert "COLOQUE_SEU_EMAIL_AQUI" not in caplog.text
    assert "COLOQUE_A_CREDENCIAL_AQUI" not in caplog.text


def test_authentication_failure_logs_only_safe_technical_cause(
    smtp, monkeypatch, caplog
):
    _, fake = smtp

    def fail_auth(*args):
        raise smtplib.SMTPAuthenticationError(535, b"sensitive provider response")

    monkeypatch.setattr(fake, "login", fail_auth)
    with caplog.at_level(logging.ERROR), pytest.raises(mailer.MailUnavailable) as error:
        mailer.send_email_verification("patient@example.com", "123456")

    assert error.value.reason == "SMTP_AUTH_FAILED"
    assert "exception_type=SMTPAuthenticationError" in caplog.text
    assert "sensitive provider response" not in caplog.text
    assert "123456" not in caplog.text


def test_advertised_login_keeps_original_535_authentication_error(
    smtp, caplog
):
    _, fake = smtp
    fake.esmtp_features = {"auth": "LOGIN PLAIN"}
    fake.auth_login = object()

    def reject_auth(*args, **kwargs):
        raise smtplib.SMTPAuthenticationError(535, b"provider details")

    fake.auth = reject_auth
    with caplog.at_level(logging.ERROR), pytest.raises(mailer.MailUnavailable) as error:
        mailer.send_email_verification("patient@example.com", "123456")

    assert error.value.reason == "SMTP_AUTH_FAILED"
    assert "exception_type=SMTPAuthenticationError" in caplog.text
    assert "provider details" not in caplog.text
    assert "123456" not in caplog.text
