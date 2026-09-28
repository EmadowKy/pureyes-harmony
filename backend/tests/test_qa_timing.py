import json
import unittest
from datetime import datetime, timedelta
from app.models.qa_record import QARecord


class QATimingTests(unittest.TestCase):
    def record(self, status='completed', progress=None):
        return QARecord(id='timing', workspace_id=1, creator_id='admin', question='test',
            status=status, created_at=datetime(2026, 9, 28, 10), progress_json=json.dumps(progress or []))

    def test_completed_time_is_stable_and_ignores_intermediate_completion(self):
        record = self.record(progress=[
            {'stage': 'reasoning', 'status': 'completed', 'at': '2026-09-28T10:01:00Z'},
            {'stage': 'answering', 'status': 'completed', 'at': '2026-09-28T10:02:03.250Z'}])
        self.assertEqual(123.25, record.to_dict()['elapsed_seconds'])
        self.assertEqual(record.timing(), record.timing())
        self.assertEqual('2026-09-28T10:02:03.250000Z', record.timing()['finished_at'])

    def test_failed_and_stopped_times(self):
        for status in ('failed', 'stopped'):
            record = self.record(status, [{'stage': 'system', 'status': status, 'at': '2026-09-28T18:01:00+08:00'}])
            self.assertEqual(60, record.timing()['elapsed_seconds'])

    def test_missing_or_invalid_old_timestamps_are_unknown(self):
        for progress in ([], [{'stage': 'answering', 'status': 'completed', 'at': 'invalid'}], [None]):
            self.assertIsNone(self.record(progress=progress).timing()['elapsed_seconds'])
        record = self.record()
        record.progress_json = 'invalid'
        self.assertIsNone(record.timing()['elapsed_seconds'])

    def test_running_uses_server_clock(self):
        record = self.record('processing')
        record.created_at = datetime.utcnow() - timedelta(seconds=15)
        self.assertGreaterEqual(record.timing()['elapsed_seconds'], 15)
        self.assertIsNone(record.timing()['finished_at'])


if __name__ == '__main__':
    unittest.main()
