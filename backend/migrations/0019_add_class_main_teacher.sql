-- Un professeur principal maximum par classe.
-- Migration additive : aucune donnée existante n'est supprimée.

ALTER TABLE classes
    ADD COLUMN IF NOT EXISTS main_teacher_id UUID;

CREATE INDEX IF NOT EXISTS ix_classes_main_teacher_id
    ON classes(main_teacher_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_classes_main_teacher'
    ) THEN
        ALTER TABLE classes
            ADD CONSTRAINT fk_classes_main_teacher
            FOREIGN KEY (main_teacher_id)
            REFERENCES teachers(id)
            ON DELETE SET NULL;
    END IF;
END
$$;
