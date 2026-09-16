"""Local, optional vision-model adapters used by the video investigation pipeline.

The adapters deliberately do not download anything at request time.  A missing
model produces an explicit unavailable state, while the rest of the video
pipeline can still index the modalities that are installed.
"""

from __future__ import annotations

import logging
import os
import threading
from typing import Any, Dict, List, Optional

import cv2
import numpy as np

logger = logging.getLogger(__name__)


class VisionModelUnavailable(RuntimeError):
    """Raised when an optional local vision model is not configured."""


def _normalise(vector: np.ndarray) -> np.ndarray:
    vector = np.asarray(vector, dtype=np.float32).reshape(-1)
    norm = float(np.linalg.norm(vector))
    return vector / norm if norm > 0 else vector


class ClipSemanticEmbedder:
    """Lazy local CLIP/Chinese-CLIP image and text embedding adapter.

    Set ``CLIP_MODEL_PATH`` to an already downloaded Hugging Face model folder.
    Loading is deliberately local-files-only: a user query must never trigger a
    surprise multi-hundred-megabyte download on the production server.
    """

    _lock = threading.Lock()
    _model: Any = None
    _processor: Any = None
    _loaded_path: Optional[str] = None
    _load_error: Optional[str] = None

    def __init__(self, model_path: Optional[str] = None):
        self.model_path = model_path or os.environ.get("CLIP_MODEL_PATH", "")
        self.device = os.environ.get("PUREYES_VISION_DEVICE", "cpu")

    @property
    def configured(self) -> bool:
        return bool(self.model_path and os.path.isdir(self.model_path))

    @property
    def status(self) -> Dict[str, Any]:
        return {
            "configured": self.configured,
            "loaded": ClipSemanticEmbedder._model is not None,
            "model_path": self.model_path or None,
            "error": ClipSemanticEmbedder._load_error,
        }

    def _ensure_loaded(self) -> None:
        if ClipSemanticEmbedder._model is not None:
            return
        if ClipSemanticEmbedder._load_error:
            raise VisionModelUnavailable(f"CLIP model could not be loaded: {ClipSemanticEmbedder._load_error}")
        if not self.configured:
            raise VisionModelUnavailable("CLIP model is not configured; set CLIP_MODEL_PATH to a local model directory")
        with ClipSemanticEmbedder._lock:
            if ClipSemanticEmbedder._model is not None:
                return
            try:
                import torch
                from transformers import AutoModel, AutoProcessor

                model = AutoModel.from_pretrained(self.model_path, local_files_only=True)
                processor = AutoProcessor.from_pretrained(self.model_path, local_files_only=True)
                device = self.device if self.device == "cpu" or torch.cuda.is_available() else "cpu"
                model.eval().to(device)
                ClipSemanticEmbedder._model = model
                ClipSemanticEmbedder._processor = processor
                ClipSemanticEmbedder._loaded_path = self.model_path
                ClipSemanticEmbedder._load_error = None
                self.device = device
                logger.info("Loaded local CLIP semantic model from %s on %s", self.model_path, device)
            except Exception as exc:
                ClipSemanticEmbedder._load_error = str(exc)
                raise VisionModelUnavailable(f"CLIP model could not be loaded: {exc}") from exc

    def _features(self, *, image: Optional[np.ndarray] = None, text: Optional[str] = None) -> np.ndarray:
        self._ensure_loaded()
        import torch

        if image is not None:
            if image.size == 0:
                raise ValueError("cannot embed an empty image")
            rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            inputs = ClipSemanticEmbedder._processor(images=rgb, return_tensors="pt")
            feature_method = "get_image_features"
        else:
            if not text or not text.strip():
                raise ValueError("cannot embed an empty text query")
            inputs = ClipSemanticEmbedder._processor(text=[text.strip()], padding=True, return_tensors="pt")
            feature_method = "get_text_features"
        inputs = {key: value.to(self.device) for key, value in inputs.items()}
        model = ClipSemanticEmbedder._model
        if not hasattr(model, feature_method):
            raise VisionModelUnavailable("configured model does not provide CLIP image/text feature methods")
        with torch.no_grad():
            features = getattr(model, feature_method)(**inputs)
        return _normalise(features.detach().cpu().numpy()[0])

    def embed_image(self, image: np.ndarray) -> np.ndarray:
        return self._features(image=image)

    def embed_text(self, text: str) -> np.ndarray:
        return self._features(text=text)


