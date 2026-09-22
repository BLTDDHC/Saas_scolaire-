-- ADMIN scolaire - presence, comportement, devoirs et emploi du temps.
-- Tables relationnelles tenant-safe, sans suppression des donnees historiques.

CREATE TABLE IF NOT EXISTS attendance_records (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    student_id UUID NOT NULL,
    class_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    attendance_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL,
    note TEXT,
    recorded_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_attendance_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_attendance_student_tenant
        FOREIGN KEY (student_id, establishment_id)
        REFERENCES students(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_attendance_class_tenant
        FOREIGN KEY (class_id, establishment_id)
        REFERENCES classes(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_attendance_year
        FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE,
    CONSTRAINT fk_attendance_actor
        FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT ck_attendance_status
        CHECK (status IN ('present', 'absent', 'late', 'justified')),
    CONSTRAINT uq_attendance_student_day
        UNIQUE (establishment_id, student_id, attendance_date)
);

CREATE TABLE IF NOT EXISTS behavior_events (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    student_id UUID NOT NULL,
    class_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    event_date DATE NOT NULL,
    category VARCHAR(50) NOT NULL,
    event_type VARCHAR(20) NOT NULL,
    severity VARCHAR(20) NOT NULL DEFAULT 'normal',
    title VARCHAR(120) NOT NULL,
    description TEXT,
    recorded_by UUID,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_behavior_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_behavior_student_tenant
        FOREIGN KEY (student_id, establishment_id)
        REFERENCES students(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_behavior_class_tenant
        FOREIGN KEY (class_id, establishment_id)
        REFERENCES classes(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_behavior_year
        FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE,
    CONSTRAINT fk_behavior_actor
        FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT ck_behavior_type
        CHECK (event_type IN ('positive', 'negative', 'neutral')),
    CONSTRAINT ck_behavior_severity
        CHECK (severity IN ('low', 'normal', 'high', 'critical'))
);

CREATE TABLE IF NOT EXISTS school_assignments (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    class_id UUID NOT NULL,
    subject_id UUID NOT NULL,
    teacher_id UUID,
    affectation_id UUID,
    title VARCHAR(150) NOT NULL,
    description TEXT,
    assigned_date DATE NOT NULL,
    due_date DATE NOT NULL,
    max_score NUMERIC(8, 2),
    status VARCHAR(20) NOT NULL DEFAULT 'published',
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_assignments_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_assignments_year
        FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE,
    CONSTRAINT fk_assignments_class_tenant
        FOREIGN KEY (class_id, establishment_id)
        REFERENCES classes(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_assignments_subject_tenant
        FOREIGN KEY (subject_id, establishment_id)
        REFERENCES subjects(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_assignments_teacher_tenant
        FOREIGN KEY (teacher_id, establishment_id)
        REFERENCES teachers(id, establishment_id),
    CONSTRAINT fk_assignments_affectation
        FOREIGN KEY (affectation_id) REFERENCES affectations(id) ON DELETE SET NULL,
    CONSTRAINT fk_assignments_actor
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT ck_assignments_dates CHECK (assigned_date <= due_date),
    CONSTRAINT ck_assignments_score CHECK (max_score IS NULL OR max_score > 0)
);

CREATE TABLE IF NOT EXISTS schedule_entries (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    class_id UUID NOT NULL,
    subject_id UUID NOT NULL,
    teacher_id UUID NOT NULL,
    affectation_id UUID,
    weekday SMALLINT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    room VARCHAR(80),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_schedule_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id) ON DELETE CASCADE,
    CONSTRAINT fk_schedule_year
        FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE,
    CONSTRAINT fk_schedule_class_tenant
        FOREIGN KEY (class_id, establishment_id)
        REFERENCES classes(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_schedule_subject_tenant
        FOREIGN KEY (subject_id, establishment_id)
        REFERENCES subjects(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_schedule_teacher_tenant
        FOREIGN KEY (teacher_id, establishment_id)
        REFERENCES teachers(id, establishment_id) ON DELETE CASCADE,
    CONSTRAINT fk_schedule_affectation
        FOREIGN KEY (affectation_id) REFERENCES affectations(id) ON DELETE SET NULL,
    CONSTRAINT fk_schedule_actor
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT ck_schedule_weekday CHECK (weekday BETWEEN 1 AND 7),
    CONSTRAINT ck_schedule_times CHECK (start_time < end_time),
    CONSTRAINT uq_schedule_class_slot
        UNIQUE (establishment_id, academic_year_id, class_id, weekday, start_time),
    CONSTRAINT uq_schedule_teacher_slot
        UNIQUE (establishment_id, academic_year_id, teacher_id, weekday, start_time)
);

CREATE INDEX IF NOT EXISTS ix_attendance_scope
    ON attendance_records (establishment_id, academic_year_id, class_id, attendance_date);
CREATE INDEX IF NOT EXISTS ix_behavior_scope
    ON behavior_events (establishment_id, academic_year_id, class_id, event_date);
CREATE INDEX IF NOT EXISTS ix_assignments_scope
    ON school_assignments (establishment_id, academic_year_id, class_id, due_date);
CREATE INDEX IF NOT EXISTS ix_schedule_scope
    ON schedule_entries (establishment_id, academic_year_id, class_id, weekday);
