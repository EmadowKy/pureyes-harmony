import unittest
import importlib.util
from pathlib import Path


module_path = Path(__file__).resolve().parents[1] / "app" / "workspaces" / "face_engine.py"
spec = importlib.util.spec_from_file_location("face_engine", module_path)
face_engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(face_engine)
assign_frame, cosine = face_engine.assign_frame, face_engine.cosine
assign_frame_by_bbox = face_engine.assign_frame_by_bbox
configured_face_backend = face_engine.configured_face_backend


class FaceEngineTests(unittest.TestCase):
    def test_face_backend_is_only_read_from_server_environment(self):
        from unittest.mock import patch
        with patch.dict("os.environ", {"FACE_RECOGNITION_BACKEND": "harmony"}):
            self.assertEqual(configured_face_backend(), "harmony")
        with patch.dict("os.environ", {"FACE_RECOGNITION_BACKEND": "invalid"}):
            with self.assertRaises(ValueError):
                configured_face_backend()

    def test_each_track_is_assigned_only_once_per_frame(self):
        tracks = [{"embedding": [1.0, 0.0], "last_time": 1.0}]
        faces = [{"embedding": [1.0, 0.0]}, {"embedding": [0.99, 0.01]}]
        self.assertEqual(len(assign_frame(tracks, faces, 2.0)), 1)

    def test_two_simultaneous_people_keep_distinct_tracks(self):
        tracks = [
            {"embedding": [1.0, 0.0], "last_time": 1.0},
            {"embedding": [0.0, 1.0], "last_time": 1.0},
        ]
        faces = [{"embedding": [0.0, 1.0]}, {"embedding": [1.0, 0.0]}]
        self.assertEqual(assign_frame(tracks, faces, 2.0), {0: 1, 1: 0})
        self.assertEqual(assign_frame(tracks, faces, 5.0), {})

    def test_invalid_vectors_cannot_match(self):
        self.assertEqual(cosine([0, 0], [1, 0]), -1)
        self.assertEqual(cosine([float("nan"), 1], [1, 0]), -1)
        self.assertEqual(cosine(["broken", 1], [1, 0]), -1)

    def test_provisional_spatial_assignment_keeps_two_faces_separate(self):
        tracks = [{"bbox": (0, 0, 60, 60), "last_time": 1.0},
                  {"bbox": (100, 0, 160, 60), "last_time": 1.0}]
        faces = [{"bbox": (102, 0, 162, 60)}, {"bbox": (2, 0, 62, 60)}]
        self.assertEqual(assign_frame_by_bbox(tracks, faces, 2.0), {0: 1, 1: 0})
        self.assertEqual(assign_frame_by_bbox(tracks, faces, 5.0), {})


if __name__ == "__main__":
    unittest.main()

