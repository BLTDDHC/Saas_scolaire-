-- Finalisation du coeur ADMIN scolaire.
-- Migration additive et idempotente : aucune table ni donnee historique n'est supprimee.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Series optionnelles, principalement utilisees au lycee.
CREATE TABLE IF NOT EXISTS school_series (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    establishment_id UUID NOT NULL,
    cycle_id UUID NOT NULL,
    code VARCHAR(32) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_school_series_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_school_series_cycle_tenant
        FOREIGN KEY (cycle_id, establishment_id)
        REFERENCES school_cycles(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT ck_school_series_status CHECK (status IN ('active', 'inactive', 'archived')),
    CONSTRAINT uq_school_series_id_establishment UNIQUE (id, establishment_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_school_series_code
    ON school_series (establishment_id, lower(code)) WHERE status <> 'archived';
CREATE UNIQUE INDEX IF NOT EXISTS uq_school_series_name
    ON school_series (establishment_id, lower(name)) WHERE status <> 'archived';

ALTER TABLE classes ADD COLUMN IF NOT EXISTS series_id UUID;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_classes_series_tenant') THEN
        ALTER TABLE classes ADD CONSTRAINT fk_classes_series_tenant
            FOREIGN KEY (series_id, establishment_id)
            REFERENCES school_series(id, establishment_id);
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS ix_classes_series ON classes (establishment_id, series_id);

-- L'identite eleve reste permanente ; le matricule devient annuel sur l'inscription.
ALTER TABLE students ADD COLUMN IF NOT EXISTS nationality VARCHAR(100);
ALTER TABLE students ALTER COLUMN registration_number DROP NOT NULL;

ALTER TABLE student_academic_registrations
    ADD COLUMN IF NOT EXISTS registration_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS school_regime VARCHAR(20) NOT NULL DEFAULT 'normal',
    ADD COLUMN IF NOT EXISTS has_td BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS options JSONB NOT NULL DEFAULT '{}'::jsonb;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_registration_school_regime') THEN
        ALTER TABLE student_academic_registrations ADD CONSTRAINT ck_registration_school_regime
            CHECK (school_regime IN ('normal', 'full_time'));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_registration_number_year
    ON student_academic_registrations (establishment_id, academic_year_id, lower(registration_number))
    WHERE registration_number IS NOT NULL;

CREATE TABLE IF NOT EXISTS annual_registration_counters (
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    last_value INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (establishment_id, academic_year_id),
    CONSTRAINT fk_registration_counter_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_registration_counter_year_tenant
        FOREIGN KEY (academic_year_id, establishment_id)
        REFERENCES academic_years(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT ck_registration_counter_value CHECK (last_value >= 0)
);

CREATE TABLE IF NOT EXISTS student_class_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    establishment_id UUID NOT NULL,
    registration_id UUID NOT NULL,
    student_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    from_class_id UUID NOT NULL,
    to_class_id UUID NOT NULL,
    effective_date DATE NOT NULL,
    reason TEXT,
    grade_handling_decision VARCHAR(30),
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_transfer_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_transfer_registration
        FOREIGN KEY (registration_id) REFERENCES student_academic_registrations(id) ON DELETE CASCADE,
    CONSTRAINT fk_transfer_student_tenant
        FOREIGN KEY (student_id, establishment_id) REFERENCES students(id, establishment_id),
    CONSTRAINT fk_transfer_year_tenant
        FOREIGN KEY (academic_year_id, establishment_id) REFERENCES academic_years(id, establishment_id),
    CONSTRAINT fk_transfer_from_class_tenant
        FOREIGN KEY (from_class_id, establishment_id) REFERENCES classes(id, establishment_id),
    CONSTRAINT fk_transfer_to_class_tenant
        FOREIGN KEY (to_class_id, establishment_id) REFERENCES classes(id, establishment_id),
    CONSTRAINT fk_transfer_actor FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT ck_transfer_distinct_classes CHECK (from_class_id <> to_class_id),
    CONSTRAINT ck_transfer_grade_decision CHECK (
        grade_handling_decision IS NULL OR
        grade_handling_decision IN ('keep_origin', 'move_destination', 'admin_review')
    )
);
CREATE INDEX IF NOT EXISTS ix_student_class_transfers_history
    ON student_class_transfers (establishment_id, student_id, academic_year_id, effective_date);

-- Une personne responsable peut etre reconnue entre plusieurs etablissements.
CREATE TABLE IF NOT EXISTS guardian_people (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(32),
    second_phone VARCHAR(32),
    email VARCHAR(254),
    address TEXT,
    profession VARCHAR(150),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_guardian_people_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT ck_guardian_people_contact CHECK (phone IS NOT NULL OR email IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_guardian_people_phone
    ON guardian_people (regexp_replace(phone, '[^0-9+]', '', 'g')) WHERE phone IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_guardian_people_email
    ON guardian_people (lower(email)) WHERE email IS NOT NULL;

ALTER TABLE guardians
    ADD COLUMN IF NOT EXISTS person_id UUID,
    ADD COLUMN IF NOT EXISTS second_phone VARCHAR(32),
    ADD COLUMN IF NOT EXISTS address TEXT,
    ADD COLUMN IF NOT EXISTS profession VARCHAR(150);
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_guardians_person') THEN
        ALTER TABLE guardians ADD CONSTRAINT fk_guardians_person
            FOREIGN KEY (person_id) REFERENCES guardian_people(id) ON DELETE RESTRICT;
    END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_guardians_person_establishment
    ON guardians (establishment_id, person_id) WHERE person_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_student_primary_guardian
    ON student_guardians (establishment_id, student_id) WHERE is_primary;

-- Parametrage matiere/niveau/serie/annee.
ALTER TABLE subject_level_settings
    ADD COLUMN IF NOT EXISTS academic_year_id UUID,
    ADD COLUMN IF NOT EXISTS series_id UUID,
    ADD COLUMN IF NOT EXISTS contributes_to_average BOOLEAN NOT NULL DEFAULT true;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_subject_level_settings_context') THEN
        ALTER TABLE subject_level_settings DROP CONSTRAINT uq_subject_level_settings_context;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_subject_settings_year_tenant') THEN
        ALTER TABLE subject_level_settings ADD CONSTRAINT fk_subject_settings_year_tenant
            FOREIGN KEY (academic_year_id, establishment_id)
            REFERENCES academic_years(id, establishment_id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_subject_settings_series_tenant') THEN
        ALTER TABLE subject_level_settings ADD CONSTRAINT fk_subject_settings_series_tenant
            FOREIGN KEY (series_id, establishment_id)
            REFERENCES school_series(id, establishment_id) ON DELETE CASCADE;
    END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_subject_settings_without_series
    ON subject_level_settings (establishment_id, academic_year_id, subject_id, school_level_id)
    WHERE series_id IS NULL AND status <> 'archived';
CREATE UNIQUE INDEX IF NOT EXISTS uq_subject_settings_with_series
    ON subject_level_settings (establishment_id, academic_year_id, subject_id, school_level_id, series_id)
    WHERE series_id IS NOT NULL AND status <> 'archived';

-- Calendrier et regles d'evaluation configurables.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_academic_periods_type') THEN
        ALTER TABLE academic_periods DROP CONSTRAINT ck_academic_periods_type;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_academic_periods_type_v2') THEN
        ALTER TABLE academic_periods ADD CONSTRAINT ck_academic_periods_type_v2
            CHECK (period_type IN ('trimester', 'month', 'custom'));
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS school_calendar_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    teaching_days JSONB NOT NULL DEFAULT '[1,2,3,4,5]'::jsonb,
    day_start TIME NOT NULL DEFAULT '07:00',
    day_end TIME NOT NULL DEFAULT '17:00',
    course_duration_minutes INTEGER NOT NULL DEFAULT 60,
    pause_duration_minutes INTEGER NOT NULL DEFAULT 15,
    pause_frequency INTEGER NOT NULL DEFAULT 2,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_calendar_settings_establishment FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_calendar_settings_year_tenant FOREIGN KEY (academic_year_id, establishment_id)
        REFERENCES academic_years(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT uq_calendar_settings_year UNIQUE (establishment_id, academic_year_id),
    CONSTRAINT ck_calendar_settings_time CHECK (day_start < day_end),
    CONSTRAINT ck_calendar_settings_duration CHECK (
        course_duration_minutes > 0 AND pause_duration_minutes >= 0 AND pause_frequency > 0
    )
);

CREATE TABLE IF NOT EXISTS school_calendar_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    academic_period_id UUID,
    title VARCHAR(150) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_calendar_events_establishment FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_calendar_events_year_tenant FOREIGN KEY (academic_year_id, establishment_id)
        REFERENCES academic_years(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_calendar_events_period FOREIGN KEY (academic_period_id) REFERENCES academic_periods(id) ON DELETE SET NULL,
    CONSTRAINT ck_calendar_events_dates CHECK (start_date <= end_date),
    CONSTRAINT ck_calendar_events_status CHECK (status IN ('active', 'cancelled', 'archived'))
);

CREATE TABLE IF NOT EXISTS evaluation_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    cycle_id UUID NOT NULL,
    school_level_id UUID,
    series_id UUID,
    evaluation_type VARCHAR(30) NOT NULL,
    label VARCHAR(100) NOT NULL,
    expected_count INTEGER,
    contributes_to_average BOOLEAN NOT NULL DEFAULT true,
    is_required BOOLEAN NOT NULL DEFAULT false,
    sort_order INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_evaluation_rules_establishment FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_evaluation_rules_year_tenant FOREIGN KEY (academic_year_id, establishment_id)
        REFERENCES academic_years(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_evaluation_rules_cycle_tenant FOREIGN KEY (cycle_id, establishment_id)
        REFERENCES school_cycles(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_evaluation_rules_level_tenant FOREIGN KEY (school_level_id, establishment_id)
        REFERENCES school_levels(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_evaluation_rules_series_tenant FOREIGN KEY (series_id, establishment_id)
        REFERENCES school_series(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT ck_evaluation_rules_type CHECK (evaluation_type IN ('devoir', 'composition', 'test', 'exam', 'exam_blanc')),
    CONSTRAINT ck_evaluation_rules_count CHECK (expected_count IS NULL OR expected_count > 0),
    CONSTRAINT ck_evaluation_rules_status CHECK (status IN ('active', 'inactive', 'archived'))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_evaluation_rules_context
    ON evaluation_rules (
        establishment_id, academic_year_id, cycle_id,
        COALESCE(school_level_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(series_id, '00000000-0000-0000-0000-000000000000'::uuid),
        evaluation_type, lower(label)
    ) WHERE status <> 'archived';

CREATE TABLE IF NOT EXISTS student_annual_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    establishment_id UUID NOT NULL,
    student_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    decision VARCHAR(20) NOT NULL,
    reason TEXT,
    decided_by UUID,
    decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_annual_decisions_establishment FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_annual_decisions_student_tenant FOREIGN KEY (student_id, establishment_id)
        REFERENCES students(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_annual_decisions_year_tenant FOREIGN KEY (academic_year_id, establishment_id)
        REFERENCES academic_years(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_annual_decisions_actor FOREIGN KEY (decided_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT ck_annual_decision CHECK (decision IN ('admitted', 'repeat', 'excluded')),
    CONSTRAINT ck_annual_exclusion_reason CHECK (decision <> 'excluded' OR reason IS NOT NULL),
    CONSTRAINT uq_annual_decision_student_year UNIQUE (establishment_id, student_id, academic_year_id)
);

-- Le retard et les semestres ne font pas partie du modele canonique.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_attendance_status') THEN
        ALTER TABLE attendance_records DROP CONSTRAINT ck_attendance_status;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_attendance_status_v2') THEN
        ALTER TABLE attendance_records ADD CONSTRAINT ck_attendance_status_v2
            CHECK (status IN ('present', 'absent', 'justified'));
    END IF;
END $$;

-- Les contraintes exactes sur l'heure de debut ne suffisent pas : les chevauchements
-- sont controles transactionnellement par FastAPI. La colonne room reste historique.
ALTER TABLE schedule_entries ALTER COLUMN room DROP NOT NULL;

CREATE INDEX IF NOT EXISTS ix_calendar_events_scope
    ON school_calendar_events (establishment_id, academic_year_id, start_date);
CREATE INDEX IF NOT EXISTS ix_evaluation_rules_scope
    ON evaluation_rules (establishment_id, academic_year_id, cycle_id, school_level_id, series_id);
CREATE INDEX IF NOT EXISTS ix_annual_decisions_scope
    ON student_annual_decisions (establishment_id, academic_year_id, decision);
