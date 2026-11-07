from datetime import datetime
from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship, validates
from app.core.database import Base
from app.core.clock import now_sao_paulo_naive, now_utc_naive
from app.core.risk import RISK_LEVELS
from app.core.specialty import specialty_storage_name


def _official_risk(value: str | None) -> str | None:
    if value is not None and value not in RISK_LEVELS:
        raise ValueError("Classificação de risco inválida")
    return value

class User(Base):
    __tablename__ = "usuarios"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    nome: Mapped[str] = mapped_column(String(120))
    cpf: Mapped[str] = mapped_column(String(11), unique=True, index=True, nullable=False)
    cns: Mapped[str | None] = mapped_column(String(15), unique=True, index=True, nullable=True)
    data_nascimento: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    email: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    email_verificado: Mapped[bool] = mapped_column(Boolean, default=False)
    telefone: Mapped[str | None] = mapped_column(String(11), nullable=True)
    senha_hash: Mapped[str] = mapped_column(String(255))
    perfil: Mapped[str] = mapped_column(String(20), default="paciente")
    ativo: Mapped[bool] = mapped_column(Boolean, default=True)
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive)
    atualizado_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive, onupdate=now_utc_naive)
    token_version: Mapped[int] = mapped_column(Integer, default=0)
    criado_por: Mapped[int | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    ultima_alteracao_por: Mapped[int | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    e_prioridade: Mapped[str | None] = mapped_column(String(30), nullable=True)
    e_menor_idade: Mapped[bool] = mapped_column(Boolean, default=False)
    nome_responsavel: Mapped[str | None] = mapped_column(String(120), nullable=True)
    cpf_responsavel: Mapped[str | None] = mapped_column(String(11), nullable=True)
    data_nascimento_responsavel: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    parentesco_responsavel: Mapped[str | None] = mapped_column(String(40), nullable=True)
    outro_parentesco_responsavel: Mapped[str | None] = mapped_column(String(80), nullable=True)
    telefone_responsavel: Mapped[str | None] = mapped_column(String(11), nullable=True)
    email_responsavel: Mapped[str | None] = mapped_column(String(120), nullable=True)
    consultas_paciente = relationship("Appointment", foreign_keys="Appointment.paciente_id", back_populates="paciente")
    consultas_medico = relationship("Appointment", foreign_keys="Appointment.medico_id", back_populates="medico")
    perfil_profissional = relationship("ProfessionalProfile", foreign_keys="ProfessionalProfile.usuario_id", uselist=False, back_populates="usuario")
    condicoes_prioritarias = relationship(
        "PriorityCondition", foreign_keys="PriorityCondition.paciente_id",
        back_populates="paciente", cascade="all, delete-orphan",
    )


class PriorityCondition(Base):
    """Estado atual de uma condição autodeclarada que exige validação presencial."""

    __tablename__ = "condicoes_prioritarias"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    paciente_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    condicao: Mapped[str] = mapped_column(String(20), index=True)
    status: Mapped[str] = mapped_column(String(20), default="pendente", index=True)
    informada_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive)
    validada_por: Mapped[int | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    validada_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    paciente = relationship("User", foreign_keys=[paciente_id], back_populates="condicoes_prioritarias")
    responsavel_validacao = relationship("User", foreign_keys=[validada_por])
    __table_args__ = (
        UniqueConstraint("paciente_id", "condicao", name="uq_condicao_prioritaria_paciente"),
    )


class PriorityConditionHistory(Base):
    """Trilha imutável das declarações, confirmações e rejeições."""

    __tablename__ = "historico_condicoes_prioritarias"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    condicao_prioritaria_id: Mapped[int] = mapped_column(
        ForeignKey("condicoes_prioritarias.id"), index=True
    )
    status_anterior: Mapped[str | None] = mapped_column(String(20), nullable=True)
    status_novo: Mapped[str] = mapped_column(String(20), index=True)
    alterado_por: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive, index=True)

class ProfessionalSchedule(Base):
    __tablename__ = "agendas_profissionais"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    medico_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    data_horario: Mapped[datetime] = mapped_column(DateTime, index=True)
    bloqueado: Mapped[bool] = mapped_column(Boolean, default=False)
    especialidade: Mapped[str] = mapped_column(String(80), default="Clínica Geral")
    medico = relationship("User")
    __table_args__ = (UniqueConstraint("medico_id", "data_horario", name="uq_agenda_medico_horario"),)

    @validates("especialidade")
    def canonicalize_specialty(self, _key: str, value: str) -> str:
        return specialty_storage_name(value)

class Appointment(Base):
    __tablename__ = "consultas"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    paciente_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    medico_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    especialidade: Mapped[str] = mapped_column(String(80), index=True)
    data_horario: Mapped[datetime] = mapped_column(DateTime, index=True)
    status: Mapped[str] = mapped_column(String(25), default="agendado")
    classificacao_risco: Mapped[str | None] = mapped_column(String(30), nullable=True)
    chegada_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    chegada_por: Mapped[int | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    falta_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    triagem_por: Mapped[int | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    triagem_dados: Mapped[str | None] = mapped_column(String(2000), nullable=True)
    triagem_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    chamado_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    iniciado_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    concluido_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    atendimento_medico_id: Mapped[int | None] = mapped_column(ForeignKey("usuarios.id"), nullable=True)
    resumo_atendimento: Mapped[str | None] = mapped_column(Text, nullable=True)
    paciente = relationship("User", foreign_keys=[paciente_id], back_populates="consultas_paciente")
    medico = relationship("User", foreign_keys=[medico_id], back_populates="consultas_medico")

    @validates("classificacao_risco")
    def validate_risk(self, _key: str, value: str | None) -> str | None:
        return _official_risk(value)

    @validates("especialidade")
    def canonicalize_specialty(self, _key: str, value: str) -> str:
        return specialty_storage_name(value)

class Guardian(Base):
    __tablename__ = 'responsaveis'
    id: Mapped[int] = mapped_column(primary_key=True)
    nome: Mapped[str] = mapped_column(String(80))
    cpf: Mapped[str] = mapped_column(String(11), unique=True)
    telefone: Mapped[str | None] = mapped_column(String(11), nullable=True)
    email: Mapped[str | None] = mapped_column(String(120), nullable=True)

class PatientGuardian(Base):
    __tablename__ = 'pacientes_responsaveis'
    paciente_id: Mapped[int] = mapped_column(ForeignKey('usuarios.id'), primary_key=True)
    responsavel_id: Mapped[int] = mapped_column(ForeignKey('responsaveis.id'), primary_key=True)
    parentesco: Mapped[str] = mapped_column(String(80))

class PasswordRecovery(Base):
    __tablename__ = 'recuperacao_senha'
    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey('usuarios.id'), index=True)
    codigo_hash: Mapped[str] = mapped_column(String(64))
    expira_em: Mapped[datetime] = mapped_column(DateTime)
    tentativas: Mapped[int] = mapped_column(default=0)
    utilizado: Mapped[bool] = mapped_column(default=False)
    verificado: Mapped[bool] = mapped_column(default=False)
    criado_em: Mapped[datetime] = mapped_column(default=now_utc_naive)


class EmailVerification(Base):
    __tablename__ = "verificacoes_email"
    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    codigo_hash: Mapped[str] = mapped_column(String(64))
    expira_em: Mapped[datetime] = mapped_column(DateTime, index=True)
    tentativas: Mapped[int] = mapped_column(default=0)
    utilizado: Mapped[bool] = mapped_column(default=False)
    token_correcao_hash: Mapped[str | None] = mapped_column(
        String(64), nullable=True, index=True
    )
    criado_em: Mapped[datetime] = mapped_column(default=now_utc_naive, index=True)

class RateLimit(Base):
    __tablename__ = 'limites_tentativas'
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    attempts: Mapped[int] = mapped_column(default=0)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)

class Specialty(Base):
    __tablename__ = 'especialidades'
    id: Mapped[int] = mapped_column(primary_key=True)
    nome: Mapped[str] = mapped_column(String(80), unique=True)
    ativo: Mapped[bool] = mapped_column(Boolean, default=True)

    @validates("nome")
    def canonicalize_name(self, _key: str, value: str) -> str:
        return specialty_storage_name(value)


class ProfessionalProfile(Base):
    __tablename__ = "perfis_profissionais"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), unique=True, index=True)
    registro_profissional: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    especialidade_id: Mapped[int] = mapped_column(ForeignKey("especialidades.id"), index=True)
    autorizado_triagem: Mapped[bool] = mapped_column(Boolean, default=False)
    ativo: Mapped[bool] = mapped_column(Boolean, default=True)
    usuario = relationship("User", foreign_keys=[usuario_id], back_populates="perfil_profissional")
    especialidade = relationship("Specialty")


