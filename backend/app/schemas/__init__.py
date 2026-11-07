from datetime import date, datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from app.core.specialty import canonical_specialty_name

PriorityConditionName = Literal["pcd", "gestante", "lactante"]


class LoginRequest(BaseModel):
    document: str = Field(min_length=3)
    password: str = Field(min_length=6)


class UserResponse(BaseModel):
    id: int
    name: str
    role: str
    permissions: list[str] = []


class RegistrationResponse(UserResponse):
    email: EmailStr
    verification_token: str = Field(min_length=32)
    resend_after_seconds: int = 60
    message: str = "Cadastro iniciado. Confirme seu e-mail para entrar."


class PatientProfile(BaseModel):
    name: str
    masked_cpf: str
    cns: str | None = None
    birth_date: date | None = None
    email: str
    phone: str | None = None
    age: int | None = None
    legal_priority: str = "geral"
    priority_reason: str = "Sem prioridade legal"
    priority_conditions: list[dict] = Field(default_factory=list)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse
    permissions: list[str] = []


class MedicalCompletion(BaseModel):
    summary: str = Field(min_length=3, max_length=2000)

    @field_validator("summary", mode="before")
    @classmethod
    def trim_summary(cls, value):
        return value.strip() if isinstance(value, str) else value


class MedicalCareResponse(BaseModel):
    id: int
    scheduled_at: datetime
    patient: str
    age: int | None = None
    specialty: str
    professional: str
    professional_id: int
    status: str
    legal_priority: str
    priority_reason: str
    risk_classification: str
    risk_label: str
    triage_complaint: str
    vital_signs: str
    triage_observation: str | None = None
    arrived_at: datetime
    triaged_at: datetime
    called_at: datetime | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    care_summary: str | None = None

    @field_validator("specialty", mode="before")
    @classmethod
    def canonicalize_specialty(cls, value):
        return canonical_specialty_name(value) if isinstance(value, str) else value


class InternalUserCreate(BaseModel):
    name: str = Field(min_length=3, max_length=80)
    cpf: str = Field(min_length=11, max_length=32)
    email: EmailStr
    role: Literal["recepcao", "enfermagem", "medico", "profissional"]
    password: str = Field(min_length=8, max_length=128)
    password_confirmation: str = Field(min_length=8, max_length=128)
    active: bool = True
    professional_registration: str | None = Field(default=None, max_length=40)
    specialty_id: int | None = None
    can_triage: bool = False


class InternalUserUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=3, max_length=80)
    email: EmailStr | None = None
    role: Literal["recepcao", "enfermagem", "medico", "profissional"] | None = None
    professional_registration: str | None = Field(default=None, max_length=40)
    specialty_id: int | None = None
    can_triage: bool | None = None


class AccessReset(BaseModel):
    password: str = Field(min_length=8, max_length=128)
    password_confirmation: str = Field(min_length=8, max_length=128)


class InternalUserResponse(BaseModel):
    id: int
    name: str
    masked_cpf: str
    email: str
    role: str
    active: bool
    professional_registration: str | None = None
    specialty_id: int | None = None
    specialty: str | None = None
    can_triage: bool = False
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @field_validator("specialty", mode="before")
    @classmethod
    def canonicalize_specialty(cls, value):
        return canonical_specialty_name(value) if isinstance(value, str) else value


class DoctorCreate(BaseModel):
    name: str = Field(min_length=3, max_length=80)
    cpf: str = Field(min_length=11, max_length=32)
    password: str = Field(min_length=8, max_length=128)
    password_confirmation: str = Field(min_length=8, max_length=128)
    active: bool = True


class DoctorUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=3, max_length=80)
    cpf: str | None = Field(default=None, min_length=11, max_length=32)
    active: bool | None = None


class DoctorResponse(BaseModel):
    id: int
    name: str
    masked_cpf: str
    role: Literal["medico"] = "medico"
    active: bool
    specialty: str = "Clínica Geral"


