-- Un événement d'évaluation est programmé une seule fois par l'ADMIN.
-- Les relevés par matière restent dans evaluations et sont reliés à
-- l'affectation réelle de chaque enseignant.
CREATE TABLE IF NOT EXISTS evaluation_programs (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    academic_period_id UUID NOT NULL,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(50) NOT NULL,
    exam_code VARCHAR(30),
    date_scheduled DATE,
    max_value DOUBLE PRECISION NOT NULL DEFAULT 20,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_evaluation_program_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE RESTRICT,
    CONSTRAINT fk_evaluation_program_year
        FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT,
    CONSTRAINT fk_evaluation_program_period
        FOREIGN KEY (academic_period_id) REFERENCES academic_periods(id) ON DELETE RESTRICT,
    CONSTRAINT fk_evaluation_program_creator
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT ck_evaluation_program_status
        CHECK (status IN ('active', 'archived'))
);

CREATE TABLE IF NOT EXISTS evaluation_program_classes (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    program_id UUID NOT NULL,
    class_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_evaluation_program_class_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE RESTRICT,
    CONSTRAINT fk_evaluation_program_class_program
        FOREIGN KEY (program_id) REFERENCES evaluation_programs(id) ON DELETE CASCADE,
    CONSTRAINT fk_evaluation_program_class_class
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT,
    CONSTRAINT uq_evaluation_program_class UNIQUE (program_id, class_id)
);

ALTER TABLE evaluations
    ADD COLUMN IF NOT EXISTS program_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_evaluation_program'
    ) THEN
        ALTER TABLE evaluations
            ADD CONSTRAINT fk_evaluation_program
            FOREIGN KEY (program_id) REFERENCES evaluation_programs(id)
            ON DELETE CASCADE;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_evaluation_program_affectation
    ON evaluations (program_id, affectation_id)
    WHERE program_id IS NOT NULL AND affectation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_evaluation_programs_context
    ON evaluation_programs (establishment_id, academic_year_id, academic_period_id);

CREATE INDEX IF NOT EXISTS ix_evaluation_program_classes_class
    ON evaluation_program_classes (class_id, program_id);

CREATE INDEX IF NOT EXISTS ix_evaluations_program
    ON evaluations (program_id);
