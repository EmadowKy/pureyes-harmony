import importlib.util
from pathlib import Path
import unittest


module_path = Path(__file__).resolve().parents[1] / "app" / "mva_v2" / "evidence_memory.py"
spec = importlib.util.spec_from_file_location("evidence_memory", module_path)
memory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memory)


class EvidenceMemoryTests(unittest.TestCase):
    def setUp(self):
        self.videos = [
            {"video_id": "a.mp4", "meta": {"id": 11}},
            {"video_id": "b.mp4", "meta": {"id": 22}},
        ]

    def test_index_card_keeps_source_video_time_and_candidate_status(self):
        cards = memory.cards_from_result("search_video_text", {
            "matches": [{"timestamp_sec": 12.5, "text": "东门出口"},
                        {"timestamp_sec": float("nan"), "text": "坏记录"}],
        }, self.videos, self.videos[1])
        self.assertEqual(1, len(cards))
        self.assertEqual(("b.mp4", 22, 12.5, "index_candidate"),
                         (cards[0]["video_id"], cards[0]["segment_id"],
                          cards[0]["timestamp_sec"], cards[0]["kind"]))
        self.assertIn("东门出口", memory.format_memory(cards))

    def test_face_search_only_remembers_selected_segments(self):
        cards = memory.cards_from_result("search_face_tracks", {
            "matched_face_groups": [{"face_group_name": "人脸 #2", "occurrences": [
                {"segment_id": 22, "timestamp_sec": 6},
                {"segment_id": 999, "timestamp_sec": 7},
            ]}],
        }, self.videos)
        self.assertEqual(["b.mp4"], [card["video_id"] for card in cards])

    def test_retrieval_deduplicates_and_limits_candidates(self):
        first = memory.frame_card(self.videos, "a.mp4", 4, "红衣人进入东门")
        other = memory.frame_card(self.videos, "b.mp4", 9, "白车经过出口")
        cards = memory.select_memory([first, first, other], "东门的红衣人", limit=2)
        self.assertEqual(2, len(cards))
        self.assertEqual({"a.mp4", "b.mp4"}, {card["video_id"] for card in cards})
        self.assertIsNone(memory.frame_card(self.videos, "outside.mp4", 4, "未知"))

    def test_batch_frame_metadata_is_not_stored_as_visual_observation(self):
        result = {"matches": [{"timestamp_sec": 4, "class_name": "视频 1 画面"}]}
        self.assertEqual([], memory.cards_from_result("read_frames", result,
                                                     self.videos, self.videos[0]))


if __name__ == "__main__":
    unittest.main()

