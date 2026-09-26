"""Face embeddings and frame-local assignment for workspace evidence tracks."""

import math
import os


TRACK_SIMILARITY = 0.45
GROUP_SIMILARITY = 0.50
MAX_TRACK_GAP_SECONDS = 3.5


def configured_face_backend():
    mode = os.environ.get("FACE_RECOGNITION_BACKEND", "server").strip().lower()
    if mode not in ("server", "harmony"):
        raise ValueError("FACE_RECOGNITION_BACKEND 只能设置为 server 或 harmony")
    return mode


def cosine(left, right):
    if not left or not right or len(left) != len(right):
        return -1.0
    try:
        left = [float(value) for value in left]
        right = [float(value) for value in right]
    except (TypeError, ValueError):
        return -1.0
    if not all(math.isfinite(value) for value in (*left, *right)):
        return -1.0
    numerator = sum(a * b for a, b in zip(left, right))
    left_norm = math.sqrt(sum(a ** 2 for a in left))
    right_norm = math.sqrt(sum(b ** 2 for b in right))
    return numerator / (left_norm * right_norm) if left_norm and right_norm else -1.0


def assign_frame(tracks, detections, timestamp, threshold=TRACK_SIMILARITY):
    """Match each face and each recent track at most once in the current frame."""
    candidates = []
    for track_index, track in enumerate(tracks):
        gap = timestamp - track["last_time"]
        if gap < 0 or gap > MAX_TRACK_GAP_SECONDS:
            continue
        for detection_index, detection in enumerate(detections):
            score = cosine(track["embedding"], detection["embedding"])
            if score >= threshold:
                candidates.append((score, track_index, detection_index))
    used_tracks, used_faces = set(), set()
    assignments = {}
    for _, track_index, detection_index in sorted(candidates, reverse=True):
        if track_index not in used_tracks and detection_index not in used_faces:
            assignments[detection_index] = track_index
            used_tracks.add(track_index)
            used_faces.add(detection_index)
    return assignments


class FaceEmbeddingModel:
    """OpenCV YuNet landmarks and SFace aligned embeddings; no color fallback."""

    def __init__(self):
        import cv2

        detector_path = os.environ.get("FACE_DETECTOR_MODEL_PATH", "")
        recognizer_path = os.environ.get("FACE_RECOGNIZER_MODEL_PATH", "")
        if not os.path.isfile(detector_path) or not os.path.isfile(recognizer_path):
            raise RuntimeError("人脸模型未配置：请设置 FACE_DETECTOR_MODEL_PATH 和 FACE_RECOGNIZER_MODEL_PATH")
        self.detector = cv2.FaceDetectorYN.create(detector_path, "", (320, 320), 0.7, 0.3, 500)
        self.recognizer = cv2.FaceRecognizerSF.create(recognizer_path, "")

    def detect(self, frame):
        height, width = frame.shape[:2]
        self.detector.setInputSize((width, height))
        _, faces = self.detector.detect(frame)
        if faces is None:
            return []
        results = []
        for face in faces:
            aligned = self.recognizer.alignCrop(frame, face)
            feature = self.recognizer.feature(aligned).flatten()
            embedding = feature.tolist()
            if cosine(embedding, embedding) < 0.99:
                continue
            x, y, w, h = [int(value) for value in face[:4]]
            x1, y1 = max(0, x), max(0, y)
            x2, y2 = min(width, x + w), min(height, y + h)
            if x2 <= x1 or y2 <= y1:
                continue
            results.append({"embedding": embedding, "crop_img": frame[y1:y2, x1:x2].copy(),
                            "bbox": (x1, y1, x2, y2)})
        return results


def bbox_iou(left, right):
    x1, y1 = max(left[0], right[0]), max(left[1], right[1])
    x2, y2 = min(left[2], right[2]), min(left[3], right[3])
    overlap = max(0, x2 - x1) * max(0, y2 - y1)
    left_area = (left[2] - left[0]) * (left[3] - left[1])
    right_area = (right[2] - right[0]) * (right[3] - right[1])
    return overlap / (left_area + right_area - overlap) if overlap else 0.0


def assign_frame_by_bbox(tracks, detections, timestamp):
    """Provisional spatial tracks; identity is assigned by the Harmony phone."""
    candidates = []
    for track_index, track in enumerate(tracks):
        if timestamp - track["last_time"] < 0 or timestamp - track["last_time"] > MAX_TRACK_GAP_SECONDS:
            continue
        for detection_index, detection in enumerate(detections):
            score = bbox_iou(track["bbox"], detection["bbox"])
            if score >= 0.25:
                candidates.append((score, track_index, detection_index))
    assignments, used_tracks = {}, set()
    for _, track_index, detection_index in sorted(candidates, reverse=True):
        if track_index not in used_tracks and detection_index not in assignments:
            assignments[detection_index] = track_index
            used_tracks.add(track_index)
    return assignments


class ProvisionalFaceDetector:
    """Detect crops without a server recognition model for phone-side comparison."""

    def __init__(self):
        import cv2
        detector_file = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        self.detector = cv2.CascadeClassifier(detector_file)
        if self.detector.empty():
            raise RuntimeError("OpenCV 人脸检测器不可用")

    def detect(self, frame):
        import cv2
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        height, width = frame.shape[:2]
        result = []
        for x, y, w, h in self.detector.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4,
                                                            minSize=(36, 36)):
            pad = int(max(w, h) * 0.12)
            x1, y1 = max(0, x - pad), max(0, y - pad)
            x2, y2 = min(width, x + w + pad), min(height, y + h + pad)
            result.append({"bbox": (x, y, x + w, y + h),
                           "crop_img": frame[y1:y2, x1:x2].copy()})
        return result

