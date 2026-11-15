"""Definições não sensíveis da equipe ampliada de demonstração."""

from dataclasses import dataclass


@dataclass(frozen=True)
class ExtendedDemoStaff:
    key: str
    name: str
    role: str
    profession: str
    specialty: str | None = None
    registration: str | None = None


EXTENDED_DEMO_STAFF = (
    ExtendedDemoStaff("ana_paula_martins", "Ana Paula Martins", "recepcao", "Recepção"),
    ExtendedDemoStaff("bruno_henrique_costa", "Bruno Henrique Costa", "recepcao", "Recepção"),
    ExtendedDemoStaff("camila_rodrigues_silva", "Camila Rodrigues Silva", "recepcao", "Recepção"),
    ExtendedDemoStaff(
        "juliana_ferreira_lima", "Juliana Ferreira Lima", "enfermagem",
        "Enfermagem", "Clínica Geral", "COREN-DEMO-201",
    ),
    ExtendedDemoStaff(
        "rafael_oliveira_santos", "Rafael Oliveira Santos", "enfermagem",
        "Enfermagem", "Clínica Geral", "COREN-DEMO-202",
    ),
    ExtendedDemoStaff(
        "patricia_almeida_souza", "Patrícia Almeida Souza", "enfermagem",
        "Enfermagem", "Clínica Geral", "COREN-DEMO-203",
    ),
    ExtendedDemoStaff(
        "lucas_mendes", "Dr. Lucas Mendes", "medico", "Médico",
        "Clínica Geral", "CRM-DEMO-201",
    ),
    ExtendedDemoStaff(
        "mariana_costa", "Dra. Mariana Costa", "medico", "Médica",
        "Cardiologia", "CRM-DEMO-202",
    ),
    ExtendedDemoStaff(
        "pedro_henrique_alves", "Dr. Pedro Henrique Alves", "medico", "Médico",
        "Pediatria", "CRM-DEMO-203",
    ),
    ExtendedDemoStaff(
        "beatriz_rodrigues", "Dra. Beatriz Rodrigues", "medico", "Médica",
        "Ginecologia", "CRM-DEMO-204",
    ),
    ExtendedDemoStaff(
        "carolina_fernandes", "Carolina Fernandes", "medico", "Dentista",
        "Odontologia", "CRO-DEMO-201",
    ),
    ExtendedDemoStaff(
        "gabriel_ribeiro", "Gabriel Ribeiro", "medico", "Dentista",
        "Odontologia", "CRO-DEMO-202",
    ),
)
