-- Non-destructive multi-cycle school structure.
-- Existing JSON payloads and legacy columns are preserved for compatibility.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS school_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL,
  code varchar(32) NOT NULL,
  name varchar(80) NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'active',
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fk_school_cycles_establishment
    FOREIGN KEY (establishment_id) REFERENCES establishments(id),
  CONSTRAINT ck_school_cycles_status CHECK (status IN ('active', 'inactive')),
  CONSTRAINT uq_school_cycles_establishment_code UNIQUE (establishment_id, code),
  CONSTRAINT uq_school_cycles_establishment_name UNIQUE (establishment_id, name),
  CONSTRAINT uq_school_cycles_id_establishment UNIQUE (id, establishment_id)
);

CREATE TABLE IF NOT EXISTS school_levels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL,
  cycle_id uuid NOT NULL,
  code varchar(40) NOT NULL,
  name varchar(80) NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'active',
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_school_levels_status CHECK (status IN ('active', 'inactive')),
  CONSTRAINT fk_school_levels_cycle_tenant
    FOREIGN KEY (cycle_id, establishment_id)
    REFERENCES school_cycles(id, establishment_id),
  CONSTRAINT uq_school_levels_establishment_cycle_code
    UNIQUE (establishment_id, cycle_id, code),
  CONSTRAINT uq_school_levels_establishment_cycle_name
    UNIQUE (establishment_id, cycle_id, name),
  CONSTRAINT uq_school_levels_id_cycle_establishment
    UNIQUE (id, cycle_id, establishment_id),
  CONSTRAINT uq_school_levels_id_establishment
    UNIQUE (id, establishment_id)
);

ALTER TABLE classes ADD COLUMN IF NOT EXISTS cycle_id uuid NULL;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS school_level_id uuid NULL;

ALTER TABLE api_resources ADD COLUMN IF NOT EXISTS establishment_id uuid NULL;
ALTER TABLE api_resources ADD COLUMN IF NOT EXISTS cycle_id uuid NULL;
ALTER TABLE api_resources ADD COLUMN IF NOT EXISTS school_level_id uuid NULL;
ALTER TABLE api_resources ADD COLUMN IF NOT EXISTS academic_year_id uuid NULL;

CREATE INDEX IF NOT EXISTS ix_school_cycles_establishment
  ON school_cycles(establishment_id);
CREATE INDEX IF NOT EXISTS ix_school_levels_establishment_cycle
  ON school_levels(establishment_id, cycle_id);
CREATE INDEX IF NOT EXISTS ix_api_resources_structured_school
  ON api_resources(establishment_id, kind);
CREATE INDEX IF NOT EXISTS ix_api_resources_structured_class
  ON api_resources(cycle_id, school_level_id, academic_year_id)
  WHERE kind = 'classes';

-- Resolve both public resource identifiers and legacy direct UUID school IDs.
WITH school_map AS (
  SELECT resource.id AS public_id, establishment.id AS establishment_id
  FROM api_resources resource
  JOIN establishments establishment
    ON resource.kind = 'establishments'
   AND resource.payload->>'databaseId' = establishment.id::text
  UNION
  SELECT establishment.id::text, establishment.id FROM establishments establishment
)
UPDATE api_resources resource
SET establishment_id = school_map.establishment_id
FROM school_map
WHERE resource.school_id = school_map.public_id
  AND resource.establishment_id IS DISTINCT FROM school_map.establishment_id;

-- Only unambiguous, explicitly observed cycle values are migrated.
WITH observed_cycles AS (
  SELECT DISTINCT resource.establishment_id,
    CASE lower(trim(resource.payload->>'cycle'))
      WHEN 'maternelle' THEN 'MATERNELLE'
      WHEN 'preschool' THEN 'MATERNELLE'
      WHEN 'kindergarten' THEN 'MATERNELLE'
      WHEN 'primaire' THEN 'PRIMAIRE'
      WHEN 'primary' THEN 'PRIMAIRE'
      WHEN 'collège' THEN 'COLLEGE'
      WHEN 'college' THEN 'COLLEGE'
      WHEN 'lycée' THEN 'LYCEE'
      WHEN 'lycee' THEN 'LYCEE'
      WHEN 'high_school' THEN 'LYCEE'
      ELSE NULL
    END AS code
  FROM api_resources resource
  WHERE resource.establishment_id IS NOT NULL
    AND nullif(trim(resource.payload->>'cycle'), '') IS NOT NULL
), normalized AS (
  SELECT establishment_id, code,
    CASE code
      WHEN 'MATERNELLE' THEN 'Maternelle'
      WHEN 'PRIMAIRE' THEN 'Primaire'
      WHEN 'COLLEGE' THEN 'Collège'
      WHEN 'LYCEE' THEN 'Lycée'
    END AS name,
    CASE code
      WHEN 'MATERNELLE' THEN 10
      WHEN 'PRIMAIRE' THEN 20
      WHEN 'COLLEGE' THEN 30
      WHEN 'LYCEE' THEN 40
    END AS sort_order
  FROM observed_cycles WHERE code IS NOT NULL
)
INSERT INTO school_cycles(establishment_id, code, name, sort_order)
SELECT establishment_id, code, name, sort_order FROM normalized
ON CONFLICT (establishment_id, code) DO NOTHING;

