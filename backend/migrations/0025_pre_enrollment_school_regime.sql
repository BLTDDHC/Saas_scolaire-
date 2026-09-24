BEGIN;

ALTER TABLE student_pre_enrollments
  ADD COLUMN IF NOT EXISTS school_regime varchar(20) NOT NULL DEFAULT 'normal';

UPDATE student_pre_enrollments pre
SET school_regime = registration.school_regime
FROM student_academic_registrations registration
WHERE registration.student_id = pre.student_id
  AND registration.academic_year_id = pre.academic_year_id
  AND registration.status = 'pre_enrolled'
  AND registration.school_regime IN ('part_time', 'full_time')
  AND pre.school_regime = 'normal';

ALTER TABLE student_pre_enrollments
  DROP CONSTRAINT IF EXISTS ck_pre_enrollment_school_regime;

ALTER TABLE student_pre_enrollments
  ADD CONSTRAINT ck_pre_enrollment_school_regime
  CHECK (school_regime IN ('normal', 'part_time', 'full_time'));

COMMIT;
