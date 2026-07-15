import asyncio
import cv2
import numpy as np
from typing import List, Dict, Optional, Any, Callable
from dataclasses import dataclass
import uuid
import time
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class BoundingBox:
    x1: int
    y1: int
    x2: int
    y2: int
    confidence: float
    class_id: int
    class_name: str

@dataclass
class TrackedObject:
    track_id: str
    bbox: BoundingBox
    frame_idx: int
    image_crop: np.ndarray

@dataclass
class ProcessedFrame:
    video_id: str
    frame_idx: int
    timestamp_sec: float
    image: np.ndarray
    tracked_objects: List[TrackedObject]
    clip_embedding: Optional[np.ndarray] = None
    skip_heavy_processing: bool = False

class YoloDetector:
    def __init__(self):
        pass
    def detect(self, image: np.ndarray) -> List[BoundingBox]:
        time.sleep(0.02)
        if np.random.rand() > 0.5:
            return [BoundingBox(10, 10, 100, 100, 0.9, 0, "person")]
        return []

class ByteTracker:
    def __init__(self):
        self.active_tracks = {}
    def update(self, bboxes: List[BoundingBox], image: np.ndarray) -> List[TrackedObject]:
        time.sleep(0.01)
        tracked = []
        for box in bboxes:
            track_id = f"track_{uuid.uuid4().hex[:6]}"
            try:
                crop = image[box.y1:box.y2, box.x1:box.x2]
            except Exception:
                crop = np.zeros((64, 64, 3))
            tracked.append(TrackedObject(track_id, box, 0, crop))
        return tracked

class FeatureExtractor:
    def __init__(self):
        pass
    def extract_reid(self, crop: np.ndarray) -> np.ndarray:
        time.sleep(0.01)
        return np.random.rand(512).astype(np.float32)
    def extract_clip(self, image: np.ndarray) -> np.ndarray:
        time.sleep(0.04)
        return np.random.rand(512).astype(np.float32)

class JITVideoPipeline:
    """按需即时提取管线 (JIT Processing Engine)"""
    def __init__(self, db_client: Any):
        self.db_client = db_client
        self.detector = YoloDetector()
        self.tracker = ByteTracker()
        self.extractor = FeatureExtractor()
        self.frame_queue = asyncio.Queue(maxsize=50)
        
    def _detect_motion(self, prev_frame: np.ndarray, curr_frame: np.ndarray) -> bool:
        if prev_frame is None:
            return True
        gray_prev = cv2.cvtColor(prev_frame, cv2.COLOR_BGR2GRAY)
        gray_curr = cv2.cvtColor(curr_frame, cv2.COLOR_BGR2GRAY)
        diff = cv2.absdiff(gray_prev, gray_curr)
        _, thresh = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)
        return np.count_nonzero(thresh) > (curr_frame.shape[0] * curr_frame.shape[1] * 0.01)

    async def producer_video_reader(self, video_path: str, video_id: str, start_sec: float, end_sec: float, sample_fps: int = 1, progress_callback: Optional[Callable[[int], None]] = None):
        logger.info(f"[JIT] Extracting {video_id} from {start_sec}s to {end_sec}s...")
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        
        # 定位到指定时间
        cap.set(cv2.CAP_PROP_POS_MSEC, start_sec * 1000.0)
        frame_interval = int(fps / sample_fps) if fps > 0 else 30
        
        start_frame_idx = int(start_sec * fps)
        frame_idx = start_frame_idx
        end_frame_idx = int(end_sec * fps)
        prev_frame = None
        frames_processed = 0
        
        total_frames_to_process = max(1, end_frame_idx - start_frame_idx)
        
        while cap.isOpened() and frame_idx <= end_frame_idx:
            ret, frame = await asyncio.to_thread(cap.read)
            if not ret:
                break
                
            if frames_processed % frame_interval == 0:
                has_motion = await asyncio.to_thread(self._detect_motion, prev_frame, frame)
                if has_motion:
                    bboxes = await asyncio.to_thread(self.detector.detect, frame)
                    if bboxes:
                        tracked_objs = await asyncio.to_thread(self.tracker.update, bboxes, frame)
                        for t in tracked_objs:
                            t.frame_idx = frame_idx
                        
                        processed = ProcessedFrame(
                            video_id=video_id,
                            frame_idx=frame_idx,
                            timestamp_sec=frame_idx / fps,
                            image=frame,
                            tracked_objects=tracked_objs
                        )
                        
                        if self.frame_queue.qsize() > self.frame_queue.maxsize * 0.9:
                            processed.skip_heavy_processing = True
                        
                        await self.frame_queue.put(processed)
                if frame is not None:
                    prev_frame = frame.copy()
            
            # 回报进度 (稍微降低回调频率以免数据库写锁过于频繁)
            if progress_callback and (frames_processed % 5 == 0 or frame_idx == end_frame_idx):
                progress_pct = min(99, int((frame_idx - start_frame_idx) / total_frames_to_process * 100))
                progress_callback(progress_pct)
                
            frame_idx += 1
            frames_processed += 1
            await asyncio.sleep(0.001)
            
        cap.release()
        await self.frame_queue.put(None)
        logger.info(f"[JIT] Producer finished extracting clip.")

    async def consumer_feature_extractor(self):
        logger.info("[JIT] Started Consumer Feature Extractor")
        while True:
            item = await self.frame_queue.get()
            if item is None:
                self.frame_queue.task_done()
                break
                
            processed: ProcessedFrame = item
            if not processed.skip_heavy_processing:
                processed.clip_embedding = await asyncio.to_thread(self.extractor.extract_clip, processed.image)
            
            tracklet_records = []
            for track in processed.tracked_objects:
                reid_emb = await asyncio.to_thread(self.extractor.extract_reid, track.image_crop)
                record = {
                    "video_id": processed.video_id,
                    "timestamp": processed.timestamp_sec,
                    "frame_idx": processed.frame_idx,
                    "track_id": track.track_id,
                    "class_name": track.bbox.class_name,
                    "bbox": [track.bbox.x1, track.bbox.y1, track.bbox.x2, track.bbox.y2],
                    "reid_vector": reid_emb.tolist(),
                    "clip_vector": processed.clip_embedding.tolist() if processed.clip_embedding is not None else None
                }
                tracklet_records.append(record)
            
            if self.db_client and tracklet_records:
                await asyncio.to_thread(self.db_client.insert, tracklet_records)
            self.frame_queue.task_done()
            
        logger.info("[JIT] Consumer finished processing clip.")

    async def process_clip(self, video_path: str, video_id: str, start_sec: float, end_sec: float, progress_callback: Optional[Callable[[int], None]] = None):
        """按需立刻处理目标片段并阻塞等待完成"""
        producer_task = asyncio.create_task(self.producer_video_reader(video_path, video_id, start_sec, end_sec, progress_callback=progress_callback))
        consumer_task = asyncio.create_task(self.consumer_feature_extractor())
        await asyncio.gather(producer_task, consumer_task)
        
        # 消费者结束后强制推满至 100%
        if progress_callback:
            progress_callback(100)