-- Resolve structured cycle references from exact mappings. A class with no
-- legacy cycle can be linked only when its establishment has exactly one
-- configured cycle.
UPDATE api_resources resource
SET cycle_id = cycle.id
FROM school_cycles cycle
WHERE resource.establishment_id = cycle.establishment_id
  AND cycle.code = CASE lower(trim(resource.payload->>'cycle'))
    WHEN 'maternelle' THEN 'MATERNELLE'
    WHEN 'preschool' THEN 'MATERNELLE'
    WHEN 'kindergarten' THEN 'MATERNELLE'
    WHEN 'primaire' THEN 'PRIMAIRE'
    WHEN 'primary' THEN 'PRIMAIRE'
    WHEN 'collège' THEN 'COLLEGE'
    WHEN 'college' THEN 'COLLEGE'
    WHEN 'lycée' THEN 'LYCEE'
    WHEN 'lycee' THEN 'LYCEE'
    WHEN 'high_school' THEN 'LYCEE'
    ELSE NULL
  END;

WITH single_cycle AS (
  SELECT establishment_id, (array_agg(id ORDER BY id))[1] AS cycle_id
  FROM school_cycles GROUP BY establishment_id HAVING count(*) = 1
)
UPDATE api_resources resource
SET cycle_id = single_cycle.cycle_id
FROM single_cycle
WHERE resource.kind = 'classes'
  AND resource.establishment_id = single_cycle.establishment_id
  AND resource.cycle_id IS NULL;

-- Migrate levels only when an exact level name is present and differs from the
-- legacy cycle label. Relational class rows provide an additional exact source.
WITH exact_levels AS (
  SELECT DISTINCT resource.establishment_id, resource.cycle_id,
         trim(resource.payload->>'level') AS name
  FROM api_resources resource
  WHERE resource.kind = 'classes'
    AND resource.establishment_id IS NOT NULL
    AND resource.cycle_id IS NOT NULL
    AND nullif(trim(resource.payload->>'level'), '') IS NOT NULL
    AND lower(trim(resource.payload->>'level')) IS DISTINCT FROM
        lower(trim(resource.payload->>'cycle'))
  UNION
  SELECT DISTINCT class.establishment_id, cycle.id, trim(class.level)
  FROM classes class
  JOIN school_cycles cycle ON cycle.establishment_id = class.establishment_id
  WHERE nullif(trim(class.level), '') IS NOT NULL
    AND (SELECT count(*) FROM school_cycles candidate
         WHERE candidate.establishment_id = class.establishment_id) = 1
), normalized_levels AS (
  SELECT establishment_id, cycle_id, name,
         upper(regexp_replace(name, '[^[:alnum:]]+', '_', 'g')) AS code
  FROM exact_levels WHERE name <> ''
)
INSERT INTO school_levels(establishment_id, cycle_id, code, name)
SELECT establishment_id, cycle_id, code, name FROM normalized_levels
ON CONFLICT (establishment_id, cycle_id, code) DO NOTHING;

UPDATE api_resources resource
SET school_level_id = level.id
FROM school_levels level
WHERE resource.kind = 'classes'
  AND resource.establishment_id = level.establishment_id
  AND resource.cycle_id = level.cycle_id
  AND lower(trim(resource.payload->>'level')) = lower(level.name);

UPDATE api_resources resource
SET school_level_id = level.id
FROM classes class
JOIN school_levels level
  ON level.establishment_id = class.establishment_id
 AND lower(level.name) = lower(trim(class.level))
WHERE resource.kind = 'classes'
  AND resource.id = class.id::text
  AND resource.establishment_id = class.establishment_id
  AND resource.cycle_id = level.cycle_id
  AND resource.school_level_id IS NULL;

UPDATE api_resources resource
SET academic_year_id = year.id
FROM academic_years year
WHERE resource.kind = 'classes'
  AND resource.establishment_id = year.establishment_id
  AND coalesce(resource.payload->>'academicYearId', resource.payload->>'schoolYearId') = year.id::text;

-- Preserve every legacy field while exposing explicit structured references.
UPDATE api_resources resource
SET payload = resource.payload
  || jsonb_build_object('cycleId', resource.cycle_id::text)
  || CASE WHEN resource.school_level_id IS NULL THEN '{}'::jsonb
          ELSE jsonb_build_object('structuredLevelId', resource.school_level_id::text) END