class OnnxTextRecognizer:
    """Lazy RapidOCR/ONNXRuntime adapter for Chinese and English frame text.

    ``OCR_MODEL_ROOT`` must contain the three PP-OCR ONNX files used below.
    The implementation deliberately uses the project's existing ONNXRuntime
    rather than PaddlePaddle, which keeps CPU-only deployments small and avoids
    an on-demand model download.
    """

    _lock = threading.Lock()
    _engine: Any = None
    _load_error: Optional[str] = None

    def __init__(self, model_root: Optional[str] = None):
        self.model_root = model_root or os.environ.get("OCR_MODEL_ROOT", "")
        self.language = os.environ.get("OCR_LANGUAGE", "ch")

    def _model_paths(self) -> Dict[str, str]:
        return {
            "det_model_path": os.path.join(self.model_root, "ch_PP-OCRv4_det_infer.onnx"),
            "rec_model_path": os.path.join(self.model_root, "ch_PP-OCRv4_rec_infer.onnx"),
            "cls_model_path": os.path.join(self.model_root, "ch_ppocr_mobile_v2.0_cls_infer.onnx"),
        }

    @property
    def status(self) -> Dict[str, Any]:
        return {
            "configured": bool(self.model_root and all(os.path.isfile(path) for path in self._model_paths().values())),
            "loaded": OnnxTextRecognizer._engine is not None,
            "model_root": self.model_root or None,
            "error": OnnxTextRecognizer._load_error,
        }

    def _ensure_loaded(self) -> None:
        if OnnxTextRecognizer._engine is not None:
            return
        if OnnxTextRecognizer._load_error:
            raise VisionModelUnavailable(f"OCR engine could not be loaded: {OnnxTextRecognizer._load_error}")
        if not self.status["configured"]:
            raise VisionModelUnavailable("OCR model is not configured; set OCR_MODEL_ROOT with local PP-OCR ONNX model files")
        with OnnxTextRecognizer._lock:
            if OnnxTextRecognizer._engine is not None:
                return
            try:
                from rapidocr_onnxruntime import RapidOCR

                OnnxTextRecognizer._engine = RapidOCR(**self._model_paths())
                OnnxTextRecognizer._load_error = None
                logger.info("Loaded RapidOCR ONNX models from %s", self.model_root)
            except Exception as exc:
                OnnxTextRecognizer._load_error = str(exc)
                raise VisionModelUnavailable(f"OCR engine could not be loaded: {exc}") from exc

    def extract(self, image: np.ndarray) -> List[Dict[str, Any]]:
        if image is None or image.size == 0:
            return []
        self._ensure_loaded()
        raw, _elapsed = OnnxTextRecognizer._engine(image)
        results: List[Dict[str, Any]] = []
        for line in raw or []:
            if not isinstance(line, (tuple, list)) or len(line) < 3:
                continue
            points, text, confidence = line[0], str(line[1]).strip(), float(line[2])
            if not text or confidence < 0.45:
                continue
            try:
                xs = [float(point[0]) for point in points]
                ys = [float(point[1]) for point in points]
                bbox = [int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys))]
            except (TypeError, ValueError, IndexError):
                continue
            results.append({"text": text, "confidence": round(confidence, 4), "bbox": bbox})
        return results


# Backwards-compatible import name for deployments that imported the early
# adapter directly. New code should use OnnxTextRecognizer.
PaddleTextRecognizer = OnnxTextRecognizer