class ScheduleGrid(Base):
    __tablename__ = "grades_atendimento"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    profissional_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    especialidade_id: Mapped[int] = mapped_column(ForeignKey("especialidades.id"), index=True)
    data: Mapped[datetime] = mapped_column(DateTime, index=True)
    horario_inicio: Mapped[str] = mapped_column(String(5))
    horario_fim: Mapped[str] = mapped_column(String(5))
    duracao_minutos: Mapped[int] = mapped_column(Integer)
    quantidade_vagas: Mapped[int] = mapped_column(Integer, default=1)
    intervalo_inicio: Mapped[str | None] = mapped_column(String(5), nullable=True)
    intervalo_fim: Mapped[str | None] = mapped_column(String(5), nullable=True)
    ativo: Mapped[bool] = mapped_column(Boolean, default=True)
    criado_por: Mapped[int] = mapped_column(ForeignKey("usuarios.id"))
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive)
    atualizado_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive, onupdate=now_utc_naive)
    profissional = relationship("User", foreign_keys=[profissional_id])
    especialidade = relationship("Specialty")


class ScheduleBlock(Base):
    __tablename__ = "bloqueios_agenda"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    profissional_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    inicio: Mapped[datetime] = mapped_column(DateTime, index=True)
    fim: Mapped[datetime] = mapped_column(DateTime, index=True)
    motivo: Mapped[str] = mapped_column(String(120))
    criado_por: Mapped[int] = mapped_column(ForeignKey("usuarios.id"))
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive)


