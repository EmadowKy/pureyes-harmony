import unittest
import importlib.util
from pathlib import Path

module_path = Path(__file__).resolve().parents[1] / "app" / "mva_v2" / "video_priority.py"
spec = importlib.util.spec_from_file_location("video_priority", module_path)
video_priority = importlib.util.module_from_spec(spec)
spec.loader.exec_module(video_priority)
VideoPriorities = video_priority.VideoPriorities


class VideoPriorityTests(unittest.TestCase):
    def setUp(self):
        self.board = VideoPriorities([
            {"video_id": "camera-a.mp4"}, {"video_id": "camera-b.mp4"},
        ])

    def test_relevant_unexplored_video_moves_ahead_after_first_is_explored(self):
        self.board.mark_explored("camera-a.mp4")
        self.board.update('{"video_scores": ['
                          '{"video_index": 1, "relevance": 0.9, "evidence": 0.8},'
                          '{"video_index": 2, "relevance": 0.8, "evidence": 0.9}]}')
        self.assertEqual(0, self.board.entries[1]["evidence"])
        self.assertLess(self.board.priority(self.board.entries[0]),
                        self.board.priority(self.board.entries[1]))
        self.assertIn("视频 2", self.board.guidance().splitlines()[1])

    def test_invalid_or_unselected_scores_are_ignored(self):
        self.board.update('{"video_scores": ['
                          '{"video_index": 1, "relevance": "1", "evidence": 0.9},'
                          '{"video_index": 2, "relevance": -1, "evidence": 2},'
                          '{"video_index": 3, "relevance": 1, "evidence": 1}]}')
        self.assertEqual([0.5, 0.5], [item["relevance"] for item in self.board.entries])
        self.assertEqual([0, 0], [item["evidence"] for item in self.board.entries])
        self.board.update("not json")
        self.assertEqual(2, len(self.board.entries))


if __name__ == "__main__":
    unittest.main()

