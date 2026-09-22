-- Atomic additive migration. Existing attendance rows are retained, not relabelled as submitted.
ALTER TABLE schedule_entries ADD COLUMN IF NOT EXISTS retired_at TIMESTAMPTZ;
ALTER TABLE schedule_entries ADD COLUMN IF NOT EXISTS attendance_context JSONB;
UPDATE schedule_entries SET retired_at = updated_at WHERE status <> 'active' AND retired_at IS NULL;
UPDATE schedule_entries s SET attendance_context = jsonb_build_object(
    'classId',s.class_id,'class',c.name,'cycleId',c.cycle_id,'levelId',c.school_level_id,
    'teacherId',s.teacher_id,'teacher',t.last_name || ' ' || t.first_name,
    'subjectId',s.subject_id,'subject',u.name,'affectationId',s.affectation_id,
    'startTime',to_char(s.start_time,'HH24:MI'),'endTime',to_char(s.end_time,'HH24:MI'))
FROM classes c, teachers t, subjects u
WHERE c.id=s.class_id AND t.id=s.teacher_id AND u.id=s.subject_id AND s.attendance_context IS NULL;

-- Retired versions must coexist with their replacement, without relaxing active conflicts.
CREATE UNIQUE INDEX IF NOT EXISTS uq_schedule_active_class_slot ON schedule_entries
    (establishment_id,academic_year_id,class_id,weekday,start_time) WHERE status='active';
CREATE UNIQUE INDEX IF NOT EXISTS uq_schedule_active_teacher_slot ON schedule_entries
    (establishment_id,academic_year_id,teacher_id,weekday,start_time) WHERE status='active';
ALTER TABLE schedule_entries DROP CONSTRAINT IF EXISTS uq_schedule_class_slot;
ALTER TABLE schedule_entries DROP CONSTRAINT IF EXISTS uq_schedule_teacher_slot;

CREATE TABLE IF NOT EXISTS attendance_sheets (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE RESTRICT,
    academic_year_id UUID NOT NULL REFERENCES academic_years(id) ON DELETE RESTRICT,
    schedule_entry_id UUID NOT NULL REFERENCES schedule_entries(id) ON DELETE RESTRICT,
    class_id UUID NOT NULL,
    teacher_id UUID NOT NULL,
    subject_id UUID NOT NULL,
    attendance_date DATE NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','locked')),
    context_snapshot JSONB NOT NULL,
    expected_students JSONB NOT NULL,
    submitted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_attendance_sheet_session UNIQUE(establishment_id,schedule_entry_id,attendance_date),
    CONSTRAINT fk_attendance_sheet_class FOREIGN KEY(class_id,establishment_id) REFERENCES classes(id,establishment_id) ON DELETE RESTRICT,
    CONSTRAINT fk_attendance_sheet_teacher FOREIGN KEY(teacher_id,establishment_id) REFERENCES teachers(id,establishment_id) ON DELETE RESTRICT,
    CONSTRAINT fk_attendance_sheet_subject FOREIGN KEY(subject_id,establishment_id) REFERENCES subjects(id,establishment_id) ON DELETE RESTRICT,
    CONSTRAINT ck_attendance_sheet_submission CHECK ((status='locked')=(submitted_at IS NOT NULL))
);
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS sheet_id UUID;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fk_attendance_record_sheet'
        AND conrelid='attendance_records'::regclass) THEN
        ALTER TABLE attendance_records ADD CONSTRAINT fk_attendance_record_sheet
            FOREIGN KEY(sheet_id) REFERENCES attendance_sheets(id) ON DELETE RESTRICT;
    END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_sheet_student ON attendance_records(sheet_id,student_id)
    WHERE sheet_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_attendance_sheets_history ON attendance_sheets(establishment_id,academic_year_id,attendance_date);
