-- Étend les codes d'évaluation pour les compositions mensuelles du
-- primaire et de la maternelle. Aucune donnée existante n'est modifiée.
ALTER TABLE evaluations
    DROP CONSTRAINT IF EXISTS ck_evaluations_exam_code;

ALTER TABLE evaluations
    ADD CONSTRAINT ck_evaluations_exam_code
    CHECK (exam_code IS NULL OR exam_code IN (
        'devoir_1',
        'devoir_2',
        'composition',
        'composition_octobre',
        'composition_novembre',
        'composition_janvier',
        'composition_fevrier',
        'composition_avril',
        'composition_mai',
        'cepe_test',
        'cepe_blanc',
        'bepc_test',
        'bepc_blanc',
        'bac_test',
        'bac_blanc',
        'devoir_departemental'
    ));
