-- Regroupe les périodes mensuelles/personnalisées sous un trimestre.
-- Additif et nullable pour conserver toutes les périodes historiques.

ALTER TABLE academic_periods
    ADD COLUMN IF NOT EXISTS parent_period_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_academic_periods_parent'
    ) THEN
        ALTER TABLE academic_periods
            ADD CONSTRAINT fk_academic_periods_parent
            FOREIGN KEY (parent_period_id)
            REFERENCES academic_periods(id) ON DELETE RESTRICT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_academic_periods_not_self_parent'
    ) THEN
        ALTER TABLE academic_periods
            ADD CONSTRAINT ck_academic_periods_not_self_parent
            CHECK (parent_period_id IS NULL OR parent_period_id <> id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_academic_periods_parent
    ON academic_periods (establishment_id, academic_year_id, parent_period_id)
    WHERE parent_period_id IS NOT NULL;
