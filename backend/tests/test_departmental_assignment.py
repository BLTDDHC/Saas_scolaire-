import unittest

from fastapi import HTTPException

from app import main as m
import test_behavior_foundations as fixtures


class DepartmentalAssignmentRules(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)

    def test_departmental_assignment_allowed_for_college(self):
        body = m.EvaluationProgramInput(
            title="Devoir départemental",
            type="exam",
            examCode="devoir_departemental",
            classIds=[self.cl.id],
            periodId=self.periods[0].id,
        )
        self.assertEqual(body.exam_code, "devoir_departemental")
        m.validate_program_type_for_class(
            self.cl,
            body.type,
            body.exam_code,
            self.s,
        )

    def test_departmental_assignment_refused_for_primary(self):
        primary = self.add(m.SchoolCycle(
            establishment_id=self.tenant.id,
            code="PRIMAIRE",
            name="Primaire",
        ))
        school_class = self.add(m.SchoolClass(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            cycle_id=primary.id,
            name="CM1 Test",
            status="active",
        ))
        with self.assertRaises(HTTPException) as error:
            m.validate_program_type_for_class(
                school_class,
                "exam",
                "devoir_departemental",
                self.s,
            )
        self.assertEqual(error.exception.status_code, 422)

    def test_departmental_assignment_not_treated_as_ordinary_grade(self):
        evaluation = m.Evaluation(
            establishment_id=self.tenant.id,
            class_id=self.cl.id,
            subject_id=self.s.scalar(m.select(m.Subject.id)),
            academic_year_id=self.year.id,
            academic_period_id=self.periods[0].id,
            name="Devoir départemental",
            type="exam",
            exam_code="devoir_departemental",
            period="T1",
            max_value=20,
            status="draft",
            created_by=m.uuid.UUID(self.principals[0].id),
        )
        self.assertEqual(
            m.normalized_evaluation_event(evaluation),
            "devoir_departemental",
        )
        with self.assertRaises(ValueError):
            m.school_subject_average(
                "COLLEGE",
                [("devoir_departemental", 15.0)],
            )


if __name__ == "__main__":
    unittest.main()
