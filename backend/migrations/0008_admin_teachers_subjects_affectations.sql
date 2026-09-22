-- ADMIN scolaire - enseignants, matieres et affectations relationnelles.
-- Migration additive et idempotente : aucune suppression de donnees.

ALTER TABLE teachers
    ADD COLUMN IF NOT EXISTS email VARCHAR(254),
    ADD COLUMN IF NOT EXISTS phone VARCHAR(32),
    ADD COLUMN IF NOT EXISTS gender VARCHAR(16),
    ADD COLUMN IF NOT EXISTS birth_date DATE,
    ADD COLUMN IF NOT EXISTS address TEXT,
    ADD COLUMN IF NOT EXISTS diploma VARCHAR(150),
    ADD COLUMN IF NOT EXISTS hire_date DATE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_teachers_establishment_employee_number
    ON teachers (establishment_id, lower(employee_number))
    WHERE employee_number IS NOT NULL AND btrim(employee_number) <> '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_subjects_establishment_name
    ON subjects (establishment_id, lower(name));

CREATE UNIQUE INDEX IF NOT EXISTS uq_subjects_establishment_code
    ON subjects (establishment_id, lower(code))
    WHERE code IS NOT NULL AND btrim(code) <> '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_affectations_active_context
    ON affectations (establishment_id, teacher_id, class_id, subject_id)
    WHERE status = 'active';

CREATE TABLE IF NOT EXISTS subject_level_settings (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    subject_id UUID NOT NULL,
    school_level_id UUID NOT NULL,
    coefficient NUMERIC(6, 2),
    grading_scale NUMERIC(6, 2) NOT NULL DEFAULT 20,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_subject_level_settings_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_subject_level_settings_subject_tenant
        FOREIGN KEY (subject_id, establishment_id)
        REFERENCES subjects(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_subject_level_settings_level_tenant
        FOREIGN KEY (school_level_id, establishment_id)
        REFERENCES school_levels(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT ck_subject_level_settings_coefficient
        CHECK (coefficient IS NULL OR coefficient > 0),
    CONSTRAINT ck_subject_level_settings_scale
        CHECK (grading_scale > 0),
    CONSTRAINT uq_subject_level_settings_context
        UNIQUE (establishment_id, subject_id, school_level_id)
);

CREATE INDEX IF NOT EXISTS ix_subject_level_settings_establishment
    ON subject_level_settings (establishment_id);
