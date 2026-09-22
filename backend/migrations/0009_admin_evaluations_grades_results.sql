-- ADMIN scolaire - periodes, evaluations, notes et tracabilite.
-- Extension additive du schema relationnel existant.

CREATE TABLE IF NOT EXISTS academic_periods (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    code VARCHAR(32) NOT NULL,
    name VARCHAR(80) NOT NULL,
    period_type VARCHAR(20) NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    start_date DATE,
    end_date DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_academic_periods_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_academic_periods_year
        FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE,
    CONSTRAINT ck_academic_periods_type
        CHECK (period_type IN ('trimester', 'semester')),
    CONSTRAINT ck_academic_periods_dates
        CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date),
    CONSTRAINT uq_academic_periods_context
        UNIQUE (establishment_id, academic_year_id, code)
);

ALTER TABLE evaluations
    ADD COLUMN IF NOT EXISTS academic_year_id UUID,
    ADD COLUMN IF NOT EXISTS academic_period_id UUID,
    ADD COLUMN IF NOT EXISTS affectation_id UUID,
    ADD COLUMN IF NOT EXISTS created_by UUID,
    ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS validated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS validated_by UUID,
    ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS rejected_by UUID,
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

UPDATE evaluations e
SET academic_year_id = c.academic_year_id
FROM classes c
WHERE e.class_id = c.id
  AND e.academic_year_id IS NULL;

ALTER TABLE evaluations
    ADD CONSTRAINT fk_evaluations_academic_year
        FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_evaluations_academic_period
        FOREIGN KEY (academic_period_id) REFERENCES academic_periods(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_evaluations_affectation
        FOREIGN KEY (affectation_id) REFERENCES affectations(id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_evaluations_created_by
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_evaluations_validated_by
        FOREIGN KEY (validated_by) REFERENCES users(id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_evaluations_rejected_by
        FOREIGN KEY (rejected_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE grades
    ALTER COLUMN value DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS presence VARCHAR(20) NOT NULL DEFAULT 'present',
    ADD COLUMN IF NOT EXISTS entered_by UUID,
    ADD COLUMN IF NOT EXISTS comment TEXT;

ALTER TABLE grades
    ADD CONSTRAINT fk_grades_entered_by
        FOREIGN KEY (entered_by) REFERENCES users(id) ON DELETE SET NULL,
    ADD CONSTRAINT ck_grades_presence
        CHECK (presence IN ('present', 'absent', 'not_recorded')),
    ADD CONSTRAINT ck_grades_value
        CHECK (
            (presence = 'present' AND value IS NOT NULL AND value >= 0 AND value <= max_value)
            OR (presence IN ('absent', 'not_recorded') AND value IS NULL)
        );

CREATE TABLE IF NOT EXISTS evaluation_status_events (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    evaluation_id UUID NOT NULL,
    actor_user_id UUID,
    from_status VARCHAR(50),
    to_status VARCHAR(50) NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_evaluation_events_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_evaluation_events_evaluation
        FOREIGN KEY (evaluation_id) REFERENCES evaluations(id) ON DELETE CASCADE,
    CONSTRAINT fk_evaluation_events_actor
        FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS ix_academic_periods_scope
    ON academic_periods (establishment_id, academic_year_id, sort_order);
CREATE INDEX IF NOT EXISTS ix_evaluations_scope
    ON evaluations (establishment_id, academic_year_id, class_id, subject_id);
CREATE INDEX IF NOT EXISTS ix_grades_scope
    ON grades (establishment_id, class_id, subject_id, evaluation_id);
CREATE INDEX IF NOT EXISTS ix_evaluation_events_evaluation
    ON evaluation_status_events (evaluation_id, created_at);
