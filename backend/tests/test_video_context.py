import importlib.util
from pathlib import Path
import unittest


module_path = Path(__file__).resolve().parents[1] / "app" / "mva_v2" / "video_context.py"
spec = importlib.util.spec_from_file_location("video_context", module_path)
video_context = importlib.util.module_from_spec(spec)
spec.loader.exec_module(video_context)


class VideoContextTests(unittest.TestCase):
    def test_video_facts_are_available_before_tool_calls(self):
        line = video_context.format_video_context(2, {
            "remark": "东门", "video_id": "segment.mp4", "duration": 12.5,
            "fps": 25.0, "frame_count": 312,
            "meta": {"status": "completed", "sample_fps": 1.0, "resolution": "720P"},
        })
        for fact in ('视频 2', '12.5 秒', '25.00 FPS', '312 帧', 'completed', '1.0 FPS', '720P'):
            self.assertIn(fact, line)

    def test_unknown_physical_metadata_is_explicit(self):
        line = video_context.format_video_context(1, {
            "remark": "片段", "video_id": "clip.mp4", "duration": 0.0,
            "fps": float("nan"), "frame_count": 0, "meta": {"status": "none"},
        })
        self.assertIn('帧率和总帧数未知', line)
        self.assertNotIn('索引采样', line)


if __name__ == "__main__":
    unittest.main()

