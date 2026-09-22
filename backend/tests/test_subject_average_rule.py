import unittest

from app import main as m


class SubjectAverageRuleTests(unittest.TestCase):
    def test_college_uses_mc_then_composition(self):
        average, mc, composition = m.school_subject_average(
            'COLLEGE',
            [('devoir_1', 10), ('devoir_2', 14), ('composition', 18)],
        )
        self.assertEqual(mc, 12)
        self.assertEqual(composition, 18)
        self.assertEqual(average, 15)
        self.assertNotEqual(average, 14)  # ancienne moyenne simple des 3 notes

    def test_lycee_uses_same_subject_rule_before_coefficient(self):
        average, mc, composition = m.school_subject_average(
            'LYCEE',
            [('devoir_1', 13), ('devoir_2', 17), ('composition', 11)],
        )
        self.assertEqual(mc, 15)
        self.assertEqual(composition, 11)
        self.assertEqual(average, 13)
        self.assertEqual(average * 5, 65)

    def test_primary_keeps_contributing_average(self):
        average, mc, composition = m.school_subject_average(
            'PRIMAIRE', [('composition', 8)],
        )
        self.assertEqual(average, 8)
        self.assertIsNone(mc)
        self.assertIsNone(composition)


if __name__ == '__main__':
    unittest.main()
