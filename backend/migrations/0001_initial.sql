CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- The application database already owns its domain tables through Alembic.
-- This table only stores the Flutter-compatible API projection; it does not
-- replace or alter the existing users, students, classes, etc. tables.
CREATE TABLE IF NOT EXISTS api_resources (
  id text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('establishments','academic-years','students','teachers','classes','subjects','evaluations','grades')),
  school_id text NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (kind, id)
);
CREATE INDEX IF NOT EXISTS ix_api_resources_kind_school ON api_resources(kind, school_id);
