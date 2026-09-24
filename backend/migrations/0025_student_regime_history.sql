BEGIN;

CREATE TABLE IF NOT EXISTS student_regime_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES establishments(id),
  registration_id uuid NOT NULL REFERENCES student_academic_registrations(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES students(id),
  academic_year_id uuid NOT NULL REFERENCES academic_years(id),
  regime varchar(20) NOT NULL,
  effective_from date NOT NULL,
  effective_to date NULL,
  tariff_amount integer NULL,
  changed_by uuid NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_student_regime_history_regime
    CHECK (regime IN ('part_time', 'full_time')),
  CONSTRAINT ck_student_regime_history_dates
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT ck_student_regime_history_tariff
    CHECK (tariff_amount IS NULL OR tariff_amount >= 0)
);

CREATE INDEX IF NOT EXISTS ix_student_regime_history_registration
  ON student_regime_history(registration_id, effective_from);
CREATE INDEX IF NOT EXISTS ix_student_regime_history_student_year
  ON student_regime_history(student_id, academic_year_id, effective_from);

INSERT INTO student_regime_history (
  establishment_id,
  registration_id,
  student_id,
  academic_year_id,
  regime,
  effective_from
)
SELECT
  registration.establishment_id,
  registration.id,
  registration.student_id,
  registration.academic_year_id,
  registration.school_regime,
  registration.registration_date
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
