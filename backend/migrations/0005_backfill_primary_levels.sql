-- Definitive primary-school mapping: CP1, CP2, CE1, CE2, CM1 and CM2 are
-- levels. Existing rows in api_resources remain classes and are attached to
-- the matching structured level without changing their identity or name.

WITH primary_classes AS (
  SELECT DISTINCT resource.establishment_id, resource.cycle_id,
         upper(trim(resource.payload->>'name')) AS level_code
  FROM api_resources resource
  JOIN school_cycles cycle
    ON cycle.id = resource.cycle_id
   AND cycle.establishment_id = resource.establishment_id
   AND cycle.code = 'PRIMAIRE'
  WHERE resource.kind = 'classes'
    AND upper(trim(resource.payload->>'name')) IN ('CP1','CP2','CE1','CE2','CM1','CM2')
    AND lower(trim(resource.payload->>'level')) = 'primaire'
), levels_to_create AS (
  SELECT establishment_id, cycle_id, level_code AS code, level_code AS name,
         CASE level_code
           WHEN 'CP1' THEN 10
           WHEN 'CP2' THEN 20
           WHEN 'CE1' THEN 30
           WHEN 'CE2' THEN 40
           WHEN 'CM1' THEN 50
           WHEN 'CM2' THEN 60
         END AS sort_order
  FROM primary_classes
)
INSERT INTO school_levels(establishment_id, cycle_id, code, name, sort_order)
SELECT establishment_id, cycle_id, code, name, sort_order
FROM levels_to_create
ON CONFLICT (establishment_id, cycle_id, code) DO NOTHING;

UPDATE api_resources resource
SET school_level_id = level.id,
    payload = resource.payload
      || jsonb_build_object(
           'legacyLevel', resource.payload->>'level',
           'level', level.name,
           'structuredLevelId', level.id::text
         )
FROM school_cycles cycle
JOIN school_levels level
  ON level.cycle_id = cycle.id
 AND level.establishment_id = cycle.establishment_id
WHERE resource.kind = 'classes'
  AND resource.establishment_id = cycle.establishment_id
  AND resource.cycle_id = cycle.id
  AND cycle.code = 'PRIMAIRE'
  AND upper(trim(resource.payload->>'name')) = level.code
  AND upper(trim(resource.payload->>'name')) IN ('CP1','CP2','CE1','CE2','CM1','CM2')
  AND lower(trim(resource.payload->>'level')) = 'primaire';
