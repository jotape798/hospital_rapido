"""Comando explícito para incluir a equipe fictícia ampliada da demonstração."""

from datetime import datetime
from pathlib import Path
import sqlite3

from app.core.database import SessionLocal, engine
from app.core.extended_demo_staff import EXTENDED_DEMO_STAFF
from app.main import migrate_database
from app.services.extended_demo_seed import ensure_extended_demo_staff


ROOT = Path(__file__).resolve().parent
ACCESS_FILE = ROOT / "profissionais_demo.env.local"


def backup_sqlite() -> Path | None:
    if engine.url.get_backend_name() != "sqlite" or engine.url.database in {None, ":memory:"}:
        return None
    source = Path(engine.url.database).resolve()
    if not source.exists():
        return None
    destination = (
        source.parent
        / "backups"
        / f"{source.stem}.pre-profissionais-demo.{datetime.now():%Y%m%d-%H%M%S%f}.bak"
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(source) as source_db, sqlite3.connect(destination) as backup_db:
        source_db.backup(backup_db)
    return destination


def main() -> None:
    backup = backup_sqlite()
    migrate_database()
    with SessionLocal() as db:
        try:
            report = ensure_extended_demo_staff(db, ACCESS_FILE)
            db.commit()
        except Exception:
            db.rollback()
            raise

    print("Equipe fictícia ampliada preparada sem envio de e-mails.")
    for role in ("recepcao", "enfermagem", "medico"):
        print(f"- {role}: {report.created_by_role.get(role, 0)} criada(s) nesta execução")
    print(f"- contas já existentes e preservadas: {report.existing_users}")
    print(f"- especialidades criadas: {report.specialties_created}")
    print(f"- grades criadas: {report.grids_created}")
    print(f"- horários criados: {report.slots_created}")
    print(f"Backup: {backup or 'não aplicável'}")
    print(f"Instruções locais de acesso: {report.access_file}")
    print("Profissionais de atendimento:")
    for spec in EXTENDED_DEMO_STAFF:
        if spec.role == "medico":
            print(f"- {spec.name}: {spec.profession} — {spec.specialty}")


if __name__ == "__main__":
    main()
