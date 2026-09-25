import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.mva_v2.evidence_memory import cards_from_result, format_memory, frame_cards_from_text, select_memory
from app.mva_v2.frame_batch import validate_frame_batch
from app.mva_v2.video_context import format_video_context
from app.mva_v2.video_priority import VideoPriorities


class AgentMemoryFeatureTests(unittest.TestCase):
    def setUp(self):
        self.videos = [{"video_id": "a.mp4", "duration": 20, "meta": {"id": 11}},
                       {"video_id": "b.mp4", "duration": 8, "meta": {"id": 22}}]

    def test_cards_are_source_linked_candidate_observations(self):
        cards = cards_from_result("search_video_text", {
            "matches": [{"timestamp_sec": 12.5, "text": "东门出口"},
                        {"timestamp_sec": float("nan"), "text": "invalid"}],
        }, self.videos, self.videos[1])
        self.assertEqual(1, len(cards))
        self.assertEqual(("b.mp4", 22, 12.5, "index_candidate"),
                         (cards[0]["video_id"], cards[0]["segment_id"],
                          cards[0]["timestamp_sec"], cards[0]["kind"]))
        self.assertIn("需画面核验", format_memory(cards))

    def test_memory_deduplicates_and_limits_video_frames(self):
        cards = cards_from_result("search_objects", {
            "sampled_results": [{"timestamp_sec": i, "class_name": "person", "track_id": str(i)}
                                for i in range(9)]
        }, self.videos, self.videos[0])
        retrieved = select_memory(cards, "person", limit=18)
        self.assertLessEqual(len(retrieved), 5)

    def test_visual_observation_requires_an_actually_read_frame(self):
        cards, answer = frame_cards_from_text(
            "FRAME_OBSERVATION a.mp4 4.0: 人物从画面左侧走向出口\n答案：不确定",
            self.videos, [{"video_id": "a.mp4", "timestamp_sec": 4, "status": "image_attached"}])
        self.assertEqual("答案：不确定", answer)
        self.assertEqual("frame_description", cards[0]["kind"])
        rejected, untouched = frame_cards_from_text(
            "FRAME_OBSERVATION a.mp4 4.0: 未读帧的猜测", self.videos, [])
        self.assertEqual([], rejected)
        self.assertTrue(untouched.startswith("FRAME_OBSERVATION"))

    def test_video_priority_does_not_treat_metadata_as_visual_evidence(self):
        board = VideoPriorities(self.videos)
        board.update('{"video_scores":[{"video_index":1,"relevance":0.9,"evidence":0.8}]}')
        self.assertEqual(0, board.entries[0]["evidence"])
        board.mark_explored("a.mp4")
        board.update({"video_scores": [{"video_index": 1, "relevance": 0.9, "evidence": 0.8}]})
        self.assertEqual(0.8, board.entries[0]["evidence"])
        self.assertIn("视频 2", board.guidance())

    def test_batch_frames_and_video_metadata(self):
        frames = validate_frame_batch(self.videos, [
            {"video_id": "a.mp4", "timestamp_sec": 12.5},
            {"video_id": "b.mp4", "timestamp_sec": 4},
        ])
        self.assertEqual([1, 2], [row[0] for row in frames])
        with self.assertRaises(ValueError):
            validate_frame_batch(self.videos, [{"video_id": "a.mp4", "timestamp_sec": 21}])
        line = format_video_context(2, {**self.videos[1], "remark": "东门", "fps": 25.0,
                                        "frame_count": 200, "meta": {"status": "completed"}})
        self.assertIn("25.00 FPS", line)
        self.assertIn("200 帧", line)


if __name__ == "__main__":
    unittest.main()
