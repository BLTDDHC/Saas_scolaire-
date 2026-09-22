-- Identifiants métier stables pour les examens officiels blancs et tests.
-- Migration additive : aucune donnée existante n'est supprimée.

ALTER TABLE evaluations
    ADD COLUMN IF NOT EXISTS exam_code VARCHAR(30);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_evaluations_exam_code'
    ) THEN
        ALTER TABLE evaluations
            ADD CONSTRAINT ck_evaluations_exam_code
            CHECK (exam_code IS NULL OR exam_code IN (
                'cepe_blanc',
                'bepc_test',
                'bepc_blanc',
                'bac_test',
                'bac_blanc'
            ));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_evaluations_bac_blanc_class_year
    ON evaluations (establishment_id, academic_year_id, class_id, exam_code)
    WHERE exam_code = 'bac_blanc' AND status <> 'rejected';

CREATE INDEX IF NOT EXISTS ix_evaluations_exam_code
    ON evaluations (establishment_id, academic_year_id, exam_code)
    WHERE exam_code IS NOT NULL;
