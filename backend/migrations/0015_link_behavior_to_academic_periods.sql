-- Les présences restent journalières. Les comportements deviennent
-- canoniquement liés à un trimestre académique existant.
ALTER TABLE behavior_events
    ADD COLUMN IF NOT EXISTS academic_period_id UUID;

UPDATE behavior_events AS behavior
SET academic_period_id = period.id
FROM academic_periods AS period
WHERE behavior.academic_period_id IS NULL
  AND period.establishment_id = behavior.establishment_id
  AND period.academic_year_id = behavior.academic_year_id
  AND period.period_type = 'trimester'
  AND period.start_date IS NOT NULL
  AND period.end_date IS NOT NULL
  AND behavior.event_date BETWEEN period.start_date AND period.end_date;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_behavior_academic_period'
    ) THEN
        ALTER TABLE behavior_events
            ADD CONSTRAINT fk_behavior_academic_period
            FOREIGN KEY (academic_period_id)
            REFERENCES academic_periods(id)
            ON DELETE RESTRICT;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_behavior_period_scope
    ON behavior_events (
        establishment_id,
        academic_year_id,
        class_id,
        academic_period_id
    );

CREATE UNIQUE INDEX IF NOT EXISTS uq_behavior_student_trimester
    ON behavior_events (
        establishment_id,
        student_id,
        class_id,
        academic_period_id
    )
    WHERE academic_period_id IS NOT NULL AND status <> 'archived';
