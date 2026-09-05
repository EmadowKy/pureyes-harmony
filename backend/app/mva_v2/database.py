import logging
from typing import List, Dict, Any
import os
import json
import tempfile
import threading

from filelock import FileLock

logger = logging.getLogger(__name__)

# 获取 backend/temp/ 目录下的持久化文件路径，使时空数据库能像 SQLite 一样跨进程/重启持久生存
BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB_FILE_PATH = os.path.join(BACKEND_DIR, "temp", "spatiotemporal_db.json")

class SpatiotemporalDB:
    """Implementation of a Local Clip-bounded Spatiotemporal Database (with JSON file persistence to align with SQLite lifecycle)"""
    _shared_records = []
    _loaded_path = None
    _thread_lock = threading.RLock()

    def __init__(self):
        self.records = self._shared_records
        self._load_from_disk()
        logger.info(f"Initialized Spatiotemporal Database. Total persistent records: {len(self.records)}")

    @staticmethod
    def _lock_path():
        return f"{DB_FILE_PATH}.lock"

    @staticmethod
    def _read_disk_unlocked():
        if not os.path.exists(DB_FILE_PATH):
            return []
        with open(DB_FILE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, list):
            raise ValueError("spatiotemporal database must contain a JSON list")
        return data

    @staticmethod
    def _write_disk_unlocked(records):
        db_dir = os.path.dirname(DB_FILE_PATH)
        os.makedirs(db_dir, exist_ok=True)
        temp_path = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=db_dir,
                prefix="spatiotemporal_",
                suffix=".tmp",
                delete=False,
            ) as f:
                temp_path = f.name
                json.dump(records, f, ensure_ascii=False)
                f.flush()
                os.fsync(f.fileno())
            os.replace(temp_path, DB_FILE_PATH)
        finally:
            if temp_path and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except OSError:
                    pass

    def _replace_shared_records(self, records):
        self.records.clear()
        self.records.extend(records)

    def _load_from_disk(self):
        with SpatiotemporalDB._thread_lock:
            if SpatiotemporalDB._loaded_path == DB_FILE_PATH:
                return
            try:
                os.makedirs(os.path.dirname(DB_FILE_PATH), exist_ok=True)
                with FileLock(self._lock_path(), timeout=30):
                    data = self._read_disk_unlocked()
                self._replace_shared_records(data)
                SpatiotemporalDB._loaded_path = DB_FILE_PATH
                logger.info(f"Loaded {len(self.records)} records from spatiotemporal DB file: {DB_FILE_PATH}")
            except Exception as e:
                logger.error(f"Failed to load spatiotemporal DB from disk: {e}")

    def _save_to_disk(self, force: bool = False):
        del force  # 保留旧调用签名；所有写入现在都使用原子落盘。
        with SpatiotemporalDB._thread_lock:
            try:
                with FileLock(self._lock_path(), timeout=30):
                    self._write_disk_unlocked(list(self.records))
                logger.debug(f"Saved {len(self.records)} records to spatiotemporal DB file.")
            except Exception as e:
                logger.error(f"Failed to save spatiotemporal DB to disk: {e}")
                raise

    def insert(self, records: List[Dict[str, Any]]):
        if not records:
            return
        with SpatiotemporalDB._thread_lock:
            with FileLock(self._lock_path(), timeout=30):
                latest = self._read_disk_unlocked()
                latest.extend(records)
                self._write_disk_unlocked(latest)
            self._replace_shared_records(latest)
            logger.debug(f"Inserted {len(records)} records. Total: {len(self.records)}")

    def replace_video_records(self, video_id: str, records: List[Dict[str, Any]], workspace_id=None):
        """Atomically replace one video's feature rows after successful processing."""
        with SpatiotemporalDB._thread_lock:
            with FileLock(self._lock_path(), timeout=30):
                latest = self._read_disk_unlocked()
                retained = [
                    record for record in latest
                    if not (
                        record.get("video_id") == video_id
                        and (workspace_id is None or record.get("workspace_id") in (None, workspace_id))
                    )
                ]
                retained.extend(records)
                self._write_disk_unlocked(retained)
            self._replace_shared_records(retained)
            logger.info(f"Replaced features for video {video_id}: {len(records)} records")

    def delete_video(self, video_id: str, workspace_id=None):
        """Delete one video's records without rebinding the process-wide shared list."""
        with SpatiotemporalDB._thread_lock:
            with FileLock(self._lock_path(), timeout=30):
                latest = self._read_disk_unlocked()
                retained = [
                    record for record in latest
                    if not (
                        record.get("video_id") == video_id
                        and (workspace_id is None or record.get("workspace_id") in (None, workspace_id))
                    )
                ]
                self._write_disk_unlocked(retained)
            removed = len(latest) - len(retained)
            self._replace_shared_records(retained)
            logger.info(f"Deleted {removed} features for video {video_id}")
            return removed

    def flush(self):
        """Compatibility hook; mutating APIs already persist atomically."""
        return None

    def snapshot(self):
        with SpatiotemporalDB._thread_lock:
            return list(self.records)

    def clear(self):
        """清除所有特征数据"""
        with SpatiotemporalDB._thread_lock:
            with FileLock(self._lock_path(), timeout=30):
                if os.path.exists(DB_FILE_PATH):
                    os.remove(DB_FILE_PATH)
            self.records.clear()
            logger.info("Cleared clip database.")

    def search_semantic(self, query_text: str, video_id: str = None, top_k: int = 5) -> List[Dict[str, Any]]:
        """基于监控大类关键词匹配的真实语义检索"""
        logger.info(f"Executing Semantic Category Keyword Search for query: '{query_text}'...")
        records = self.snapshot()
        if not records:
            return []
            
        # 建立中文关键字与监控常见目标类别的映射
        person_keys = ["人", "男", "女", "谁", "衣", "步", "跑", "走", "影", "涉案", "嫌疑", "嫌疑人"]
        car_keys = ["车", "轿车", "卡车", "面包车", "小车", "大车", "货车", "公路", "道路", "公交", "巴士", "自行车", "摩托", "行车", "交通"]
        
        target_class = None
        for k in person_keys:
            if k in query_text:
                target_class = "person"
                break
        if not target_class:
            for k in car_keys:
                if k in query_text:
                    target_class = "vehicle"
                    break
                    
        # 筛选符合类别的记录
        candidates = []
        for r in records:
            if video_id and r.get("video_id") != video_id:
                continue
            c_name = r.get("class_name", "")
            if target_class == "person":
                if c_name == "person":
                    candidates.append(r)
            elif target_class == "vehicle":
                if c_name in ["car", "truck", "bus", "motorcycle", "bicycle"]:
                    candidates.append(r)
            else:
                candidates.append(r)
                
        if not candidates:
            return []
            
        # 按时间戳排序后均匀采样返回，提供最广泛的时间跨度供大模型分析
        candidates.sort(key=lambda x: x["timestamp"])
        if len(candidates) <= top_k:
            return candidates
            
        step = len(candidates) / top_k
        sampled = [candidates[int(i * step)] for i in range(top_k)]
        return sampled

    def search_identity(self, 
                        query_reid_vector: list, 
                        relax_threshold: bool = False,
                        top_k: int = 5,
                        video_id: str = None) -> List[Dict[str, Any]]:
        """片段内真实 ReID 向量余弦相似度检索"""
        logger.info("Executing Real Intra-Clip ReID Cosine Similarity Search...")
        records = self.snapshot()
        if not records or not query_reid_vector:
            return []
            
        import numpy as np
        q_vec = np.array(query_reid_vector, dtype=np.float32)
        if q_vec.ndim != 1 or not np.all(np.isfinite(q_vec)):
            return []
        q_norm = np.linalg.norm(q_vec)
        if q_norm > 0:
            q_vec = q_vec / q_norm
            
        scored_records = []
        for rec in records:
            if video_id and rec.get("video_id") != video_id:
                continue
            r_vec_list = rec.get("reid_vector")
            if not r_vec_list:
                continue
            r_vec = np.array(r_vec_list, dtype=np.float32)
            if r_vec.shape != q_vec.shape or not np.all(np.isfinite(r_vec)):
                continue
            r_norm = np.linalg.norm(r_vec)
            if r_norm > 0:
                r_vec = r_vec / r_norm
                
            similarity = float(np.dot(q_vec, r_vec))
            scored_records.append((rec, similarity))
            
        # 按相似度降序排列
        scored_records.sort(key=lambda x: x[1], reverse=True)
        
        # 设定阈值过滤，如果找不到可以适当放宽
        threshold = 0.55 if not relax_threshold else 0.42
        valid_results = []
        for rec, score in scored_records:
            if score >= threshold:
                rec_copy = rec.copy()
                rec_copy["similarity_score"] = round(score, 4)
                valid_results.append(rec_copy)
            if len(valid_results) >= top_k:
                break
                
        return valid_results

    def get_tracklet(self, track_id: str, video_id: str) -> List[Dict[str, Any]]:
        logger.info(f"Recalling full tracklet for track_id: {track_id}")
        tracklet = [r for r in self.snapshot() if r['track_id'] == track_id and r['video_id'] == video_id]
        tracklet.sort(key=lambda x: x['timestamp'])
        return tracklet
