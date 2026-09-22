"""Batch grade loading keeps the same tenant, direction and teacher scope."""
import unittest
import uuid

from app import main as m
import test_behavior_foundations as fixtures


class GradeBatchLoading(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.school = m.public_school_id(self.s, self.tenant.id)
        self.admin = m.Principal(
            id=self.principals[0].id,
            role='admin',
            school_id=self.school,
            direction_id=str(uuid.uuid4()),
            direction_cycle_ids=[str(self.cycle.id)],
        )
        self.affectation = self.s.query(m.Affectation).filter_by(
            teacher_id=self.teachers[0].id, class_id=self.cl.id
        ).first()
        self.evaluation = self.add(m.Evaluation(
            establishment_id=self.tenant.id,
            class_id=self.cl.id,
            subject_id=self.affectation.subject_id,
            academic_year_id=self.year.id,
            academic_period_id=self.periods[0].id,
            affectation_id=self.affectation.id,
            name='Batch', type='devoir', period='T1', max_value=20,
        ))
        for student in self.students:
            self.add(m.Grade(
                establishment_id=self.tenant.id,
                student_id=student.id,
                evaluation_id=self.evaluation.id,
                class_id=self.cl.id,
                subject_id=self.affectation.subject_id,
                teacher_id=self.teachers[0].id,
                affectation_id=self.affectation.id,
                value=12, max_value=20,
            ))

    def test_admin_batch_matches_sheet_detail(self):
        batch = m.list_school_grades(self.year.id, None, self.admin, self.s)
        detail = m.list_evaluation_grades(
            self.evaluation.id, self.admin, self.s
        )
        self.assertEqual(batch, detail)
        self.assertEqual(len(batch), len(self.students))

    def test_direction_and_teacher_scope_are_preserved(self):
        denied = self.admin.model_copy(
            update={'direction_cycle_ids': [str(uuid.uuid4())]}
        )
        self.assertEqual(
            m.list_school_grades(self.year.id, None, denied, self.s), []
        )
        own = m.list_school_grades(
            self.year.id, None, self.principals[0], self.s
        )
        other = m.list_school_grades(
            self.year.id, None, self.principals[1], self.s
        )
        self.assertEqual(len(own), len(self.students))
        self.assertEqual(other, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
