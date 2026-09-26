"""A worker must observe video features committed by another process."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

from app.mva_v2 import database  # noqa: E402


class DatabaseCrossProcessTest(unittest.TestCase):
    def test_snapshot_refreshes_after_another_worker_writes_and_deletes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "features.json")
            with patch.object(database, "DB_FILE_PATH", path):
                database.SpatiotemporalDB._loaded_path = None
                db = database.SpatiotemporalDB()
                self.assertEqual(db.snapshot(), [])

                script = """import sys
from app.mva_v2 import database
database.DB_FILE_PATH = sys.argv[1]
db = database.SpatiotemporalDB()
if sys.argv[2] == 'insert':
    db.insert([{'video_id': 'camera.mp4', 'workspace_id': 1}])
else:
    db.delete_video('camera.mp4', workspace_id=1)
"""
                env = {**os.environ, "PYTHONPATH": str(BACKEND_DIR)}
                subprocess.check_call([sys.executable, "-c", script, path, "insert"], env=env)
                self.assertEqual(len(db.snapshot()), 1)
                subprocess.check_call([sys.executable, "-c", script, path, "delete"], env=env)
                self.assertEqual(db.snapshot(), [])


if __name__ == "__main__":
    unittest.main()
