import logging
from typing import List, Dict, Any
import os
import json

logger = logging.getLogger(__name__)

# 获取 backend/temp/ 目录下的持久化文件路径，使 mock 数据库能像 SQLite 一样跨进程/重启持久生存
BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB_FILE_PATH = os.path.join(BACKEND_DIR, "temp", "spatiotemporal_mock_db.json")

class SpatiotemporalDB:
    """Mock implementation of a Local Clip-bounded Database (with JSON file persistence to align with SQLite lifecycle)"""
    _shared_records = []
    _loaded = False

    def __init__(self):
        self.records = self._shared_records
        self._load_from_disk()
        logger.info(f"Initialized Mock Spatiotemporal Database. Total persistent records: {len(self.records)}")

    def _load_from_disk(self):
        if not SpatiotemporalDB._loaded:
            try:
                os.makedirs(os.path.dirname(DB_FILE_PATH), exist_ok=True)
                if os.path.exists(DB_FILE_PATH):
                    with open(DB_FILE_PATH, "r", encoding="utf-8") as f:
                        data = json.load(f)
                        if isinstance(data, list):
                            self.records.clear()
                            self.records.extend(data)
                            logger.info(f"Loaded {len(self.records)} records from mock DB file: {DB_FILE_PATH}")
                SpatiotemporalDB._loaded = True
            except Exception as e:
                logger.error(f"Failed to load mock spatiotemporal DB from disk: {e}")

    def _save_to_disk(self):
        try:
            os.makedirs(os.path.dirname(DB_FILE_PATH), exist_ok=True)
            with open(DB_FILE_PATH, "w", encoding="utf-8") as f:
                json.dump(self.records, f, ensure_ascii=False, indent=2)
            logger.debug(f"Saved {len(self.records)} records to mock DB file.")
        except Exception as e:
            logger.error(f"Failed to save mock spatiotemporal DB to disk: {e}")

    def insert(self, records: List[Dict[str, Any]]):
        self.records.extend(records)
        self._save_to_disk()
        logger.debug(f"Inserted {len(records)} records. Total: {len(self.records)}")

    def clear(self):
        """清除所有特征数据"""
        self.records.clear()
        if os.path.exists(DB_FILE_PATH):
            try:
                os.remove(DB_FILE_PATH)
            except:
                pass
        logger.info("Cleared clip database.")

    def search_semantic(self, query_clip_vector: list, top_k: int = 5) -> List[Dict[str, Any]]:
        logger.info("Executing Semantic CLIP Vector Search within current clip...")
        if not self.records:
            return []
        import random
        return random.sample(self.records, min(top_k, len(self.records)))

    def search_identity(self, 
                        query_reid_vector: list, 
                        relax_threshold: bool = False,
                        top_k: int = 5) -> List[Dict[str, Any]]:
        """片段内身份检索"""
        logger.info(f"Executing Intra-Clip ReID Search. (Threshold relaxed: {relax_threshold})")
        
        valid_results = []
        for rec in self.records:
            # Mock 相似度计算
            score = 0.9 if not relax_threshold else 0.7 
            if score > 0.8 or relax_threshold:
                valid_results.append(rec)
            
            if len(valid_results) >= top_k:
                break
                
        return valid_results

    def get_tracklet(self, track_id: str, video_id: str) -> List[Dict[str, Any]]:
        logger.info(f"Recalling full tracklet for track_id: {track_id}")
        tracklet = [r for r in self.records if r['track_id'] == track_id and r['video_id'] == video_id]
        tracklet.sort(key=lambda x: x['timestamp'])
        return tracklet
