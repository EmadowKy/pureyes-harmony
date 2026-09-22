"""Regression coverage for CLIP/OCR evidence storage and Agent-facing tools."""

import asyncio
import os
import tempfile
import unittest
from unittest.mock import patch

import cv2
import numpy as np

from app.mva_v2 import database
from app.mva_v2.agents import ReActTools
from app.mva_v2.pipeline import BoundingBox, ByteTracker, JITVideoPipeline, TrackedObject
from app.mva_v2.vision_models import OnnxTextRecognizer, VisionModelUnavailable


class FakeSemanticEmbedder:
    def embed_text(self, text):
        self.last_text = text
        return [1.0, 0.0, 0.0]


class FakeDetector:
    def detect(self, frame):
        return [BoundingBox(4, 5, 28, 45, 0.95, 0, "person", 9)]


class FakeTracker:
    def update(self, boxes, frame):
        box = boxes[0]
        return [TrackedObject("track_9", box, 0, frame[box.y1:box.y2, box.x1:box.x2])]


class FakeReId:
    def extract_reid(self, crop):
        return np.array([0.0, 1.0], dtype=np.float32)


class FakeClip:
    def embed_image(self, image):
        return np.array([1.0, 0.0, 0.0], dtype=np.float32)


class FakeOcr:
    def extract(self, image):
        return [{"text": "园区东门", "confidence": 0.97, "bbox": [2, 2, 30, 14]}]


class MultimodalEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "evidence.json")
        self.db_path_patch = patch.object(database, "DB_FILE_PATH", self.db_path)
        self.db_path_patch.start()
        database.SpatiotemporalDB._shared_records = []
        database.SpatiotemporalDB._loaded_path = None
        self.db = database.SpatiotemporalDB()
        self.db.insert([
            {
                "video_id": "camera-a.mp4", "workspace_id": 1, "timestamp": 4.0,
                "frame_idx": 100, "track_id": "scene_100", "class_name": "scene",
                "bbox": [0, 0, 1920, 1080], "clip_vector": [0.99, 0.01, 0.0],
                "reid_vector": [], "modality": "scene",
            },
            {
                "video_id": "camera-a.mp4", "workspace_id": 1, "timestamp": 7.5,
                "frame_idx": 188, "track_id": "text_188_0", "class_name": "text",
                "bbox": [10, 10, 120, 40], "clip_vector": [], "reid_vector": [],
                "modality": "ocr", "ocr_text": "东门出口 A12345", "ocr_confidence": 0.96,
            },
            {
                "video_id": "camera-b.mp4", "workspace_id": 1, "timestamp": 8.0,
                "frame_idx": 200, "track_id": "scene_200", "class_name": "scene",
                "bbox": [0, 0, 1920, 1080], "clip_vector": [0.0, 1.0, 0.0],
                "reid_vector": [], "modality": "scene",
            },
        ])

    def tearDown(self):
        self.db_path_patch.stop()
        database.SpatiotemporalDB._shared_records = []
        database.SpatiotemporalDB._loaded_path = None
        self.temp_dir.cleanup()

    def test_clip_search_returns_only_the_requested_video_with_similarity(self):
        results = self.db.search_clip_vectors([1.0, 0.0, 0.0], video_id="camera-a.mp4")
        self.assertEqual(1, len(results))
        self.assertEqual("scene_100", results[0]["track_id"])
        self.assertGreater(results[0]["semantic_similarity"], 0.9)

    def test_ocr_search_returns_timestamped_text_evidence(self):
        results = self.db.search_ocr_text("A12345", video_id="camera-a.mp4")
        self.assertEqual(1, len(results))
        self.assertEqual("东门出口 A12345", results[0]["ocr_text"])
        self.assertEqual(7.5, results[0]["timestamp"])

    def test_agent_tools_expose_real_semantic_and_ocr_results(self):
        embedder = FakeSemanticEmbedder()
        tools = ReActTools(self.db, semantic_embedder=embedder)

        semantic = tools.search_visual_semantics("红色轿车", "camera-a.mp4")
        ocr = tools.search_video_text("东门", "camera-a.mp4")

        self.assertTrue(semantic["available"])
        self.assertEqual("红色轿车", embedder.last_text)
        self.assertEqual("scene_100", semantic["matches"][0]["track_id"])
        self.assertEqual("东门出口 A12345", ocr["matches"][0]["text"])

    def test_fallback_tracker_keeps_a_fast_moving_target(self):
        tracker = ByteTracker()
        frames = [
            BoundingBox(520, 324, 579, 432, 0.9, 0, "person"),
            BoundingBox(543, 252, 595, 355, 0.9, 0, "person"),
            BoundingBox(586, 200, 640, 297, 0.9, 0, "person"),
        ]
        ids = [
            tracker.update([box], np.zeros((500, 800, 3), dtype=np.uint8))[0].track_id
            for box in frames
        ]
        self.assertEqual(["track_fallback_1"] * 3, ids)

    def test_identity_search_can_cross_selected_videos_only(self):
        self.db.insert([
            {"video_id": "camera-a.mp4", "workspace_id": 1, "timestamp": 1.0,
             "frame_idx": 1, "track_id": "person-a", "class_name": "person",
             "bbox": [0, 0, 20, 40], "clip_vector": [], "reid_vector": [1.0, 0.0],
             "modality": "object"},
            {"video_id": "camera-b.mp4", "workspace_id": 1, "timestamp": 2.0,
             "frame_idx": 2, "track_id": "person-b", "class_name": "person",
             "bbox": [0, 0, 20, 40], "clip_vector": [], "reid_vector": [1.0, 0.0],
             "modality": "object"},
        ])
        tools = ReActTools(self.db)
        result = tools.spatiotemporal_search(
            "identity", "person-a", "camera-a.mp4",
            video_ids=["camera-a.mp4", "camera-b.mp4"],
        )
        self.assertIn("person-b", result["summary"]["unique_track_ids_list"])

    def test_unknown_object_query_does_not_return_ocr_rows(self):
        result = ReActTools(self.db).spatiotemporal_search(
            "semantic", "unclassified scene", "camera-a.mp4"
        )
        self.assertEqual(0, result["summary"]["total_matching_records"])

    def test_pipeline_persists_object_scene_and_ocr_records(self):
        video_path = os.path.join(self.temp_dir.name, "sample.avi")
        writer = cv2.VideoWriter(video_path, cv2.VideoWriter_fourcc(*"MJPG"), 5.0, (64, 48))
        for _ in range(2):
            writer.write(np.full((48, 64, 3), 120, dtype=np.uint8))
        writer.release()

        pipeline = object.__new__(JITVideoPipeline)
        pipeline.db_client = self.db
        pipeline.detector = FakeDetector()
        pipeline.tracker = FakeTracker()
        pipeline.extractor = FakeReId()
        pipeline.semantic_embedder = FakeClip()
        pipeline.text_recognizer = FakeOcr()
        pipeline._unavailable_modalities = set()

        asyncio.run(pipeline.process_clip(video_path, "sample.avi", 0.0, 0.2, sample_fps=5.0))
        records = self.db.snapshot()
        modalities = {record.get("modality") for record in records}
        object_record = next(record for record in records if record.get("modality") == "object")

        self.assertEqual({"object", "scene", "ocr"}, modalities)
        self.assertEqual([1.0, 0.0, 0.0], object_record["clip_vector"])
        self.assertEqual([0.0, 1.0], object_record["reid_vector"])

    def test_ocr_requires_explicit_local_onnx_models(self):
        with patch.dict(os.environ, {"OCR_MODEL_ROOT": ""}, clear=False):
            recognizer = OnnxTextRecognizer()
            self.assertFalse(recognizer.status["configured"])
            with self.assertRaises(VisionModelUnavailable):
                recognizer.extract(np.zeros((16, 16, 3), dtype=np.uint8))


if __name__ == "__main__":
    unittest.main()
