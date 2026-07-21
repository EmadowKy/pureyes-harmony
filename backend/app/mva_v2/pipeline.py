import os
os.environ["OPENCV_LOG_LEVEL"] = "OFF"
import warnings
warnings.filterwarnings("ignore")

import asyncio
import cv2
import numpy as np
from typing import List, Dict, Optional, Any, Callable
from dataclasses import dataclass
import uuid
import time
import logging
from ultralytics import YOLO

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
    track_id: int = -1

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
    _shared_model = None

    def __init__(self):
        # 共享单例，避免重复装载 YOLO 模型与分配 CUDA 上下文
        if YoloDetector._shared_model is None:
            YoloDetector._shared_model = YOLO('yolov8n.pt')
        self.model = YoloDetector._shared_model
        self.target_classes = [0, 1, 2, 3, 5, 7]
        self.class_names = {
            0: "person", 
            1: "bicycle", 
            2: "car", 
            3: "motorcycle", 
            5: "bus", 
            7: "truck"
        }
        self.tracker_cfg = os.path.join(os.path.dirname(__file__), "bytetrack_fixed.yaml")

    def detect(self, image: np.ndarray) -> List[BoundingBox]:
        # 启用禁用 GMC 的 ByteTrack 跨帧跟踪引擎，消除全局光流推算杂音日志
        results = self.model.track(image, persist=True, verbose=False, tracker=self.tracker_cfg)
        bboxes = []
        if not results:
            return bboxes
            
        for r in results:
            if r.boxes is None:
                continue
            for box in r.boxes:
                cls_id = int(box.cls[0].item())
                if cls_id in self.target_classes:
                    xyxy = box.xyxy[0].tolist()
                    conf = float(box.conf[0].item())
                    # 获取 YOLO 追踪 ID
                    t_id = int(box.id[0].item()) if box.id is not None else -1
                    bboxes.append(BoundingBox(
                        x1=int(xyxy[0]),
                        y1=int(xyxy[1]),
                        x2=int(xyxy[2]),
                        y2=int(xyxy[3]),
                        confidence=conf,
                        class_id=cls_id,
                        class_name=self.class_names[cls_id],
                        track_id=t_id
                    ))
        return bboxes

class ByteTracker:
    def __init__(self):
        pass
        
    def update(self, bboxes: List[BoundingBox], image: np.ndarray) -> List[TrackedObject]:
        tracked = []
        for box in bboxes:
            # 优先映射 YOLO 原生追踪分配的 track_id
            track_id = f"track_{box.track_id}" if box.track_id != -1 else f"track_temp_{uuid.uuid4().hex[:4]}"
            try:
                crop = image[box.y1:box.y2, box.x1:box.x2]
                if crop.size == 0:
                    crop = np.zeros((64, 64, 3), dtype=np.uint8)
            except Exception:
                crop = np.zeros((64, 64, 3), dtype=np.uint8)
            tracked.append(TrackedObject(track_id, box, 0, crop))
        return tracked

