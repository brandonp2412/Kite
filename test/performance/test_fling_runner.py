import unittest

from tool.perf.run_chat_list_fling import grade_report


class FlingRunnerTest(unittest.TestCase):
    def test_fails_even_if_driver_claims_success(self):
        flings = [dict(valid=True, slow_frames=0, cadence_gap_count=0) for _ in range(4)]
        flings[1]['slow_frames'] = 1
        self.assertEqual(grade_report({'schema_version': 2, 'flings': flings}), 1)

    def test_missing_or_invalid_measurement_does_not_pass(self):
        self.assertEqual(grade_report({}), 2)
        self.assertEqual(grade_report({'flings': [dict(valid=False)] * 4}), 2)

    def test_all_four_smooth_flings_pass(self):
        self.assertEqual(grade_report({
            'schema_version': 2,
            'flings': [dict(valid=True, slow_frames=0, cadence_gap_count=0) for _ in range(4)]
        }), 0)

    def test_cheap_frames_with_missing_refresh_fail(self):
        flings = [dict(valid=True, slow_frames=0, cadence_gap_count=1)] * 4
        self.assertEqual(grade_report({'schema_version': 2, 'flings': flings}), 1)

    def test_legacy_or_missing_cadence_cannot_pass(self):
        flings = [dict(valid=True, slow_frames=0)] * 4
        self.assertEqual(grade_report({'flings': flings}), 2)
        self.assertEqual(grade_report({'schema_version': 2, 'flings': flings}), 2)
