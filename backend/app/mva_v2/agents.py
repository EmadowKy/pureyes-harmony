import logging
import os
import cv2
import uuid
import json
import re
from typing import List, Dict, Any, Optional, Tuple
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

class ReActParser:
    @staticmethod
    def parse_response(text: str) -> Tuple[Optional[str], Optional[str], Optional[dict], Optional[str]]:
        """
        解析大模型的 JSON 回复。
        返回四元组: (thought, tool_name, tool_params, final_answer)
        """
        # 清洗可能存在的 Markdown 代码块包裹
        cleaned = text.strip()
        if cleaned.startswith("```json"):
            cleaned = cleaned[7:]
        elif cleaned.startswith("```"):
            cleaned = cleaned[3:]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3]
        cleaned = cleaned.strip()

        # 尝试使用正则匹配出 JSON 部分（以防大模型多输出了多余解释字符）
        try:
            match = re.search(r'\{.*\}', cleaned, re.DOTALL)
            if match:
                cleaned = match.group(0)
            
            data = json.loads(cleaned)
            thought = data.get("thought")
            tool_name = data.get("tool_name")
            tool_params = data.get("tool_params")
            final_answer = data.get("final_answer")
            return thought, tool_name, tool_params, final_answer
        except Exception as e:
            logger.warning(f"Failed to parse ReAct JSON: {e}. Raw text was: {text}")
            # 如果解析失败，尝试退化提取
            if "final_answer" in text:
                match_ans = re.search(r'"final_answer"\s*:\s*"([^"]+)"', text)
                if match_ans:
                    return "Fallback parse", None, None, match_ans.group(1)
            return None, None, None, None

class ReActTools:
    def __init__(self, db_client: Any):
        self.db = db_client

    def spatiotemporal_search(self, query_type: str, query_text: str, video_id: str) -> List[Dict[str, Any]]:
        """
        检索特征库。
        query_type: 'semantic' (场景/动作) 或 'identity' (同一个人)
        """
        logger.info(f"[TOOL - spatiotemporal_search] Running search: type={query_type}, query={query_text} on video={video_id}")
        
        # 从数据库特征池中，筛选过滤出当前片段的特征
        clip_records = [r for r in self.db.records if r['video_id'] == video_id]
        if not clip_records:
            return []

        if query_type == "identity":
            # 身份比对 (mock ReID 特征匹配)
            mock_reid_vector = [0.2] * 512
            retrieved = self.db.search_identity(query_reid_vector=mock_reid_vector)
            retrieved = [r for r in retrieved if r['video_id'] == video_id]
        else:
            # 语义匹配 (mock CLIP 动作匹配)
            import random
            retrieved = random.sample(clip_records, min(5, len(clip_records)))

        # 格式化精简输出，节省大模型 Token
        formatted_results = []
        for r in retrieved:
            formatted_results.append({
                "timestamp_sec": round(r["timestamp"], 2),
                "frame_idx": r["frame_idx"],
                "track_id": r["track_id"],
                "class_name": r["class_name"],
                "bbox": r["bbox"]
            })
        return formatted_results

    def read_frame_image(self, video_path: str, timestamp_sec: float, video_id: str) -> Optional[str]:
        """
        从物理视频截取某一秒的画面。
        为了大模型能看清细节，我们采用：整帧大图 + YOLO 检测目标局部裁切拼合，或直接保存为 JPEG 并返回物理路径
        """
        logger.info(f"[TOOL - read_frame_image] Extracting frame at {timestamp_sec}s from {video_path}")
        try:
            cap = cv2.VideoCapture(video_path)
            fps = cap.get(cv2.CAP_PROP_FPS)
            frame_idx = int(timestamp_sec * fps) if fps > 0 else int(timestamp_sec * 30)
            
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            cap.release()
            
            if ret and frame is not None:
                backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
                temp_dir = os.path.join(backend_dir, "temp")
                os.makedirs(temp_dir, exist_ok=True)
                
                # 保存截图文件
                img_name = f"react_{video_id}_{frame_idx}_{uuid.uuid4().hex[:4]}.jpg"
                temp_img_path = os.path.join(temp_dir, img_name)
                
                # 检查数据库中当前秒数附近是否有关联的检测目标，有的话在原图上画框辅助 VLM 识别
                # 这样更精确，不易看错
                records = [r for r in self.db.records if r['video_id'] == video_id and abs(r['timestamp'] - timestamp_sec) < 1.0]
                if records:
                    # 在复制的图上绘制边界框
                    draw_frame = frame.copy()
                    for r in records:
                        bbox = r["bbox"]
                        cv2.rectangle(draw_frame, (int(bbox[0]), int(bbox[1])), (int(bbox[2]), int(bbox[3])), (0, 0, 255), 2)
                        cv2.putText(draw_frame, f"{r['class_name']} ({r['track_id']})", (int(bbox[0]), int(bbox[1]-5)), 
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 1)
                    cv2.imwrite(temp_img_path, draw_frame)
                else:
                    cv2.imwrite(temp_img_path, frame)
                    
                return temp_img_path
        except Exception as e:
            logger.error(f"Failed to read frame image: {e}")
        return None

    def get_video_metadata(self, video_path: str) -> Dict[str, Any]:
        """获取视频片段的基本持续时间、帧率和总帧数"""
        logger.info(f"[TOOL - get_video_metadata] Querying metadata for {video_path}")
        try:
            cap = cv2.VideoCapture(video_path)
            fps = cap.get(cv2.CAP_PROP_FPS)
            frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            duration = frame_count / fps if fps > 0 else 0
            cap.release()
            return {
                "duration_seconds": round(duration, 2),
                "fps": round(fps, 2),
                "frame_count": frame_count
            }
        except Exception as e:
            logger.error(f"Failed to read video metadata: {e}")
            return {"error": str(e)}

