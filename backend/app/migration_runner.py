"""Tracked migration bootstrap for deployed PostgreSQL databases.

An imported database may already contain the historical schema without a
migration journal. In that case we audit migration-defined tables/columns,
repair the one legacy table that is known to be absent from ORM metadata, and
stamp the historical migrations as the baseline. Future migration files are
then executed normally, once each.
"""
from __future__ import annotations

from pathlib import Path
import re
from typing import Iterable

from sqlalchemy.engine import Engine

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "migrations"
BASELINE_MARKER = "__historical_schema_baselined__"

TRACKING_SQL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    filename TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""

# This table is required by registration-number generation but is not declared
# in Base.metadata. Its canonical definition comes from migration 0011.
ANNUAL_REGISTRATION_COUNTER_SQL = """
CREATE TABLE IF NOT EXISTS annual_registration_counters (
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    last_value INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (establishment_id, academic_year_id),
    CONSTRAINT fk_registration_counter_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_registration_counter_year_tenant
        FOREIGN KEY (academic_year_id, establishment_id)
        REFERENCES academic_years(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT ck_registration_counter_value CHECK (last_value >= 0)
);
"""

CREATE_TABLE_RE = re.compile(
    r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:(?:\"?public\"?)\.)?\"?([a-zA-Z0-9_]+)\"?",
    re.IGNORECASE,
)
ADD_COLUMN_RE = re.compile(
    r"ALTER\s+TABLE\s+\"?([a-zA-Z0-9_]+)\"?\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+\"?([a-zA-Z0-9_]+)\"?",
    re.IGNORECASE,
)


def _migration_files() -> list[Path]:
    return sorted(MIGRATIONS_DIR.glob("*.sql"))


def _created_tables(files: Iterable[Path]) -> set[str]:
    tables: set[str] = set()
    for path in files:
        tables.update(CREATE_TABLE_RE.findall(path.read_text(encoding="utf-8")))
    return tables


def _added_columns(files: Iterable[Path]) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for path in files:
        sql = path.read_text(encoding="utf-8")
        for table, column in ADD_COLUMN_RE.findall(sql):
            result.setdefault(table, set()).add(column)
    return result


def _raw_pg_connection(engine: Engine):
    raw = engine.raw_connection()
    driver = getattr(raw, "driver_connection", None)
    if driver is None:
        driver = raw.connection
    return raw, driver


def _execute_script(driver, sql: str) -> None:
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


def _existing_columns(driver) -> dict[str, set[str]]:
    with driver.cursor() as cursor:
        cursor.execute(
            """
            SELECT table_name, column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
            """
        )
        result: dict[str, set[str]] = {}
        for table, column in cursor.fetchall():
            result.setdefault(table, set()).add(column)
        return result


def _missing_columns(
    expected: dict[str, set[str]], actual: dict[str, set[str]]
) -> list[str]:
    missing: list[str] = []
    for table, columns in sorted(expected.items()):
        for column in sorted(columns):
            if column not in actual.get(table, set()):
                missing.append(f"{table}.{column}")
    return missing


def _is_baselined(driver) -> bool:
    with driver.cursor() as cursor:
        cursor.execute(
            "SELECT 1 FROM schema_migrations WHERE filename = %s",
            (BASELINE_MARKER,),
        )
        return cursor.fetchone() is not None


def _stamp_historical_baseline(driver, files: list[Path]) -> None:
    with driver.cursor() as cursor:
        for path in files:
            cursor.execute(
                """
                INSERT INTO schema_migrations(filename)
                VALUES (%s)
                ON CONFLICT (filename) DO NOTHING
                """,
                (path.name,),
            )
        cursor.execute(
            """
            INSERT INTO schema_migrations(filename)
            VALUES (%s)
            ON CONFLICT (filename) DO NOTHING
            """,
            (BASELINE_MARKER,),
        )


def _audit_and_baseline_imported_schema(driver, files: list[Path]) -> None:
    expected_tables = _created_tables(files)
    before = _existing_tables(driver)
    missing_before = sorted(expected_tables - before)

    print(
        f"[migrations] historical audit: {len(before)} public tables; "
        f"{len(missing_before)} migration-defined tables missing"
    )
    if missing_before:
        print("[migrations] missing tables before repair: " + ", ".join(missing_before))

    # The production failure identified exactly this omitted migration-only
    # table. Recreate it from the repository's canonical migration definition.
    if "annual_registration_counters" in missing_before:
        print("[migrations] repairing annual_registration_counters from migration 0011")
        _execute_script(driver, ANNUAL_REGISTRATION_COUNTER_SQL)
        driver.commit()

    after_repair = _existing_tables(driver)
    remaining_tables = sorted(expected_tables - after_repair)
    if remaining_tables:
        raise RuntimeError(
            "Historical schema audit failed; migration-defined tables still missing: "
            + ", ".join(remaining_tables)
        )

    expected_columns = _added_columns(files)
    actual_columns = _existing_columns(driver)
    missing_columns = _missing_columns(expected_columns, actual_columns)
    print(
        f"[migrations] historical column audit: "
        f"{sum(len(v) for v in expected_columns.values())} additive columns checked; "
        f"{len(missing_columns)} missing"
    )
    if missing_columns:
        raise RuntimeError(
            "Historical schema audit failed; migration-defined columns missing: "
            + ", ".join(missing_columns)
        )

    _stamp_historical_baseline(driver, files)
    driver.commit()
    print(
        f"[migrations] historical baseline accepted: {len(after_repair)} public tables; "
        "all migration-defined tables and additive columns present"
    )


def apply_pending_migrations(engine: Engine) -> None:
    files = _migration_files()
    if not files:
        print("[migrations] no SQL migration files found")
        return

    raw, driver = _raw_pg_connection(engine)
    try:
        _execute_script(driver, TRACKING_SQL)
        driver.commit()

        if not _is_baselined(driver):
            _audit_and_baseline_imported_schema(driver, files)
            return

        with driver.cursor() as cursor:
            cursor.execute(
                "SELECT filename FROM schema_migrations WHERE filename <> %s",
                (BASELINE_MARKER,),
            )
            applied = {row[0] for row in cursor.fetchall()}

        pending = [path for path in files if path.name not in applied]
        if not pending:
            print("[migrations] no pending migrations")
            return

        for path in pending:
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

        print(f"[migrations] applied {len(pending)} pending migration(s)")
    finally:
        raw.close()
