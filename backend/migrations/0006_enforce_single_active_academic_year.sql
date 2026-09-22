-- ADMIN 1: PostgreSQL is the final guard for one active academic year per
-- establishment. The API also serializes activation in a transaction.
WITH ranked_active AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY establishment_id
           ORDER BY updated_at DESC, start_date DESC, id
         ) AS active_rank
  FROM academic_years
  WHERE is_active = TRUE
)
UPDATE academic_years year
SET is_active = FALSE,
    status = 'inactive',
    updated_at = CURRENT_TIMESTAMP
FROM ranked_active ranked
WHERE year.id = ranked.id
  AND ranked.active_rank > 1;

UPDATE academic_years
SET status = CASE WHEN is_active THEN 'active' ELSE 'inactive' END
WHERE status IS DISTINCT FROM CASE WHEN is_active THEN 'active' ELSE 'inactive' END;

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_years_one_active_per_establishment
  ON academic_years(establishment_id)
  WHERE is_active = TRUE;