class ReActSystemPrompt:
    SYSTEM_PROMPT = """你是一个智能安防监控推演与分析专家。你正在协助用户在给定的监控切片视频中寻找答案。
你拥有如下“工具箱”来收集和验证事实。每次回答时，你必须严格思考并选择输出以下两种 JSON 格式之一。请注意：你的输出必须是符合标准的纯 JSON 字符串，不能包裹在任何 Markdown 代码块（如 ```json ）中。

### 格式 1：调用工具搜寻证据
如果你需要通过搜索数据库、获取时间、或者查看具体的监控帧画面来搜集线索，请输出：
{
  "thought": "你的详细推理逻辑。解释当前发现了什么，以及为什么需要调用这个工具。",
  "tool_name": "调用的工具名称",
  "tool_params": {
    "参数名": "参数值"
  }
}

### 格式 2：得出最终客观答案
如果你已经搜集到了足够的视觉证据，能够胸有成竹、证据闭环地回答用户问题，请输出：
{
  "thought": "总结你的思考，简述搜集到的时空证据链条。",
  "final_answer": "你的最终推演结论。要求用中文生动、客观、详细地叙述监控中发生的真实事件，并提供时间戳证据。"
}

---

### 可用的工具箱（Tools List）：

1. "spatiotemporal_search"：检索时空特征数据库（包含 YOLO 目标与多目标追踪 ID 记录）。
   参数：
   - "query_type": 字符串，'semantic'（搜索场景或特定动作行为）或 'identity'（追踪特定追踪ID的同一个人或物体）
   - "query_text": 检索文本（例如 "红衣男子" 或 "有人在跑步"）
   - "video_id": 字符串，当前视频的文件名（如 "slice_2_7918a9ee.mp4"）
   返回：匹配到的轨迹和关键帧的列表，包含时间戳、帧序号、track_id等。

2. "read_frame_image"：从视频片段的特定时间点截取图像，送入你的视觉感知中。
   参数：
   - "video_path": 字符串，视频文件的物理路径
   - "timestamp_sec": 浮点数，截图的目标时间（秒）
   - "video_id": 字符串，视频文件名
   返回：截取出的临时图像文件的绝对路径。在下一轮对话的开头，你将会直接看见这张图像。

3. "get_video_metadata"：获取视频的持续时间、帧率和帧数。
   参数：
   - "video_path": 字符串，视频物理路径
   返回：{"duration_seconds": 秒数, "fps": 帧率, "frame_count": 总帧数}
"""