class AppointmentStatusHistory(Base):
    __tablename__ = "historico_status_consultas"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    consulta_id: Mapped[int] = mapped_column(ForeignKey("consultas.id"), index=True)
    status_anterior: Mapped[str | None] = mapped_column(String(25), nullable=True)
    status_novo: Mapped[str] = mapped_column(String(25))
    alterado_por: Mapped[int] = mapped_column(ForeignKey("usuarios.id"))
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive, index=True)


class RiskClassification(Base):
    __tablename__ = "classificacoes_risco"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    consulta_id: Mapped[int] = mapped_column(
        ForeignKey("consultas.id"), unique=True, index=True
    )
    profissional_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    nivel_risco: Mapped[str] = mapped_column(String(20), index=True)
    queixa_principal: Mapped[str | None] = mapped_column(String(500), nullable=True)
    sinais_vitais: Mapped[str | None] = mapped_column(String(500), nullable=True)
    observacao: Mapped[str | None] = mapped_column(String(500), nullable=True)
    classificado_em: Mapped[datetime] = mapped_column(DateTime, default=now_sao_paulo_naive)
    consulta = relationship("Appointment")
    profissional = relationship("User")

    @validates("nivel_risco")
    def validate_risk(self, _key: str, value: str) -> str:
        return _official_risk(value)  # type: ignore[return-value]


class AuditLog(Base):
    __tablename__ = "auditoria_administrativa"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    acao: Mapped[str] = mapped_column(String(80), index=True)
    tipo_registro: Mapped[str] = mapped_column(String(50), index=True)
    registro_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    detalhes: Mapped[str | None] = mapped_column(Text, nullable=True)
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=now_utc_naive, index=True)
