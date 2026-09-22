-- Les résultats officiels sont des instantanés calculés explicitement.
-- Aucune note ni aucun historique existant n'est modifié.
CREATE TABLE IF NOT EXISTS result_calculations (
    id UUID PRIMARY KEY,
    establishment_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    class_id UUID NOT NULL,
    academic_period_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'official',
    payload JSONB NOT NULL,
    source_updated_at TIMESTAMPTZ NOT NULL,
    calculated_by UUID,
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_result_calculation_establishment
        FOREIGN KEY (establishment_id) REFERENCES establishments(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_result_calculation_year
        FOREIGN KEY (academic_year_id) REFERENCES academic_years(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_result_calculation_class
        FOREIGN KEY (class_id) REFERENCES classes(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_result_calculation_period
        FOREIGN KEY (academic_period_id) REFERENCES academic_periods(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_result_calculation_user
        FOREIGN KEY (calculated_by) REFERENCES users(id)
        ON DELETE SET NULL,
    CONSTRAINT uq_result_calculation_context
        UNIQUE (establishment_id, class_id, academic_period_id),
    CONSTRAINT ck_result_calculation_status
        CHECK (status IN ('official', 'archived'))
);

CREATE INDEX IF NOT EXISTS ix_result_calculations_year
    ON result_calculations (establishment_id, academic_year_id);

CREATE INDEX IF NOT EXISTS ix_result_calculations_context
    ON result_calculations (class_id, academic_period_id);
