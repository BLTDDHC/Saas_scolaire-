-- Un appel est propre à un créneau, un enseignant et une matière.
-- Les anciennes présences restent conservées avec un contexte de séance NULL.
ALTER TABLE attendance_records
    ADD COLUMN IF NOT EXISTS schedule_entry_id UUID,
    ADD COLUMN IF NOT EXISTS teacher_id UUID,
    ADD COLUMN IF NOT EXISTS subject_id UUID;

-- Backfill uniquement lorsqu'un seul créneau historique correspond sans ambiguïté.
WITH unique_matches AS (
    SELECT attendance.id AS attendance_id,
           (ARRAY_AGG(schedule.id ORDER BY schedule.id))[1] AS schedule_entry_id
    FROM attendance_records attendance
    JOIN teachers teacher
      ON teacher.user_id = attendance.recorded_by
     AND teacher.establishment_id = attendance.establishment_id
    JOIN schedule_entries schedule
      ON schedule.establishment_id = attendance.establishment_id
     AND schedule.academic_year_id = attendance.academic_year_id
     AND schedule.class_id = attendance.class_id
     AND schedule.teacher_id = teacher.id
     AND schedule.weekday = EXTRACT(ISODOW FROM attendance.attendance_date)::integer
     AND schedule.status = 'active'
    WHERE attendance.schedule_entry_id IS NULL
    GROUP BY attendance.id
    HAVING COUNT(schedule.id) = 1
)
UPDATE attendance_records attendance
SET schedule_entry_id = schedule.id,
    teacher_id = schedule.teacher_id,
    subject_id = schedule.subject_id
FROM unique_matches matched
JOIN schedule_entries schedule ON schedule.id = matched.schedule_entry_id
WHERE attendance.id = matched.attendance_id;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_attendance_schedule_entry'
          AND conrelid = 'attendance_records'::regclass
    ) THEN
        ALTER TABLE attendance_records
            ADD CONSTRAINT fk_attendance_schedule_entry
            FOREIGN KEY (schedule_entry_id)
            REFERENCES schedule_entries(id)
            ON DELETE RESTRICT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_attendance_teacher'
          AND conrelid = 'attendance_records'::regclass
    ) THEN
        ALTER TABLE attendance_records
            ADD CONSTRAINT fk_attendance_teacher
            FOREIGN KEY (teacher_id)
            REFERENCES teachers(id)
            ON DELETE RESTRICT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_attendance_subject'
          AND conrelid = 'attendance_records'::regclass
    ) THEN
        ALTER TABLE attendance_records
            ADD CONSTRAINT fk_attendance_subject
            FOREIGN KEY (subject_id)
            REFERENCES subjects(id)
            ON DELETE RESTRICT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_attendance_session_context'
          AND conrelid = 'attendance_records'::regclass
    ) THEN
        ALTER TABLE attendance_records
            ADD CONSTRAINT ck_attendance_session_context CHECK (
                (schedule_entry_id IS NULL AND teacher_id IS NULL AND subject_id IS NULL)
                OR
                (schedule_entry_id IS NOT NULL AND teacher_id IS NOT NULL AND subject_id IS NOT NULL)
            );
    END IF;
END $$;

ALTER TABLE attendance_records
    DROP CONSTRAINT IF EXISTS uq_attendance_student_day;

CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_student_schedule_day
    ON attendance_records (
        establishment_id,
        student_id,
        schedule_entry_id,
        attendance_date
    )
    WHERE schedule_entry_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_attendance_teacher_day
    ON attendance_records (
        establishment_id,
        teacher_id,
        attendance_date
    );
