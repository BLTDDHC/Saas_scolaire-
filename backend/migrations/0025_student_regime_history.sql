BEGIN;

ALTER TABLE student_pre_enrollments
  ADD COLUMN IF NOT EXISTS desired_school_regime varchar(20) NULL;

ALTER TABLE student_pre_enrollments
  DROP CONSTRAINT IF EXISTS ck_pre_enrollment_school_regime;

ALTER TABLE student_pre_enrollments
  ADD CONSTRAINT ck_pre_enrollment_school_regime
  CHECK (desired_school_regime IS NULL OR desired_school_regime IN ('part_time', 'full_time'));


CREATE TABLE IF NOT EXISTS student_regime_history (
  id uuid PRIMARY KEY,
  establishment_id uuid NOT NULL,
  registration_id uuid NOT NULL,
  student_id uuid NOT NULL,
  school_regime varchar(20) NOT NULL,
  effective_date date NOT NULL,
  end_date date NULL,
  created_by uuid NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_student_regime_history_value
    CHECK (school_regime IN ('part_time', 'full_time')),
  CONSTRAINT fk_student_regime_history_establishment
    FOREIGN KEY (establishment_id) REFERENCES establishments(id),
  CONSTRAINT fk_student_regime_history_registration
    FOREIGN KEY (registration_id) REFERENCES student_academic_registrations(id) ON DELETE CASCADE,
  CONSTRAINT fk_student_regime_history_student
    FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  CONSTRAINT fk_student_regime_history_created_by
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS ix_student_regime_history_registration_date
  ON student_regime_history (registration_id, effective_date);

CREATE UNIQUE INDEX IF NOT EXISTS uq_student_regime_history_registration_effective
  ON student_regime_history (registration_id, effective_date);

INSERT INTO student_regime_history (
  id,
  establishment_id,
  registration_id,
  student_id,
  school_regime,
  effective_date,
  end_date,
  created_by,
  created_at
)
SELECT
  gen_random_uuid(),
  registration.establishment_id,
  registration.id,
  registration.student_id,
  registration.school_regime,
  registration.registration_date,
  NULL,
  NULL,
  now()
FROM student_academic_registrations registration
JOIN classes school_class ON school_class.id = registration.class_id
JOIN school_cycles cycle ON cycle.id = school_class.cycle_id
WHERE registration.school_regime IN ('part_time', 'full_time')
  AND upper(cycle.code) IN ('MATERNELLE', 'PRIMAIRE')
  AND NOT EXISTS (
    SELECT 1
    FROM student_regime_history history
    WHERE history.registration_id = registration.id
  );

COMMIT;
