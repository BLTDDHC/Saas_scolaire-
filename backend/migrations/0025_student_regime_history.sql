-- Historical school regime changes for Maternelle / Primaire.
-- Additive only: existing registrations and validated payments remain untouched.

CREATE TABLE IF NOT EXISTS student_regime_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES establishments(id),
  registration_id uuid NOT NULL REFERENCES student_academic_registrations(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES students(id),
  academic_year_id uuid NOT NULL REFERENCES academic_years(id),
  regime varchar(20) NOT NULL,
  effective_date date NOT NULL,
  ended_at date NULL,
  changed_by uuid NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_student_regime_history_regime
    CHECK (regime IN ('part_time', 'full_time')),
  CONSTRAINT ck_student_regime_history_dates
    CHECK (ended_at IS NULL OR ended_at >= effective_date),
  CONSTRAINT uq_student_regime_history_effective
    UNIQUE (registration_id, effective_date)
);

CREATE INDEX IF NOT EXISTS ix_student_regime_history_registration
  ON student_regime_history(registration_id, effective_date);

CREATE INDEX IF NOT EXISTS ix_student_regime_history_student_year
  ON student_regime_history(student_id, academic_year_id);
