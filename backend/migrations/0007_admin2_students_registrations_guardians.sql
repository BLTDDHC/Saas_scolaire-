-- ADMIN 2 / Lot A: canonical students, annual registrations, pre-enrollments
-- and many-to-many guardians. Additive and idempotent; legacy api_resources
-- projections are deliberately preserved.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SEQUENCE IF NOT EXISTS student_registration_number_seq;

ALTER TABLE students ADD COLUMN IF NOT EXISTS email varchar(254) NULL;
ALTER TABLE students ADD COLUMN IF NOT EXISTS phone varchar(32) NULL;
ALTER TABLE students ADD COLUMN IF NOT EXISTS address text NULL;

CREATE TABLE IF NOT EXISTS guardians (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL,
  user_id uuid NULL,
  first_name varchar(100) NOT NULL,
  last_name varchar(100) NOT NULL,
  phone varchar(32) NULL,
  email varchar(254) NULL,
  status varchar(20) NOT NULL DEFAULT 'active',
  created_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now(),
  CONSTRAINT fk_guardians_establishment FOREIGN KEY (establishment_id) REFERENCES establishments(id),
  CONSTRAINT fk_guardians_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT ck_guardians_status CHECK (status IN ('active', 'archived')),
  CONSTRAINT ck_guardians_contact CHECK (phone IS NOT NULL OR email IS NOT NULL),
  CONSTRAINT uq_guardians_id_establishment UNIQUE (id, establishment_id)
);

CREATE TABLE IF NOT EXISTS student_guardians (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL,
  student_id uuid NOT NULL,
  guardian_id uuid NOT NULL,
  relationship varchar(50) NOT NULL,
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now(),
  CONSTRAINT fk_student_guardians_student_tenant
    FOREIGN KEY (student_id, establishment_id) REFERENCES students(id, establishment_id),
  CONSTRAINT fk_student_guardians_guardian_tenant
    FOREIGN KEY (guardian_id, establishment_id) REFERENCES guardians(id, establishment_id),
  CONSTRAINT uq_student_guardian UNIQUE (establishment_id, student_id, guardian_id)
);

CREATE TABLE IF NOT EXISTS student_pre_enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL,
  student_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  desired_class_id uuid NULL,
  status varchar(20) NOT NULL DEFAULT 'draft',
  submitted_at timestamp NULL,
  decided_at timestamp NULL,
  decision_note text NULL,
  created_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now(),
  CONSTRAINT fk_pre_enrollments_student_tenant
    FOREIGN KEY (student_id, establishment_id) REFERENCES students(id, establishment_id),
  CONSTRAINT fk_pre_enrollments_year_tenant
    FOREIGN KEY (academic_year_id, establishment_id) REFERENCES academic_years(id, establishment_id),
  CONSTRAINT fk_pre_enrollments_class_tenant
    FOREIGN KEY (desired_class_id, establishment_id) REFERENCES classes(id, establishment_id),
  CONSTRAINT ck_pre_enrollments_status
    CHECK (status IN ('draft', 'submitted', 'approved', 'rejected', 'cancelled')),
  CONSTRAINT uq_pre_enrollment_student_year
    UNIQUE (establishment_id, student_id, academic_year_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_student_registration_year
  ON student_academic_registrations(establishment_id, student_id, academic_year_id)
  WHERE status IN ('pending', 'validated', 'active');

CREATE INDEX IF NOT EXISTS ix_students_establishment_name
  ON students(establishment_id, last_name, first_name);
CREATE INDEX IF NOT EXISTS ix_guardians_establishment_name
  ON guardians(establishment_id, last_name, first_name);
CREATE INDEX IF NOT EXISTS ix_student_guardians_student
  ON student_guardians(establishment_id, student_id);
CREATE INDEX IF NOT EXISTS ix_student_guardians_guardian
  ON student_guardians(establishment_id, guardian_id);
CREATE INDEX IF NOT EXISTS ix_pre_enrollments_year_status
  ON student_pre_enrollments(establishment_id, academic_year_id, status);
CREATE INDEX IF NOT EXISTS ix_registrations_year_class
  ON student_academic_registrations(establishment_id, academic_year_id, class_id);
