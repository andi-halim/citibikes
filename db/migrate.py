"""
Applies pending SQL migrations from the migrations/ directory in version order.
Tracks applied migrations in the schema_migrations table.

Usage:
    DATABASE_URL=postgresql://... uv run python db/migrate.py
"""

import os
import sys
from pathlib import Path

import psycopg

MIGRATIONS_DIR = Path(__file__).parent.parent / "migrations"


def get_conn() -> psycopg.Connection:
    return psycopg.connect(os.environ["DATABASE_URL"])


def ensure_migrations_table(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version    TEXT PRIMARY KEY,
                applied_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
    conn.commit()


def applied_versions(conn: psycopg.Connection) -> set[str]:
    with conn.cursor() as cur:
        cur.execute("SELECT version FROM schema_migrations")
        return {row[0] for row in cur.fetchall()}


def run_migrations(conn: psycopg.Connection) -> None:
    ensure_migrations_table(conn)
    applied = applied_versions(conn)

    pending = sorted(
        f for f in MIGRATIONS_DIR.glob("*.sql") if f.stem not in applied
    )

    if not pending:
        print("No pending migrations.")
        return

    for path in pending:
        version = path.stem
        print(f"Applying {path.name} ... ", end="", flush=True)
        migration_sql = path.read_text()
        with conn.cursor() as cur:
            cur.execute(migration_sql)
            cur.execute(
                "INSERT INTO schema_migrations (version) VALUES (%s)", (version,)
            )
        conn.commit()
        print("done")


if __name__ == "__main__":
    if "DATABASE_URL" not in os.environ:
        print("Error: DATABASE_URL environment variable not set.", file=sys.stderr)
        sys.exit(1)

    with get_conn() as conn:
        run_migrations(conn)
