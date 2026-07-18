import logging
from typing import List, Dict, Any
import os
import json

logger = logging.getLogger(__name__)

# 获取 backend/temp/ 目录下的持久化文件路径，使时空数据库能像 SQLite 一样跨进程/重启持久生存
BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB_FILE_PATH = os.path.join(BACKEND_DIR, "temp", "spatiotemporal_db.json")

class SpatiotemporalDB:
    """Implementation of a Local Clip-bounded Spatiotemporal Database (with JSON file persistence to align with SQLite lifecycle)"""
    _shared_records = []
    _loaded = False

    def __init__(self):
        self.records = self._shared_records
        self._load_from_disk()
        logger.info(f"Initialized Spatiotemporal Database. Total persistent records: {len(self.records)}")

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
                            logger.info(f"Loaded {len(self.records)} records from spatiotemporal DB file: {DB_FILE_PATH}")
                SpatiotemporalDB._loaded = True
            except Exception as e:
                logger.error(f"Failed to load spatiotemporal DB from disk: {e}")

    def _save_to_disk(self):
        try:
            os.makedirs(os.path.dirname(DB_FILE_PATH), exist_ok=True)
            with open(DB_FILE_PATH, "w", encoding="utf-8") as f:
                json.dump(self.records, f, ensure_ascii=False, indent=2)
            logger.debug(f"Saved {len(self.records)} records to spatiotemporal DB file.")
        except Exception as e:
            logger.error(f"Failed to save spatiotemporal DB to disk: {e}")

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

    def search_semantic(self, query_text: str, video_id: str = None, top_k: int = 5) -> List[Dict[str, Any]]:
        """基于监控大类关键词匹配的真实语义检索"""
        logger.info(f"Executing Semantic Category Keyword Search for query: '{query_text}'...")
        if not self.records:
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
        for r in self.records:
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
                        top_k: int = 5) -> List[Dict[str, Any]]:
        """片段内真实 ReID 向量余弦相似度检索"""
        logger.info("Executing Real Intra-Clip ReID Cosine Similarity Search...")
        if not self.records or not query_reid_vector:
            return []
            
        import numpy as np
        q_vec = np.array(query_reid_vector, dtype=np.float32)
        q_norm = np.linalg.norm(q_vec)
        if q_norm > 0:
            q_vec = q_vec / q_norm
            
        scored_records = []
        for rec in self.records:
            r_vec_list = rec.get("reid_vector")
            if not r_vec_list:
                continue
            r_vec = np.array(r_vec_list, dtype=np.float32)
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
        tracklet = [r for r in self.records if r['track_id'] == track_id and r['video_id'] == video_id]
        tracklet.sort(key=lambda x: x['timestamp'])
        return tracklet
