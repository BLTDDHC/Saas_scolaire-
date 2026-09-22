BEGIN;

ALTER TABLE student_academic_registrations
    DROP CONSTRAINT IF EXISTS ck_registration_school_regime;

ALTER TABLE student_academic_registrations
    ADD CONSTRAINT ck_registration_school_regime
    CHECK (school_regime IN ('normal', 'part_time', 'full_time'));

COMMIT;
