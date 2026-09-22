-- Additive multi-direction administration model.
-- Existing establishments, cycles, users and historical data are preserved.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS school_directions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL,
  code varchar(64) NOT NULL,
  name varchar(120) NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fk_school_directions_establishment
    FOREIGN KEY (establishment_id) REFERENCES establishments(id),
  CONSTRAINT ck_school_directions_status
    CHECK (status IN ('active', 'inactive')),
  CONSTRAINT uq_school_directions_establishment_code
    UNIQUE (establishment_id, code),
  CONSTRAINT uq_school_directions_id_establishment
    UNIQUE (id, establishment_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_school_directions_establishment_name
  ON school_directions (establishment_id, lower(name));

CREATE TABLE IF NOT EXISTS school_direction_cycles (
  direction_id uuid NOT NULL,
  establishment_id uuid NOT NULL,
  cycle_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (direction_id, cycle_id),
  CONSTRAINT fk_direction_cycles_direction_tenant
    FOREIGN KEY (direction_id, establishment_id)
    REFERENCES school_directions(id, establishment_id) ON DELETE CASCADE,
  CONSTRAINT fk_direction_cycles_cycle_tenant
    FOREIGN KEY (cycle_id, establishment_id)
    REFERENCES school_cycles(id, establishment_id),
  CONSTRAINT uq_school_direction_cycle
    UNIQUE (establishment_id, cycle_id)
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS direction_id uuid NULL;
ALTER TABLE students ADD COLUMN IF NOT EXISTS created_direction_id uuid NULL;
ALTER TABLE guardians ADD COLUMN IF NOT EXISTS created_direction_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_users_direction_tenant'
  ) THEN
    ALTER TABLE users ADD CONSTRAINT fk_users_direction_tenant
      FOREIGN KEY (direction_id, establishment_id)
      REFERENCES school_directions(id, establishment_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_guardians_created_direction_tenant'
  ) THEN
    ALTER TABLE guardians ADD CONSTRAINT fk_guardians_created_direction_tenant
      FOREIGN KEY (created_direction_id, establishment_id)
      REFERENCES school_directions(id, establishment_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_students_created_direction_tenant'
  ) THEN
    ALTER TABLE students ADD CONSTRAINT fk_students_created_direction_tenant
      FOREIGN KEY (created_direction_id, establishment_id)
      REFERENCES school_directions(id, establishment_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_school_directions_establishment
  ON school_directions(establishment_id);
CREATE INDEX IF NOT EXISTS ix_school_direction_cycles_cycle
  ON school_direction_cycles(cycle_id);
CREATE INDEX IF NOT EXISTS ix_users_direction
  ON users(direction_id) WHERE direction_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_admin_direction
  ON users(direction_id)
  WHERE direction_id IS NOT NULL AND role = 'admin';
CREATE INDEX IF NOT EXISTS ix_students_created_direction
  ON students(created_direction_id) WHERE created_direction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_guardians_created_direction
  ON guardians(created_direction_id) WHERE created_direction_id IS NOT NULL;

-- Create only unambiguous default directions from configured cycles.
-- Existing administrators remain unassigned until the Super Admin explicitly
-- chooses their direction, preserving their current access during migration.
INSERT INTO school_directions(establishment_id, code, name)
SELECT DISTINCT establishment_id, 'MATERNELLE_PRIMAIRE',
       'Direction Maternelle & Primaire'
FROM school_cycles
WHERE code IN ('MATERNELLE', 'PRIMAIRE')
ON CONFLICT (establishment_id, code) DO NOTHING;

INSERT INTO school_directions(establishment_id, code, name)
SELECT DISTINCT establishment_id, 'COLLEGE', 'Direction Collège'
FROM school_cycles WHERE code = 'COLLEGE'
ON CONFLICT (establishment_id, code) DO NOTHING;

INSERT INTO school_directions(establishment_id, code, name)
SELECT DISTINCT establishment_id, 'LYCEE', 'Direction Lycée'
FROM school_cycles WHERE code = 'LYCEE'
ON CONFLICT (establishment_id, code) DO NOTHING;

INSERT INTO school_direction_cycles(direction_id, establishment_id, cycle_id)
SELECT direction.id, cycle.establishment_id, cycle.id
FROM school_cycles cycle
JOIN school_directions direction
  ON direction.establishment_id = cycle.establishment_id
 AND direction.code = CASE
   WHEN cycle.code IN ('MATERNELLE', 'PRIMAIRE') THEN 'MATERNELLE_PRIMAIRE'
   WHEN cycle.code = 'COLLEGE' THEN 'COLLEGE'
   WHEN cycle.code = 'LYCEE' THEN 'LYCEE'
 END
WHERE cycle.code IN ('MATERNELLE', 'PRIMAIRE', 'COLLEGE', 'LYCEE')
ON CONFLICT (establishment_id, cycle_id) DO NOTHING;