class PatientRegistration(BaseModel):
    name: str = Field(min_length=3, max_length=80)
    cpf: str = Field(min_length=11, max_length=32)
    cns: str | None = None  # legado aceito e deliberadamente ignorado
    birth_date: date
    email: EmailStr
    phone: str = Field(min_length=10, max_length=16)
    password: str = Field(min_length=8, max_length=128)
    password_confirmation: str = Field(min_length=8, max_length=128)
    priority: str | None = None
    priority_conditions: list[PriorityConditionName] = Field(default_factory=list)
    guardian_name: str | None = Field(default=None, max_length=120)
    guardian_cpf: str | None = Field(default=None, max_length=32)
    guardian_birth_date: date | None = None
    guardian_relationship: str | None = Field(default=None, max_length=40)
    guardian_other_relationship: str | None = Field(default=None, max_length=80)
    guardian_phone: str | None = Field(default=None, max_length=16)
    guardian_email: EmailStr | None = None

    @field_validator("name", "guardian_name", mode="before")
    @classmethod
    def normalize_spaces(cls, value):
        return " ".join(value.split()) if isinstance(value, str) else value

    @field_validator("email", "guardian_email", mode="before")
    @classmethod
    def trim_email(cls, value):
        return value.strip().lower() if isinstance(value, str) else value


class PatientPriorityUpdate(BaseModel):
    """Paciente pode apenas declarar condições; estado e auditoria são internos."""

    model_config = ConfigDict(extra="forbid")
    priority: str | None = None
    priority_conditions: list[PriorityConditionName] = Field(default_factory=list)


class PriorityValidationInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["confirmada", "rejeitada"]


class EmailPasswordRecoveryRequest(BaseModel):
    email: EmailStr

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value):
        return value.strip().lower() if isinstance(value, str) else value


class EmailPasswordRecoveryVerify(EmailPasswordRecoveryRequest):
    code: str = Field(pattern=r"^[0-9]{6}$")


class EmailVerificationRequest(BaseModel):
    email: EmailStr

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value):
        return value.strip().lower() if isinstance(value, str) else value


class EmailVerificationConfirm(EmailVerificationRequest):
    code: str = Field(pattern=r"^[0-9]{6}$")


class EmailVerificationCorrection(BaseModel):
    verification_token: str = Field(min_length=1)
    new_email: EmailStr

    @field_validator("new_email", mode="before")
    @classmethod
    def normalize_email(cls, value):
        return value.strip().lower() if isinstance(value, str) else value


class EmailPasswordReset(BaseModel):
    recovery_token: str = Field(min_length=1)
    new_password: str = Field(min_length=8, max_length=128)
    confirm_new_password: str = Field(min_length=8, max_length=128)


class PasswordChange(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    password: str = Field(min_length=8, max_length=128)


class AppointmentResponse(BaseModel):
    id: int
    specialty: str
    professional: str
    doctor_id: int
    scheduled_at: datetime
    status: str
    risk_classification: str | None = None
    location: str | None = None
    message: str | None = None

    @field_validator("specialty", mode="before")
    @classmethod
    def canonicalize_specialty(cls, value):
        return canonical_specialty_name(value) if isinstance(value, str) else value


class PatientSummary(BaseModel):
    patient: PatientProfile
    next_appointment: AppointmentResponse | None = None


class CatalogItem(BaseModel):
    id: int
    name: str

    @field_validator("name", mode="before")
    @classmethod
    def canonicalize_name(cls, value):
        return canonical_specialty_name(value) if isinstance(value, str) else value


class AppointmentCreate(BaseModel):
    doctor_id: int
    specialty: str = Field(min_length=3, max_length=80)
    scheduled_at: datetime

    @field_validator("specialty", mode="before")
    @classmethod
    def canonicalize_specialty(cls, value):
        return canonical_specialty_name(value) if isinstance(value, str) else value


class RescheduleRequest(BaseModel):
    doctor_id: int
    scheduled_at: datetime


class AvailableSlot(BaseModel):
    doctor_id: int
    doctor_name: str
    specialty: str
    scheduled_at: datetime

    @field_validator("specialty", mode="before")
    @classmethod
    def canonicalize_specialty(cls, value):
        return canonical_specialty_name(value) if isinstance(value, str) else value


class CalendarSlot(AvailableSlot):
    availability: Literal["available", "unavailable", "already_scheduled"]
    label: Literal["Disponível", "Indisponível", "Já agendado"]
    selectable: bool
