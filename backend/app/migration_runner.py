"""Apply SQL migrations from backend/migrations safely at application startup.

The runner is intentionally additive:
- it never drops tables or columns;
- it records successful migrations in schema_migrations;
- each migration is committed independently;
- a failed migration is rolled back and prevents startup.
"""
from __future__ import annotations

from pathlib import Path
import re
from typing import Iterable

from sqlalchemy.engine import Engine

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "migrations"

BASELINE_INDEX_SQL = """
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_school_cycles_establishment_code
  ON school_cycles (establishment_id, code);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_school_levels_establishment_cycle_code
  ON school_levels (establishment_id, cycle_id, code);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_school_cycles_id_establishment
  ON school_cycles (id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_school_levels_id_cycle_establishment
  ON school_levels (id, cycle_id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_academic_years_id_establishment
  ON academic_years (id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_classes_id_establishment
  ON classes (id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_students_id_establishment
  ON students (id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_teachers_id_establishment
  ON teachers (id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_subjects_id_establishment
  ON subjects (id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_school_series_id_establishment
  ON school_series (id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_school_directions_id_establishment
  ON school_directions (id, establishment_id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_school_directions_establishment_code
  ON school_directions (establishment_id, code);
CREATE UNIQUE INDEX IF NOT EXISTS ci_uq_school_direction_cycles_establishment_cycle
  ON school_direction_cycles (establishment_id, cycle_id);
"""

TRACKING_SQL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    filename TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""

CREATE_TABLE_RE = re.compile(
    r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:(?:\"?public\"?)\.)?\"?([a-zA-Z0-9_]+)\"?",
    re.IGNORECASE,
)


def _migration_files() -> list[Path]:
    return sorted(MIGRATIONS_DIR.glob("*.sql"))


def _created_tables(files: Iterable[Path]) -> set[str]:
    tables: set[str] = set()
    for path in files:
        tables.update(CREATE_TABLE_RE.findall(path.read_text(encoding="utf-8")))
    return tables


def _raw_pg_connection(engine: Engine):
    raw = engine.raw_connection()
    driver = getattr(raw, "driver_connection", None)
    if driver is None:
        driver = raw.connection
    return raw, driver


def _execute_script(driver, sql: str) -> None:
    # psycopg 3 accepts multi-statement SQL with the simple query protocol when
    # prepare=False. Migration files include DO $$ blocks, so naive semicolon
    # splitting would be unsafe.
    with driver.cursor() as cursor:
        cursor.execute(sql, prepare=False)


def _existing_tables(driver) -> set[str]:
    with driver.cursor() as cursor:
        cursor.execute(
            """
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            """
        )
        return {row[0] for row in cursor.fetchall()}


def apply_pending_migrations(engine: Engine) -> None:
    files = _migration_files()
    if not files:
        print("[migrations] no SQL migration files found")
        return

    raw, driver = _raw_pg_connection(engine)
    try:
        _execute_script(driver, TRACKING_SQL)
        driver.commit()

        expected_tables = _created_tables(files)
        before = _existing_tables(driver)
        missing_before = sorted(expected_tables - before)
        print(
            f"[migrations] preflight: {len(before)} public tables; "
            f"{len(missing_before)} migration-defined tables missing"
        )
        if missing_before:
            print("[migrations] missing before apply: " + ", ".join(missing_before))

        # Match the proven GitHub Actions migration order: ORM schema first,
        # then composite baseline indexes, then the historical SQL migrations.
        # Migration 0004 uses ON CONFLICT(establishment_id, code) against tables
        # that Base.metadata.create_all() may have created without these unique
        # constraints, so the alignment must happen before 0004.
        try:
            _execute_script(driver, BASELINE_INDEX_SQL)
            driver.commit()
        except Exception:
            driver.rollback()
            print("[migrations] FAILED baseline-index alignment")
            raise

        with driver.cursor() as cursor:
            cursor.execute("SELECT filename FROM schema_migrations")
            applied = {row[0] for row in cursor.fetchall()}

        for path in files:
            if path.name in applied:
                print(f"[migrations] skip {path.name} (already recorded)")
                continue

            sql = path.read_text(encoding="utf-8")
            print(f"[migrations] applying {path.name}")
            try:
                _execute_script(driver, sql)
                with driver.cursor() as cursor:
                    cursor.execute(
                        "INSERT INTO schema_migrations(filename) VALUES (%s)",
                        (path.name,),
                    )
                driver.commit()
            except Exception:
                driver.rollback()
                print(f"[migrations] FAILED {path.name}; transaction rolled back")
                raise

        after = _existing_tables(driver)
        missing_after = sorted(expected_tables - after)
        print(
            f"[migrations] postflight: {len(after)} public tables; "
            f"{len(missing_after)} migration-defined tables missing"
        )
        if missing_after:
            raise RuntimeError(
                "Migration verification failed; missing tables: "
                + ", ".join(missing_after)
            )

        if "annual_registration_counters" not in after:
            raise RuntimeError(
                "Migration verification failed: annual_registration_counters missing"
            )

        print("[migrations] all SQL migrations verified")
    finally:
        raw.close()