WHERE resource.kind = 'classes' AND resource.cycle_id IS NOT NULL;

UPDATE classes class
SET cycle_id = candidate.cycle_id
FROM (
  SELECT establishment_id, (array_agg(id ORDER BY id))[1] AS cycle_id
  FROM school_cycles GROUP BY establishment_id HAVING count(*) = 1
) candidate
WHERE class.establishment_id = candidate.establishment_id
  AND class.cycle_id IS NULL;

UPDATE classes class
SET school_level_id = level.id
FROM school_levels level
WHERE class.establishment_id = level.establishment_id
  AND class.cycle_id = level.cycle_id
  AND lower(trim(class.level)) = lower(level.name)
  AND class.school_level_id IS NULL;

-- Additive composite uniqueness allows tenant-safe foreign keys without
-- replacing the existing primary keys.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_academic_years_id_establishment') THEN
    ALTER TABLE academic_years ADD CONSTRAINT uq_academic_years_id_establishment UNIQUE (id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_classes_id_establishment') THEN
    ALTER TABLE classes ADD CONSTRAINT uq_classes_id_establishment UNIQUE (id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_students_id_establishment') THEN
    ALTER TABLE students ADD CONSTRAINT uq_students_id_establishment UNIQUE (id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_teachers_id_establishment') THEN
    ALTER TABLE teachers ADD CONSTRAINT uq_teachers_id_establishment UNIQUE (id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_subjects_id_establishment') THEN
    ALTER TABLE subjects ADD CONSTRAINT uq_subjects_id_establishment UNIQUE (id, establishment_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_classes_year_tenant') THEN
    ALTER TABLE classes ADD CONSTRAINT fk_classes_year_tenant
      FOREIGN KEY (academic_year_id, establishment_id)
      REFERENCES academic_years(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_classes_cycle_tenant') THEN
    ALTER TABLE classes ADD CONSTRAINT fk_classes_cycle_tenant
      FOREIGN KEY (cycle_id, establishment_id)
      REFERENCES school_cycles(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_classes_level_cycle_tenant') THEN
    ALTER TABLE classes ADD CONSTRAINT fk_classes_level_cycle_tenant
      FOREIGN KEY (school_level_id, cycle_id, establishment_id)
      REFERENCES school_levels(id, cycle_id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_registrations_student_tenant') THEN
    ALTER TABLE student_academic_registrations ADD CONSTRAINT fk_registrations_student_tenant
      FOREIGN KEY (student_id, establishment_id)
      REFERENCES students(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_registrations_class_tenant') THEN
    ALTER TABLE student_academic_registrations ADD CONSTRAINT fk_registrations_class_tenant
      FOREIGN KEY (class_id, establishment_id)
      REFERENCES classes(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_registrations_year_tenant') THEN
    ALTER TABLE student_academic_registrations ADD CONSTRAINT fk_registrations_year_tenant
      FOREIGN KEY (academic_year_id, establishment_id)
      REFERENCES academic_years(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_affectations_teacher_tenant') THEN
    ALTER TABLE affectations ADD CONSTRAINT fk_affectations_teacher_tenant
      FOREIGN KEY (teacher_id, establishment_id)
      REFERENCES teachers(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_affectations_class_tenant') THEN
    ALTER TABLE affectations ADD CONSTRAINT fk_affectations_class_tenant
      FOREIGN KEY (class_id, establishment_id)
      REFERENCES classes(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_affectations_subject_tenant') THEN
    ALTER TABLE affectations ADD CONSTRAINT fk_affectations_subject_tenant
      FOREIGN KEY (subject_id, establishment_id)
      REFERENCES subjects(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_api_resources_establishment') THEN
    ALTER TABLE api_resources ADD CONSTRAINT fk_api_resources_establishment
      FOREIGN KEY (establishment_id) REFERENCES establishments(id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_api_resources_cycle_tenant') THEN
    ALTER TABLE api_resources ADD CONSTRAINT fk_api_resources_cycle_tenant
      FOREIGN KEY (cycle_id, establishment_id)
      REFERENCES school_cycles(id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_api_resources_level_cycle_tenant') THEN
    ALTER TABLE api_resources ADD CONSTRAINT fk_api_resources_level_cycle_tenant
      FOREIGN KEY (school_level_id, cycle_id, establishment_id)
      REFERENCES school_levels(id, cycle_id, establishment_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_api_resources_year_tenant') THEN
    ALTER TABLE api_resources ADD CONSTRAINT fk_api_resources_year_tenant
      FOREIGN KEY (academic_year_id, establishment_id)
      REFERENCES academic_years(id, establishment_id);
  END IF;
END $$;
