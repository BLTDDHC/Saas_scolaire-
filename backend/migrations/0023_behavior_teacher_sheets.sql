-- Run within one transaction. Preserve all existing contributions; refuse ambiguity.
ALTER TABLE behavior_events ADD COLUMN IF NOT EXISTS teacher_id UUID;
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM behavior_events b
        LEFT JOIN teachers t ON t.user_id = b.recorded_by AND t.establishment_id = b.establishment_id
        WHERE b.status <> 'archived'
        GROUP BY b.id, b.academic_period_id, b.category
        HAVING count(t.id) <> 1 OR b.academic_period_id IS NULL OR b.category !~ '^stars:[1-5]$'
    ) THEN
        RAISE EXCEPTION 'Behavior migration blocked: unresolved author, trimester or stars; preserve and reconcile existing rows';
    END IF;
END $$;
UPDATE behavior_events b SET teacher_id = t.id
FROM teachers t WHERE t.user_id = b.recorded_by AND t.establishment_id = b.establishment_id
AND b.teacher_id IS NULL;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM behavior_events WHERE status <> 'archived'
        GROUP BY establishment_id, academic_year_id, class_id, academic_period_id, teacher_id, student_id
        HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Behavior migration blocked: duplicate contributions; no data deleted';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_behavior_teacher_tenant'
                   AND conrelid = 'behavior_events'::regclass) THEN
        ALTER TABLE behavior_events ADD CONSTRAINT fk_behavior_teacher_tenant
        FOREIGN KEY (teacher_id, establishment_id) REFERENCES teachers(id, establishment_id) ON DELETE RESTRICT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_behavior_teacher_stars'
                   AND conrelid = 'behavior_events'::regclass) THEN
        ALTER TABLE behavior_events ADD CONSTRAINT ck_behavior_teacher_stars CHECK (
            status = 'archived' OR (teacher_id IS NOT NULL AND academic_period_id IS NOT NULL
                AND category ~ '^stars:[1-5]$' AND status IN ('draft','locked','active')));
    END IF;
END $$;
-- Create the replacement before removing the old, more restrictive index.
CREATE UNIQUE INDEX IF NOT EXISTS uq_behavior_teacher_student_trimester ON behavior_events
    (establishment_id, academic_year_id, class_id, academic_period_id, teacher_id, student_id)
    WHERE status <> 'archived';
DROP INDEX IF EXISTS uq_behavior_student_trimester;

CREATE TABLE IF NOT EXISTS behavior_calculations (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE RESTRICT,
    academic_year_id UUID NOT NULL REFERENCES academic_years(id) ON DELETE RESTRICT,
    class_id UUID NOT NULL,
    academic_period_id UUID NOT NULL REFERENCES academic_periods(id) ON DELETE RESTRICT,
    source_fingerprint VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    calculated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    calculated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_behavior_calculation_class_tenant FOREIGN KEY (class_id, establishment_id)
        REFERENCES classes(id, establishment_id) ON DELETE RESTRICT,
    CONSTRAINT uq_behavior_calculation_context UNIQUE (establishment_id, class_id, academic_period_id)
);
