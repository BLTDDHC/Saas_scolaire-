"""Regression tests for trimester evaluation rules and teacher visibility.

All data is created in the shared PostgreSQL rollback fixture.
"""
import unittest
import uuid

from app import main as m
import test_behavior_foundations as fixtures


class EvaluationCycleRulesRegression(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)

    def test_teacher_sees_programmed_sheet_after_affectation_replacement(self):
        old_affectation = self.s.scalar(m.select(m.Affectation).where(
            m.Affectation.teacher_id == self.teachers[0].id,
            m.Affectation.class_id == self.cl.id,
            m.Affectation.status == "active",
        ))
        self.assertIsNotNone(old_affectation)
        evaluation = self.add(m.Evaluation(
            establishment_id=self.tenant.id,
            class_id=self.cl.id,
            subject_id=old_affectation.subject_id,
            academic_year_id=self.year.id,
            academic_period_id=self.periods[0].id,
            affectation_id=old_affectation.id,
            name="Composition historique",
            type="composition",
            exam_code="composition",
            period="T1",
            max_value=20,
            status="draft",
            created_by=uuid.UUID(self.principals[0].id),
        ))

        # Simulate a real deployed database where the assignment was replaced
        # after the evaluation had already been materialized.
        old_affectation.status = "inactive"
        replacement = self.add(m.Affectation(
            establishment_id=self.tenant.id,
            teacher_id=self.teachers[0].id,
            class_id=self.cl.id,
            subject_id=old_affectation.subject_id,
            status="active",
        ))
        self.s.flush()

        rows = m.list_evaluations(
            academic_year_id=self.year.id,
            class_id=None,
            subject_id=None,
            period_id=None,
            current=self.principals[0],
            session=self.s,
        )
        self.assertIn(str(evaluation.id), {row["id"] for row in rows})
        self.assertNotEqual(replacement.id, old_affectation.id)

    def test_primary_trimester_requires_two_months_plus_trimester_composition(self):
        primary = self.add(m.SchoolCycle(
            establishment_id=self.tenant.id,
            code="PRIMAIRE",
            name="Primaire",
            status="active",
        ))
        primary_class = self.add(m.SchoolClass(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            cycle_id=primary.id,
            name="CM1 test",
            status="active",
        ))
        subject = self.add(m.Subject(
            establishment_id=self.tenant.id,
            name=f"Primaire {uuid.uuid4()}",
            status="active",
        ))
        # Old imported databases can contain this legacy rule. It must not
        # reduce the new fixed trimester requirement back to one composition.
        self.add(m.EvaluationRule(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            cycle_id=primary.id,
            evaluation_type="composition",
            label="Composition",
            expected_count=1,
            contributes_to_average=True,
            is_required=True,
            sort_order=30,
            status="active",
        ))

        def evaluation(code, label):
            return self.add(m.Evaluation(
                establishment_id=self.tenant.id,
                class_id=primary_class.id,
                subject_id=subject.id,
                academic_year_id=self.year.id,
                academic_period_id=self.periods[0].id,
                name=label,
                type="composition",
                exam_code=code,
                period="T1",
                max_value=10,
                status="submitted",
            ))

        october = evaluation("composition_octobre", "Composition du mois d’Octobre")
        november = evaluation("composition_novembre", "Composition du mois de Novembre")

        selected, missing = m.evaluation_policy_for_class(
            self.s, primary_class, [october, november], self.periods[0]
        )
        self.assertEqual(selected, [])
        self.assertEqual(
            {item.get("eventCode") for item in missing},
            {"composition"},
        )

        trimester = evaluation("composition", "Composition du 1er trimestre")
        selected, missing = m.evaluation_policy_for_class(
            self.s, primary_class, [october, november, trimester], self.periods[0]
        )
        self.assertEqual(missing, [])
        self.assertEqual(
            {m.normalized_evaluation_event(item) for item in selected},
            {"composition_octobre", "composition_novembre", "composition"},
        )

    def test_primary_rejects_devoirs_and_college_lycee_keep_them(self):
        primary = self.add(m.SchoolCycle(
            establishment_id=self.tenant.id,
            code="PRIMAIRE",
            name="Primaire",
            status="active",
        ))
        primary_class = self.add(m.SchoolClass(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            cycle_id=primary.id,
            name="Primaire cycle rules",
            status="active",
        ))
        with self.assertRaises(m.HTTPException) as rejected:
            m.validate_program_type_for_class(
                primary_class, "devoir", "devoir_1", self.s
            )
        self.assertEqual(rejected.exception.status_code, 422)

        # The existing fixture is a collège class and keeps D1/D2/composition.
        m.validate_program_type_for_class(
            self.cl, "devoir", "devoir_1", self.s
        )
        m.validate_program_type_for_class(
            self.cl, "devoir", "devoir_2", self.s
        )
        m.validate_program_type_for_class(
            self.cl, "composition", "composition", self.s
        )

    def test_primary_trimester_event_mapping_for_all_three_periods(self):
        self.assertEqual(
            set(m.primary_trimester_composition_events(self.periods[0])),
            {"composition_octobre", "composition_novembre", "composition"},
        )
        self.assertEqual(
            set(m.primary_trimester_composition_events(self.periods[1])),
            {"composition_janvier", "composition_fevrier", "composition"},
        )
        self.assertEqual(
            set(m.primary_trimester_composition_events(self.periods[2])),
            {"composition_avril", "composition_mai", "composition"},
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
