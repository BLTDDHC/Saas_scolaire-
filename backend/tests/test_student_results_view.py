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
