-- Add the departmental assessment to the canonical evaluation-event codes.
-- This is an additive constraint change only: no data reset, reseed or rewrite.

ALTER TABLE evaluations
DROP CONSTRAINT IF EXISTS ck_evaluations_exam_code;

ALTER TABLE evaluations
ADD CONSTRAINT ck_evaluations_exam_code
CHECK (exam_code IS NULL OR exam_code IN (
  'devoir_1',
  'devoir_2',
  'composition',
  'cepe_test',
  'cepe_blanc',
  'bepc_test',
  'bepc_blanc',
  'bac_test',
  'bac_blanc',
  'devoir_departemental'
));
