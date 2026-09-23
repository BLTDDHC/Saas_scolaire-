"""Published student-result projections; every write is rolled back."""
import unittest
from unittest.mock import patch

from app import main as m
import test_behavior_foundations as fixtures


class StudentResultsView(unittest.TestCase):
    add = fixtures.BehaviorFoundations.add
    assign = fixtures.BehaviorFoundations.assign
    cleanup = fixtures.BehaviorFoundations.cleanup

    def setUp(self):
        fixtures.BehaviorFoundations.setUp(self)
        self.tenant.enabled_modules = [*self.tenant.enabled_modules, 'grades']
        self.student = self.students[0]
        self.student.registration_number = 'MAT-RESULT-001'
        self.s.flush()

    def official(self):
        student_id = str(self.student.id)
        ordinary = {
            'studentId': student_id,
            'studentName': 'Rollback S0',
            'average': 14.5,
            'rank': 2,
            'subjects': [{
                'subjectId': 'subject-math',
                'subject': 'Mathématiques',
                'average': 14.5,
                'coefficient': 1,
                'point': 14.5,
                'grades': [{
                    'evaluation': 'Devoir 1', 'type': 'devoir',
                    'value': 15, 'maxValue': 20,
                }],
            }],
        }
        exam = {
            'event': 'BEPC Blanc',
            'students': [{
                'studentId': student_id, 'average': 13, 'rank': 3,
                'subjects': [{
                    'subject': 'Mathématiques', 'average': 13,
                    'grades': [{'value': 13, 'maxValue': 20}],
                }],
            }],
        }
        return {
            'calculationStatus': 'official',
            'students': [ordinary],
            'eventResults': {'bepc_blanc': exam},
        }

    def test_student_view_uses_only_official_snapshot_and_separates_exams(self):
        with patch.object(m, 'school_results', return_value=self.official()):
            result = m.student_results(
                self.student.id, self.year.id, self.admin, self.s
            )
        self.assertEqual(result['registration']['cycleCode'], 'COLLEGE')
        self.assertEqual(len(result['periods']), 3)
        period = result['periods'][0]
        self.assertEqual(period['average'], 14.5)
        self.assertEqual(period['averageScale'], 20)
        self.assertEqual(period['rank'], 2)
        self.assertEqual(period['mention'], 'Bien')
        self.assertEqual(period['subjects'][0]['grades'][0]['value'], 15)
        self.assertEqual(period['subjects'][0]['grades'][0]['maxValue'], 20)
        self.assertEqual(period['exams'][0]['code'], 'bepc_blanc')
        self.assertEqual(period['exams'][0]['subjects'][0]['grades'][0]['value'], 13)


    def test_submitted_note_is_visible_before_official_result(self):
        affectation = self.s.scalar(m.select(m.Affectation).where(
            m.Affectation.class_id == self.cl.id,
        ))
        evaluation = self.add(m.Evaluation(
            establishment_id=self.tenant.id,
            class_id=self.cl.id,
            subject_id=affectation.subject_id,
            academic_year_id=self.year.id,
            academic_period_id=self.periods[0].id,
            affectation_id=affectation.id,
            name='Devoir 1',
            type='devoir',
            exam_code='devoir_1',
            period='T1',
            max_value=20,
            status='submitted',
            created_by=m.uuid.UUID(self.principals[0].id),
        ))
        self.add(m.Grade(
            establishment_id=self.tenant.id,
            student_id=self.student.id,
            evaluation_id=evaluation.id,
            class_id=self.cl.id,
            subject_id=affectation.subject_id,
            teacher_id=affectation.teacher_id,
            affectation_id=affectation.id,
            value=16,
            max_value=20,
            presence='present',
            status='submitted',
        ))
        with patch.object(m, 'school_results', return_value={
            'calculationStatus': 'waiting', 'students': [],
        }):
            result = m.student_results(
                self.student.id, self.year.id, self.admin, self.s
            )
        self.assertEqual(result['periods'], [])
        self.assertEqual(len(result['notes']), 1)
        self.assertEqual(result['notes'][0]['evaluation'], 'Devoir 1')
        self.assertEqual(result['notes'][0]['value'], 16)
        self.assertEqual(result['notes'][0]['periodType'], 'trimester')
        self.assertEqual(result['notes'][0]['presence'], 'present')

    def test_period_metadata_distinguishes_month_from_trimester(self):
        month = self.add(m.AcademicPeriod(
            establishment_id=self.tenant.id,
            academic_year_id=self.year.id,
            parent_period_id=self.periods[0].id,
            code='OCT',
            name='Octobre',
            period_type='month',
            sort_order=2,
        ))
        with patch.object(m, 'school_results', return_value=self.official()):
            result = m.student_results(
                self.student.id, self.year.id, self.admin, self.s
            )
        october = next(item for item in result['periods']
                       if item['periodId'] == str(month.id))
        self.assertEqual(october['period'], 'Octobre')
        self.assertEqual(october['periodType'], 'month')
        self.assertEqual(october['parentPeriodId'], str(self.periods[0].id))

    def test_unofficial_result_is_not_exposed(self):
        with patch.object(m, 'school_results', return_value={
            'calculationStatus': 'stale', 'students': [],
        }):
            result = m.student_results(
                self.student.id, self.year.id, self.admin, self.s
            )
        self.assertEqual(result['periods'], [])


if __name__ == '__main__':
    unittest.main()
