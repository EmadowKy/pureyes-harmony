import importlib.util
from pathlib import Path
import unittest


module_path = Path(__file__).resolve().parents[1] / "app" / "mva_v2" / "frame_batch.py"
spec = importlib.util.spec_from_file_location("frame_batch", module_path)
batch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(batch)


class FrameBatchTests(unittest.TestCase):
    def setUp(self):
        self.videos = [{"video_id": "a.mp4", "duration": 20},
                       {"video_id": "b.mp4", "duration": 8}]

    def test_can_select_different_frames_across_selected_videos(self):
        frames = batch.validate_frame_batch(self.videos, [
            {"video_id": "a.mp4", "timestamp_sec": 12.5},
            {"video_id": "b.mp4", "timestamp_sec": 4},
        ])
        self.assertEqual([(1, "a.mp4", 12.5), (2, "b.mp4", 4.0)],
                         [(index, item["video_id"], sec) for index, item, sec in frames])

    def test_rejects_invalid_video_time_duplicates_and_unbounded_batch(self):
        bad = [
            [{"video_id": "outside.mp4", "timestamp_sec": 1}],
            [{"video_id": "b.mp4", "timestamp_sec": 9}],
            [{"video_id": "a.mp4", "timestamp_sec": float("nan")}],
            [{"video_id": "a.mp4", "timestamp_sec": True}],
            [{"video_id": "a.mp4", "timestamp_sec": 1}] * 2,
            [{"video_id": "a.mp4", "timestamp_sec": index} for index in range(5)],
        ]
        for requests in bad:
            with self.subTest(requests=requests), self.assertRaises(ValueError):
                batch.validate_frame_batch(self.videos, requests)


if __name__ == "__main__":
    unittest.main()