class FeatureExtractor:
    _shared_session = None

    def __init__(self):
        if FeatureExtractor._shared_session is not None:
            self.session = FeatureExtractor._shared_session
            return

        # 寻找并初始化本地 OSNet ONNX 行人重识别模型
        backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        model_path = os.path.join(os.path.dirname(backend_dir), "models", "osnet_x1_0.onnx")
        
        # 寻找并注入 PyTorch 内置的 CUDA/cuDNN DLL 路径，实现 Windows 平台零配置 GPU 推理
        try:
            import torch
            torch_lib = os.path.join(os.path.dirname(torch.__file__), 'lib')
            if os.path.exists(torch_lib):
                os.environ['PATH'] = torch_lib + os.path.pathsep + os.environ['PATH']
                if hasattr(os, 'add_dll_directory'):
                    os.add_dll_directory(torch_lib)
            site_packages = os.path.dirname(os.path.dirname(torch.__file__))
            nvidia_dir = os.path.join(site_packages, 'nvidia')
            if os.path.exists(nvidia_dir):
                for sub in os.listdir(nvidia_dir):
                    bin_path = os.path.join(nvidia_dir, sub, 'bin')
                    if os.path.exists(bin_path):
                        os.environ['PATH'] = bin_path + os.path.pathsep + os.environ['PATH']
                        if hasattr(os, 'add_dll_directory'):
                            os.add_dll_directory(bin_path)
        except Exception as dll_err:
            logger.warning(f"Failed to inject PyTorch CUDA/cuDNN DLL paths: {dll_err}")

        import onnxruntime as ort
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Critical ReID model file not found at expected path: {model_path}")
            
        try:
            available_providers = ort.get_available_providers()
            self.session = None
            if 'CUDAExecutionProvider' in available_providers:
                try:
                    self.session = ort.InferenceSession(model_path, providers=['CUDAExecutionProvider'])
                    logger.info("Successfully loaded OSNet ReID ONNX model on GPU (CUDAExecutionProvider)")
                except Exception as cuda_err:
                    logger.warning(f"GPU (CUDAExecutionProvider) failed to initialize: {cuda_err}. Falling back to CPU.")
                    
            if self.session is None:
                self.session = ort.InferenceSession(model_path, providers=['CPUExecutionProvider'])
                logger.info("Successfully loaded OSNet ReID ONNX model on CPU (CPUExecutionProvider)")
                
            FeatureExtractor._shared_session = self.session
        except Exception as ort_err:
            raise RuntimeError(f"Failed to load ReID ONNX model session: {ort_err}")

    def extract_reid(self, crop: np.ndarray) -> np.ndarray:
        if crop is None or crop.size == 0:
            raise ValueError("Input image crop is empty or None")
        if self.session is None:
            raise RuntimeError("FeatureExtractor session is not initialized")
            
        # OSNet 输入规范：裁剪图 Resize 至 256x128，BGR 转 RGB，按 ImageNet 均值标准差标准化
        img = cv2.resize(crop, (128, 256))
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = img.astype(np.float32) / 255.0
        
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        img = (img - mean) / std
        
        # HWC -> CHW, 插入 Batch 维度 -> (1, 3, 256, 128)
        img = np.transpose(img, (2, 0, 1))
        img = np.expand_dims(img, axis=0)
        
        # 运行 ONNX 推理
        input_name = self.session.get_inputs()[0].name
        output_name = self.session.get_outputs()[0].name
        feat = self.session.run([output_name], {input_name: img})[0]
        
        # 归一化特征向量
        feat = feat[0]
        norm = np.linalg.norm(feat)
        if norm > 0:
            feat = feat / norm
        return feat

    def extract_clip(self, image: np.ndarray) -> np.ndarray:
        # 网络受限，返回零向量填充。高层语义过滤由 database.py 中的类别路由引擎自动承接
        return np.zeros(512, dtype=np.float32)

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
        """(已废弃，其功能并入 process_clip 串行执行)"""
        await self.process_clip(video_path, video_id, start_sec, end_sec, progress_callback)

    async def consumer_feature_extractor(self):
        """(已废弃，其功能并入 process_clip 串行执行)"""
        pass

    async def process_clip(self, video_path: str, video_id: str, start_sec: float, end_sec: float, progress_callback: Optional[Callable[[int], None]] = None, sample_fps: float = 1.0, resolution: str = "1080P"):
        """按需立刻处理目标片段并阻塞等待完成 (支持动态采样率 sample_fps 与画质清晰度 resolution)"""
        logger.info(f"[JIT] Fast-processing clip {video_id} from {start_sec}s to {end_sec}s with sample_fps={sample_fps}, resolution={resolution}...")
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps <= 0:
            fps = 30.0
        
        # 计算采样帧间隔
        frame_interval = max(1, int(fps / sample_fps))
        
        start_frame_idx = int(start_sec * fps)
        end_frame_idx = int(end_sec * fps)
        total_frames_to_process = max(1, end_frame_idx - start_frame_idx)
        
        frame_idx = 0
        prev_frame = None
        last_progress_pct = -1
        last_callback_time = 0.0

        while cap.isOpened() and frame_idx <= end_frame_idx:
            ret, frame = cap.read()
            if not ret or frame is None:
                break

            # 仅处理落在 [start_frame_idx, end_frame_idx] 区间且符合采样间隔的帧
            if frame_idx >= start_frame_idx and (frame_idx - start_frame_idx) % frame_interval == 0:
                # 按照画质分辨率设定对帧进行自适应缩放
                h, w = frame.shape[:2]
                target_h = 1080
                if resolution == "480P":
                    target_h = 480
                elif resolution == "720P":
                    target_h = 720
                elif resolution == "1080P":
                    target_h = 1080
                elif resolution == "4K":
                    target_h = 2160
                
                if h > target_h:
                    scale = target_h / float(h)
                    frame = cv2.resize(frame, (int(w * scale), target_h))

                # 运动检测与 YOLO 追踪提取
                has_motion = self._detect_motion(prev_frame, frame)
                if has_motion:
                    bboxes = self.detector.detect(frame)
                    if bboxes:
                        tracked_objs = self.tracker.update(bboxes, frame)
                        tracklet_records = []
                        for track in tracked_objs:
                            reid_emb = self.extractor.extract_reid(track.image_crop)
                            record = {
                                "video_id": video_id,
                                "timestamp": frame_idx / fps,
                                "frame_idx": frame_idx,
                                "track_id": track.track_id,
                                "class_name": track.bbox.class_name,
                                "bbox": [track.bbox.x1, track.bbox.y1, track.bbox.x2, track.bbox.y2],
                                "reid_vector": reid_emb.tolist(),
                                "clip_vector": [0.0] * 512
                            }
                            tracklet_records.append(record)
                            
                        if self.db_client and tracklet_records:
                            self.db_client.insert(tracklet_records)
                            
                prev_frame = frame.copy()
                
                # 高效汇报进度：节流更新频率，避免 SQL 事务锁开销
                if progress_callback:
                    progress_pct = min(99, int((frame_idx - start_frame_idx) / total_frames_to_process * 100))
                    now = time.time()
                    if progress_pct != last_progress_pct and (now - last_callback_time >= 0.3 or progress_pct >= 99):
                        last_progress_pct = progress_pct
                        last_callback_time = now
                        progress_callback(progress_pct)
                
            frame_idx += 1
            
        cap.release()
        if progress_callback:
            progress_callback(100)
