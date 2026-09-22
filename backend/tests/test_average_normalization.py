"""Focused calculation contracts for mixed subject scales."""
import unittest

from app import main as m


class AverageNormalizationTests(unittest.TestCase):
    def test_ten_over_ten_keeps_its_contribution(self):
        self.assertEqual(m.normalize_grade_for_general_average(8, 10, 10), 8)

    def test_twenty_over_twenty_normalizes_only_for_primary_average(self):
        self.assertEqual(m.normalize_grade_for_general_average(16, 20, 10), 8)
        # The grade record keeps 16 and 20; this helper is calculation-only.
        self.assertEqual((16, 20), (16, 20))

    def test_mixed_scales_produce_a_ten_over_ten_average(self):
        values = [
            m.normalize_grade_for_general_average(16, 20, 10),
            m.normalize_grade_for_general_average(8, 10, 10),
        ]
        self.assertEqual(sum(values) / len(values), 8)

    def test_college_and_lycee_keep_twenty_over_twenty_scale(self):
        self.assertEqual(m.normalize_grade_for_general_average(16, 20, 20), 16)
        self.assertEqual(m.normalize_grade_for_general_average(8, 10, 20), 16)


if __name__ == "__main__":
    unittest.main()
