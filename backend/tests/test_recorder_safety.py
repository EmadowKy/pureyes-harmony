import os
import sys
import time
import subprocess
import tempfile
import unittest
from pathlib import Path
from datetime import datetime, timedelta
from unittest.mock import patch
from types import SimpleNamespace
from app.core import recorder


class RecorderSafetyTests(unittest.TestCase):
    def test_low_disk_only_removes_closed_old_files(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / '1'
            directory.mkdir()
            now = datetime.now()
            old = directory / ((now - timedelta(minutes=10)).strftime('%Y%m%d_%H%M%S') + '.mp4')
            recent = directory / (now.strftime('%Y%m%d_%H%M%S') + '.mp4')
            active = directory / ((now - timedelta(days=2)).strftime('%Y%m%d_%H%M%S') + '.mp4')
            for f in (old, recent, active):
                f.write_bytes(b'video')
            for f in (old, active):
                os.utime(f, (time.time() - 600, time.time() - 600))
            with patch.object(recorder, 'VIDEO_STORAGE_BASE', folder), \
                    patch.object(recorder, '_open_recording_paths', return_value={str(active.resolve())}), \
                    patch.object(recorder.shutil, 'disk_usage', return_value=SimpleNamespace(free=0)):
                recorder._delete_expired_recordings()
            self.assertFalse(old.exists())
            self.assertTrue(recent.exists())
            self.assertTrue(active.exists())

    def test_retention_preserves_current_writer_and_unrelated_files(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / '1'
            directory.mkdir()
            name = (datetime.now() - timedelta(days=2)).strftime('%Y%m%d_%H%M%S')
            active = directory / (name + '.mp4')
            unrelated = directory / 'keep.txt'
            active.write_bytes(b'video')
            unrelated.write_bytes(b'keep')
            with patch.object(recorder, 'VIDEO_STORAGE_BASE', folder), \
                    patch.object(recorder, '_open_recording_paths', return_value=set()):
                recorder._delete_expired_recordings()
            self.assertTrue(active.exists())
            self.assertTrue(unrelated.exists())

    @unittest.skipUnless(os.name == 'posix', 'Linux process lock')
    def test_child_holds_lock_after_parent_closes_descriptor(self):
        with tempfile.TemporaryDirectory() as folder:
            fd = recorder._acquire_recording_lock(folder)
            child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'], pass_fds=(fd,))
            os.close(fd)
            try:
                self.assertEqual(-1, recorder._acquire_recording_lock(folder))
            finally:
                child.terminate()
                child.wait(timeout=5)
            next_fd = recorder._acquire_recording_lock(folder)
            self.assertGreaterEqual(next_fd, 0)
            os.close(next_fd)


if __name__ == '__main__':
    unittest.main()
