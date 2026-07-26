import logging
import asyncio
import time
import os
import json
from typing import List, Dict, Any, Optional, Callable
from .database import SpatiotemporalDB
from .agents import ReActParser, ReActTools, ReActSystemPrompt
from .pipeline import JITVideoPipeline

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class MVA2Runner:
    def __init__(self, db_client: SpatiotemporalDB = None):
        self.db = db_client or SpatiotemporalDB()
        self.pipeline = JITVideoPipeline(self.db)
        self.tools = ReActTools(self.db)
        self.max_feedback_loops = 10  # 支持最大 10 轮 ReAct 循环

    async def execute_on_demand_multi(self, video_items: List[Dict[str, Any]], user_query: str, progress_callback: Optional[Callable] = None) -> str:
        logger.info("="*60)
        logger.info(f"MVA V2 Multi-Video Agent Runner started for query: '{user_query}' with {len(video_items)} videos")
        logger.info("="*60)

        # 阶段零：即时扫描与全特征入库
        for idx, item in enumerate(video_items, 1):
            v_path = item["video_path"]
            v_id = item["video_id"]
            start_s = item.get("start_sec", 0.0)
            end_s = item.get("end_sec", item.get("duration", 0.0))
            meta = item.get("meta", {})
            sample_fps = meta.get("sample_fps", 1.0)
            resolution = meta.get("resolution", "1080P")

            has_records = any(rec['video_id'] == v_id for rec in self.db.records)
            if not has_records:
                if progress_callback:
                    progress_callback({
                        "stage": "jit_ingestion",
                        "status": "started",
                        "message": f"正在扫描视频 {idx}/{len(video_items)} ({item['remark']})..."
                    })
                await self.pipeline.process_clip(v_path, v_id, start_s, end_s, sample_fps=sample_fps, resolution=resolution)

        # 阶段一：组装全多视频元数据 Prompt
        videos_meta_text = []
        for idx, item in enumerate(video_items, 1):
            videos_meta_text.append(
                f"  - 视频 {idx} (序号: \"{idx}\", 视频名称/备注: \"{item['remark']}\", 文件名: \"{item['video_id']}\", 时长: {item['duration']:.1f}秒, 绝对路径: \"{os.path.abspath(item['video_path'])}\")"
            )
        videos_summary_str = "\n".join(videos_meta_text)

        meta_prompt = (
            f"【当前用户选择参与对比分析的视频片段列表 (共 {len(video_items)} 个)】:\n"
            f"{videos_summary_str}\n\n"
            f"【时间戳输出强制格式规范】:\n"
            f"在最终回答 final_answer 中，凡是提到某视频的具体时间节点，必须**严格使用格式化标签**：\n"
            f"`[video:\"视频序号\", time:\"MM:SS\"]`\n"
            f"示例：\n"
            f"- 视频 1 的 2 分 33 秒处 -> `[video:\"1\", time:\"02:33\"]`\n"
            f"- 视频 2 的 0 分 00 秒处 -> `[video:\"2\", time:\"00:00\"]`\n"
            f"（注意：视频序号必须是对应上面列表中的数字字符串 \"1\", \"2\"，必须包含英文方括号与双引号，前端依赖此格式生成蓝色可点击跳转播放链接！）"
        )

        messages = [
            {
                "role": "system",
                "content": ReActSystemPrompt.SYSTEM_PROMPT
            },
            {
                "role": "user",
                "content": f"{meta_prompt}\n\n"
                           f"用户提出的分析问题 (question): '{user_query}'\n\n"
                           f"请开始你的跨视频对比与推演。请一步一步思考，使用工具搜集事实线索，不要瞎猜。"
            }
        ]

        from app.mva.utils import Qwen_VL, api_config
        
        temp_files_to_clean = []
        final_answer_result = None
        for iteration in range(self.max_feedback_loops):
            loop_idx = iteration + 1
            logger.info(f"--- ReAct Iteration {loop_idx} / {self.max_feedback_loops} ---")

            if progress_callback:
                progress_callback({
                    "stage": "reasoning",
                    "status": "running",
                    "message": f"Agent 正在跨视频联想推理 (第 {loop_idx} 轮)...",
                    "data": {
                        "iteration": loop_idx,
                        "phase": "thinking"
                    }
                })

            if loop_idx == self.max_feedback_loops:
                messages.append({
                    "role": "user",
                    "content": "【重要指令】决策已达最大上限。请根据搜集到的所有客观线索，立刻总结输出 final_answer JSON，并严格遵守 [video:\"序号\", time:\"MM:SS\"] 时间戳格式。"
                })

            try:
                setattr(api_config, 'loop_idx', loop_idx)
                vlm_response = Qwen_VL(messages)
            except Exception as e:
                logger.error(f"VLM call failed: {e}")
                final_answer_result = f"多模态推理失败: {str(e)}"
                break

            thought, tool_name, tool_params, final_answer = ReActParser.parse_response(vlm_response)

            messages.append({
                "role": "assistant",
                "content": vlm_response
            })

            if final_answer:
                logger.info(f"ReAct Loop converged! Final Answer: {final_answer}")
                if progress_callback:
                    progress_callback({
                        "stage": "reasoning",
                        "status": "completed",
                        "message": f"Agent 思考终结: {thought or '锁定完整证据链'}",
                        "data": {
                            "iteration": loop_idx,
                            "phase": "completed",
                            "thought": thought or ""
                        }
                    })
                final_answer_result = final_answer
                break
                
            if tool_name:
                tool_params = tool_params or {}
                logger.info(f"Agent decided to call Tool: {tool_name} with params: {tool_params}")
                
                # 实时向前端通知 Agent 当前的思考和做出的行动
                if progress_callback:
                    progress_callback({
                        "stage": "reasoning",
                        "status": "running",
                        "message": f"🧠 思考: {thought or '正在搜寻线索'}\n🎬 行动: 调用 [{tool_name}]，参数: {json.dumps(tool_params, ensure_ascii=False)}",
                        "data": {
                            "iteration": loop_idx,
                            "phase": "action",
                            "thought": thought or "",
                            "tool_name": tool_name,
                            "tool_params": tool_params
                        }
                    })
                
                # 执行具体工具
                observation = ""
                try:
                    if tool_name == "spatiotemporal_search":
                        q_type = tool_params.get("query_type", "semantic")
                        q_text = tool_params.get("query_text", "")
                        v_id = tool_params.get("video_id") or video_items[0]["video_id"]
                        res = self.tools.spatiotemporal_search(q_type, q_text, v_id)
                        observation = f"系统观察反馈 (特征库检索结果):\n{json.dumps(res, ensure_ascii=False)}"
                        
                        # 构造纯文本观察追加给消息上下文
                        messages.append({
                            "role": "user",
                            "content": observation
                        })
                        
                    elif tool_name == "read_frame_image":
                        v_id = tool_params.get("video_id")
                        v_path = tool_params.get("video_path")
                        if not v_path:
                            for vi in video_items:
                                if v_id and (v_id == vi["video_id"] or v_id in vi["video_path"]):
                                    v_path = vi["video_path"]
                                    v_id = vi["video_id"]
                                    break
                            if not v_path:
                                v_path = video_items[0]["video_path"]
                                v_id = video_items[0]["video_id"]
                                
                        t_sec = float(tool_params.get("timestamp_sec", 0.0))
                        
                        img_path = self.tools.read_frame_image(v_path, t_sec, v_id)
                        if img_path and os.path.exists(img_path):
                            temp_files_to_clean.append(img_path)
                            # 构造图文混排观察追加给多模态大模型
                            messages.append({
                                "role": "user",
                                "content": [
                                    {"type": "image", "image": img_path},
                                    {"type": "text", "text": f"系统观察反馈: 已成功截取到视频在 {t_sec}s 的监控帧图像如上。请结合画面细节继续推演决策。"}
                                ]
                            })
                            observation = f"已成功提取并看到了 {t_sec}s 的监控画面。"
                        else:
                            observation = f"错误: 无法截取视频在 {t_sec}s 的监控帧图像。"
                            messages.append({
                                "role": "user",
                                "content": observation
                            })
                            
                    elif tool_name == "get_video_metadata":
                        v_p = tool_params.get("video_path") or video_items[0]["video_path"]
                        res = self.tools.get_video_metadata(v_p)
                        observation = f"系统观察反馈 (视频元数据):\n{json.dumps(res, ensure_ascii=False)}"
                        messages.append({
                            "role": "user",
                            "content": observation
                        })
                    else:
                        observation = f"错误: 未知的工具名称 '{tool_name}'。"
                        messages.append({
                            "role": "user",
                            "content": observation
                        })
                except Exception as tool_err:
                    logger.error(f"Failed to execute tool {tool_name}: {tool_err}")
                    observation = f"错误: 工具执行发生异常: {str(tool_err)}"
                    messages.append({
                        "role": "user",
                        "content": observation
                    })
                
                logger.info(f"Tool Observation: {observation}")
            else:
                # 容错：如果大模型没有输出任何合法的 JSON，返回提示让它纠正格式
                logger.warning("Agent response was not in a valid JSON format. Prompting format correction...")
                messages.append({
                    "role": "user",
                    "content": "你的回复不符合预定的 JSON 规范，或者缺失了 thought、tool_name 等必需的 JSON 键值。请重新按照格式输出纯 JSON 对象，且不要包裹在任何 ``` 代码块中。"
                })
                
        # ==========================================
        # 资源清理阶段
        # ==========================================
        for temp_img in temp_files_to_clean:
            try:
                if os.path.exists(temp_img):
                    os.remove(temp_img)
            except Exception as clean_err:
                logger.warning(f"Failed to remove temp image {temp_img}: {clean_err}")
        
        if not final_answer_result:
            try:
                for msg in reversed(messages):
                    if msg.get("role") == "assistant":
                        c = msg.get("content", "")
                        _, _, _, fa = ReActParser.parse_response(c)
                        if fa:
                            final_answer_result = fa
                            break
                        if c:
                            final_answer_result = c
                            break
            except Exception as fallback_err:
                final_answer_result = f"分析步骤已达最大限制，提取回答时出错: {str(fallback_err)}"

        return final_answer_result

    async def execute_on_demand(self, video_path: str, video_id: str, start_sec: float, end_sec: float, user_query: str, progress_callback: Optional[Callable] = None, segment_meta: Optional[Dict[str, Any]] = None) -> str:
        """
        向后兼容旧版单视频调用接口，自动包装并转发给多视频 Agent。
        """
        meta = segment_meta or {}
        duration = max(0.1, end_sec - start_sec)
        remark = meta.get("remark") or meta.get("video_name") or video_id
        
        video_item = {
            "video_path": video_path,
            "video_id": video_id,
            "remark": remark,
            "duration": duration,
            "start_sec": start_sec,
            "end_sec": end_sec,
            "meta": meta
        }
        return await self.execute_on_demand_multi([video_item], user_query, progress_callback)

    def run_on_sample(self, sample: Dict[str, Any], video_base_dir: str, progress_callback: Optional[Callable] = None) -> Dict[str, Any]:
        import os, cv2
        question = sample.get("question", "")
        video_filenames = sample.get("video_paths", sample.get("videos", []))
        segment_metas = sample.get("segment_metas", [])

        if not video_filenames:
            return {"error": "No video paths provided", "success": False}

        full_video_paths = [os.path.join(video_base_dir, v) for v in video_filenames]

        if progress_callback:
            progress_callback({
                "stage": "model_initialization",
                "status": "completed",
                "message": "MVA V2 按需分析引擎（多视频跨时空 Agent）已就绪"
            })

        video_items = []
        for idx, video_path in enumerate(full_video_paths):
            video_id = os.path.basename(video_path)
            meta = segment_metas[idx] if idx < len(segment_metas) else {}
            remark = meta.get("remark") or meta.get("video_name") or f"视频片段 {idx + 1}"

            cap = cv2.VideoCapture(video_path)
            fps = cap.get(cv2.CAP_PROP_FPS)
            frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            duration = frame_count / fps if fps > 0 else 0
            cap.release()
            
            video_items.append({
                "video_path": video_path,
                "video_id": video_id,
                "remark": remark,
                "duration": duration,
                "start_sec": 0.0,
                "end_sec": duration,
                "meta": meta
            })

        try:
            final_answer = asyncio.run(
                self.execute_on_demand_multi(video_items, question, progress_callback)
            )
        except Exception as e:
            logger.error(f"Error processing multi-videos: {e}")
            import traceback
            traceback.print_exc()
            final_answer = f"分析多视频时发生异常: {str(e)}"
        
        return {
            "predicted_answer": final_answer,
            "success": True,
            "answer_generation": {
                "raw_output": final_answer
            }
        }
