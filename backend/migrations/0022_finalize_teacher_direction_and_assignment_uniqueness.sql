-- Finalise le rattachement des enseignants aux directions et empêche qu'une
-- même matière active soit confiée à deux enseignants dans la même classe.
-- Migration additive, idempotente et sans suppression de données.

ALTER TABLE teachers
    ADD COLUMN IF NOT EXISTS created_direction_id UUID NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_teachers_created_direction_tenant'
    ) THEN
        ALTER TABLE teachers ADD CONSTRAINT fk_teachers_created_direction_tenant
            FOREIGN KEY (created_direction_id, establishment_id)
            REFERENCES school_directions(id, establishment_id);
    END IF;
END $$;

-- Un rattachement historique n'est appliqué que lorsque toutes les
-- affectations actives de l'enseignant convergent vers une seule direction.
WITH teacher_directions AS (
    SELECT a.teacher_id, MIN(dc.direction_id::text)::uuid AS direction_id
    FROM affectations a
    JOIN classes c ON c.id = a.class_id
    JOIN school_direction_cycles dc
      ON dc.cycle_id = c.cycle_id
     AND dc.establishment_id = a.establishment_id
    WHERE a.status = 'active'
    GROUP BY a.teacher_id
    HAVING COUNT(DISTINCT dc.direction_id) = 1
)
UPDATE teachers t
SET created_direction_id = td.direction_id
FROM teacher_directions td
WHERE t.id = td.teacher_id
  AND t.created_direction_id IS NULL;

CREATE INDEX IF NOT EXISTS ix_teachers_created_direction
    ON teachers(created_direction_id)
    WHERE created_direction_id IS NOT NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM affectations
        WHERE status = 'active'
        GROUP BY establishment_id, class_id, subject_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Des doublons actifs classe/matiere doivent être résolus avant cette migration';
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_affectations_active_class_subject
    ON affectations(establishment_id, class_id, subject_id)
    WHERE status = 'active';
