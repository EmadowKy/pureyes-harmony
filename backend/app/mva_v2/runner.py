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

    async def execute_on_demand(self, video_path: str, video_id: str, start_sec: float, end_sec: float, user_query: str, progress_callback: Optional[Callable] = None) -> str:
        logger.info("="*60)
        logger.info(f"MVA V2 (ReAct Agent) Runner started for query: '{user_query}'")
        logger.info("="*60)
        
        # ==========================================
        # 阶段零：即时提权与入库 (JIT Ingestion)
        # ==========================================
        # 检查数据库中是否已存在该视频片段的特征信息，避免重复分析
        has_records = any(rec['video_id'] == video_id for rec in self.db.records)
        
        if not has_records:
            if progress_callback:
                progress_callback({
                    "stage": "jit_ingestion",
                    "status": "started",
                    "message": "检测到未预分析视频，正在进行特征提取与目标追踪..."
                })
            
            logger.info(f"--- Phase 0: JIT Feature Extraction for {video_id} ---")
            await self.pipeline.process_clip(video_path, video_id, start_sec, end_sec)
            
            if progress_callback:
                progress_callback({
                    "stage": "jit_ingestion",
                    "status": "completed",
                    "message": f"视频片段特征提取完毕，共入库 {len([r for r in self.db.records if r['video_id'] == video_id])} 条结构化记录"
                })
        else:
            logger.info(f"--- Phase 0: Skipping JIT Ingestion, records already exist for {video_id} ---")
            if progress_callback:
                progress_callback({
                    "stage": "jit_ingestion",
                    "status": "completed",
                    "message": "检测到该视频片段已完成预处理，直接进入 RAG 工具调用阶段"
                })
        
        # ==========================================
        # ReAct (Thought-Action-Observation) 主循环
        # ==========================================
        from app.mva.utils import Qwen_VL
        
        # 初始化消息上下文，植入 ReAct 系统提示词
        messages = [
            {
                "role": "system",
                "content": ReActSystemPrompt.SYSTEM_PROMPT
            },
            {
                "role": "user",
                "content": f"目标视频文件名 (video_id): '{video_id}'\n"
                           f"视频文件的绝对路径 (video_path): '{os.path.abspath(video_path)}'\n"
                           f"用户提出的问题 (question): '{user_query}'\n\n"
                           f"请开始你的推理。请一步一步思考，使用工具链搜集客观事实，不要瞎猜。"
            }
        ]
        
        temp_files_to_clean = []
        final_answer_result = None
        
        for iteration in range(self.max_feedback_loops):
            loop_idx = iteration + 1
            logger.info(f"--- ReAct Iteration {loop_idx} / {self.max_feedback_loops} ---")
            
            if progress_callback:
                progress_callback({
                    "stage": "reasoning",
                    "status": "running",
                    "message": f"Agent 正在思考决策 (第 {loop_idx} 轮)...",
                    "data": {
                        "iteration": loop_idx,
                        "phase": "thinking"
                    }
                })
            
            # 如果是最后一轮，强制要求模型输出 final_answer 结束任务
            if loop_idx == self.max_feedback_loops:
                logger.info("Reached maximum iterations (10). Forcing final answer...")
                messages.append({
                    "role": "user",
                    "content": "【重要指令】当前问答决策已达最大限制（10轮）。请不要再调用任何工具。根据目前你搜集到的所有观察线索，请立刻给出你对用户提问的最终中文推演回答，并严格按照格式输出包含 thought 和 final_answer 的 JSON。"
                })

            # 调用云端多模态大模型
            try:
                # 这一步会根据 routes.py 注入的 LLM 密钥去调用 Qwen-VL
                from app.mva.utils import api_config
                setattr(api_config, 'loop_idx', loop_idx)
                vlm_response = Qwen_VL(messages)
            except Exception as e:
                logger.error(f"VLM call failed in ReAct loop: {e}")
                final_answer_result = f"多模态推理失败，在大模型调用过程中报错: {str(e)}"
                break
                
            # 解析大模型回复的 JSON 动作
            thought, tool_name, tool_params, final_answer = ReActParser.parse_response(vlm_response)
            
            # 把大模型的推理回复追加到上下文（保证大模型有先前的 Thought 记忆）
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
                        v_id = tool_params.get("video_id", video_id)
                        res = self.tools.spatiotemporal_search(q_type, q_text, v_id)
                        observation = f"系统观察反馈 (检索结果):\n{json.dumps(res, ensure_ascii=False)}"
                        
                        # 构造纯文本观察追加给消息上下文
                        messages.append({
                            "role": "user",
                            "content": observation
                        })
                        
                    elif tool_name == "read_frame_image":
                        v_path = tool_params.get("video_path", video_path)
                        t_sec = float(tool_params.get("timestamp_sec", 0.0))
                        v_id = tool_params.get("video_id", video_id)
                        
                        img_path = self.tools.read_frame_image(v_path, t_sec, v_id)
                        if img_path and os.path.exists(img_path):
                            temp_files_to_clean.append(img_path)
                            # 构造图文混排观察追加给多模态大模型
                            messages.append({
                                "role": "user",
                                "content": [
                                    {"type": "image", "image": img_path},
                                    {"type": "text", "text": f"系统观察反馈: 截取到视频在 {t_sec}s 的监控画面图像如上，其中红色框为本地 CV 辅助锁定的目标。请继续根据画面内容推演决策。"}
                                ]
                            })
                            observation = f"已成功提取并看到了 {t_sec}s 的画面。"
                        else:
                            observation = "错误: 无法截取该时间戳的视频帧画面。"
                            messages.append({
                                "role": "user",
                                "content": observation
                            })
                            
                    elif tool_name == "get_video_metadata":
                        v_path = tool_params.get("video_path", video_path)
                        res = self.tools.get_video_metadata(v_path)
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
                
        if final_answer_result is None:
            logger.warning("Max loops reached without final answer. Running fallback final answer extraction...")
            try:
                messages.append({
                    "role": "user",
                    "content": "当前推理已被强行终止，请不要输出任何 JSON 和工具名，直接用一句话简短总结上述推演线索给出最终的中文回答。"
                })
                # 设置 is_final_answer = True 以开启 streaming
                from app.mva.utils import api_config
                setattr(api_config, 'is_final_answer', True)
                fallback_resp = Qwen_VL(messages)
                
                # 尝试再次解析 final_answer，如果不是 JSON 格式则直接将返回文本当作答案
                _, _, _, final_answer = ReActParser.parse_response(fallback_resp)
                final_answer_result = final_answer or fallback_resp
            except Exception as fallback_err:
                final_answer_result = f"分析步骤已达最大限制，强制提取回答时出错: {str(fallback_err)}"
            
        return final_answer_result

    def run_on_sample(self, sample: Dict[str, Any], video_base_dir: str, progress_callback: Optional[Callable] = None) -> Dict[str, Any]:
        import os
        question = sample.get("question", "")
        video_filenames = sample.get("video_paths", sample.get("videos", []))
        
        if not video_filenames:
            return {"error": "No video paths provided", "success": False}
        
        full_video_paths = [os.path.join(video_base_dir, v) for v in video_filenames]
        
        if progress_callback:
            progress_callback({
                "stage": "model_initialization",
                "status": "completed",
                "message": "MVA V2 按需分析引擎（ReAct 智能代理）已就绪"
            })
        
        all_answers = []
        
        for idx, video_path in enumerate(full_video_paths):
            video_id = os.path.basename(video_path)
            
            if progress_callback:
                progress_callback({
                    "stage": "processing",
                    "status": "running",
                    "message": f"正在分析视频片段 {idx + 1}/{len(full_video_paths)}: {video_id}"
                })
            
            import cv2
            cap = cv2.VideoCapture(video_path)
            fps = cap.get(cv2.CAP_PROP_FPS)
            frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            duration = frame_count / fps if fps > 0 else 0
            cap.release()
            
            start_sec = 0.0
            end_sec = duration
            
            try:
                answer = asyncio.run(
                    self.execute_on_demand(video_path, video_id, start_sec, end_sec, question, progress_callback)
                )
                all_answers.append(answer)
            except Exception as e:
                logger.error(f"Error processing {video_path}: {e}")
                all_answers.append(f"处理视频 {video_id} 时出错: {str(e)}")
        
        if len(all_answers) == 1:
            final_answer = all_answers[0]
        else:
            final_answer = "\n\n".join([
                f"[视频片段 {i+1}] {ans}" for i, ans in enumerate(all_answers)
            ])
        
        return {
            "predicted_answer": final_answer,
            "success": True,
            "answer_generation": {
                "raw_output": final_answer
            }
        }
