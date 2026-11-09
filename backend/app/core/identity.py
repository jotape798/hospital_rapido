import unicodedata
from fastapi import HTTPException


def normalized_name(value):
    return " ".join(
        "".join(
            c
            for c in unicodedata.normalize("NFD", value or "")
            if not unicodedata.combining(c)
        )
        .casefold()
        .split()
    )


def field_error(field, message):
    raise HTTPException(422, {"field": field, "message": message})


def validate_guardian(payload):
    from app.main import digits, valid_cpf, valid_name, is_minor

    name = " ".join((payload.guardian_name or "").split())
    if not valid_name(name):
        field_error("guardian_name", "Informe nome e sobrenome do responsável legal.")
    if normalized_name(name) == normalized_name(payload.name):
        field_error(
            "guardian_name",
            "O nome do responsável deve ser diferente do nome do paciente.",
        )
    cpf = digits(payload.guardian_cpf or "")
    if any(
        c not in "0123456789.- " for c in (payload.guardian_cpf or "")
    ) or not valid_cpf(cpf):
        field_error("guardian_cpf", "Informe o CPF válido do responsável legal.")
    if cpf == digits(payload.cpf):
        field_error(
            "guardian_cpf",
            "O CPF do responsável deve ser diferente do CPF do paciente.",
        )
    if not payload.guardian_email:
        field_error("guardian_email", "Informe o e-mail válido do responsável legal.")
    if (
        str(payload.guardian_email).strip().casefold()
        == str(payload.email).strip().casefold()
    ):
        field_error(
            "guardian_email",
            "O e-mail do responsável deve ser diferente do e-mail do paciente.",
        )
    phone = digits(payload.guardian_phone or "")
    if len(phone) not in (10, 11):
        field_error("guardian_phone", "Informe o telefone válido do responsável legal.")
    if phone == digits(payload.phone):
        field_error(
            "guardian_phone",
            "O telefone do responsável deve ser diferente do telefone do paciente.",
        )
    if not payload.guardian_birth_date:
        field_error(
            "guardian_birth_date",
            "Informe a data de nascimento do responsável legal.",
        )
    if is_minor(payload.guardian_birth_date):
        field_error(
            "guardian_birth_date", "O responsável legal deve ter pelo menos 18 anos."
        )
    if not payload.guardian_relationship:
        field_error(
            "guardian_relationship", "Informe o parentesco do responsável legal."
        )
    if (
        payload.guardian_relationship == "Outro responsável legal"
        and not (payload.guardian_other_relationship or "").strip()
    ):
        field_error(
            "guardian_other_relationship",
            "Descreva o parentesco do responsável legal.",
        )
