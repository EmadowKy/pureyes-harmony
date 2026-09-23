"""Native function-calling loop for the video investigation agent."""

import json
import logging
import math
import os
import re
import time

from app.core.tool_security import resolve_selected_video
from app.mva.utils import Qwen_VL, api_config

logger = logging.getLogger(__name__)


def _tool(name, description, properties, required):
    return {"type": "function", "function": {"name": name, "description": description,
            "parameters": {"type": "object", "properties": properties,
                           "required": required, "additionalProperties": False}}}


VIDEO = {"type": "string", "description": "已选视频的文件名，必须来自用户消息中的列表"}
QUERY = {"type": "string", "description": "检索词"}
TIME = {"type": "number", "description": "视频内时间，单位秒"}
FRAME = {"type": "object", "properties": {"video_id": VIDEO, "timestamp_sec": TIME},
         "required": ["video_id", "timestamp_sec"], "additionalProperties": False}

TOOLS = [
    _tool("search_objects", "查询完整视频的目标与轨迹索引；覆盖性问题应先用此工具", {"query_text": QUERY, "video_id": VIDEO}, ["query_text", "video_id"]),
    _tool("search_visual_semantics", "CLIP 画面语义候选检索，结论须看原帧", {"query_text": QUERY, "video_id": VIDEO}, ["query_text", "video_id"]),
    _tool("search_visual_semantics_batch", "一次检索同一视频的多个画面语义条件，减少模型往返；最多四项", {"queries": {"type": "array", "items": QUERY, "minItems": 1, "maxItems": 4}, "video_id": VIDEO}, ["queries", "video_id"]),
    _tool("search_video_text", "OCR 文字索引检索", {"query_text": QUERY, "video_id": VIDEO}, ["query_text", "video_id"]),
    _tool("track_target", "用 track_id 追踪并在已选视频中寻找跨镜 ReID 候选", {"track_id": {"type": "string"}, "video_id": VIDEO}, ["track_id", "video_id"]),
    _tool("search_face_tracks", "查询人脸轨迹候选，不等于身份确认", {"query_text": QUERY}, ["query_text"]),
    _tool("read_frame_image", "读取一张原始视频帧以核验候选", {"video_id": VIDEO, "timestamp_sec": TIME}, ["video_id", "timestamp_sec"]),
    _tool("read_frames", "一次读取多个原始视频帧；优先选择不同时间段的代表帧，最多四张", {"frames": {"type": "array", "items": FRAME, "minItems": 1, "maxItems": 4}}, ["frames"]),
]

SYSTEM_PROMPT = """你是安防视频调查 Agent。视频的时长、帧率、总帧数已在用户消息给出，不要再查询。
使用原生工具调用，不要输出 JSON 工具指令。目标索引已随问题附上；先利用它规划全片，再根据候选查看原帧。独立条件优先用批量检索，多个时间点优先用 read_frames。单视频最多读取四张原帧，多视频最多八张；多条件题须给每个条件至少留一张。挑选分散且最有判别力的时间点，不要逐秒穷举或重复读取相近画面。判断打斗、倒地、跑动等短时动作时，优先查看人物交互或状态变化的局部时段，并用相邻画面核实动作过程。工具阶段结束后及时作答。
CLIP、OCR、ReID 和人脸搜索只提供候选，关键结论需原帧核验。跨视频同一目标须先获取 track_id，再调用 track_target，并读取两边原帧；无法确认时说明不确定。
回答用户的选项题时，第一行只写选项字母。所有具体时间必须写成 [video:"1", time:"MM:SS"] 形式，序号对应用户提供的视频列表。证据不足时如实说明。避免冗长的过程叙述。"""


def _frame(runner, video_items, args, temp_files):
    selected = resolve_selected_video(video_items, args)
    if not selected:
        return {"error": "video_id 不属于本次已选视频"}, None
    try:
        timestamp = float(args.get("timestamp_sec"))
    except (TypeError, ValueError):
        return {"error": "timestamp_sec 无效"}, None
    if not math.isfinite(timestamp) or timestamp < 0 or timestamp > float(selected.get("duration") or 0):
        return {"error": "时间超出视频范围"}, None
    path = runner.tools.read_frame_image(selected["video_path"], timestamp, selected["video_id"])
    if not path or not os.path.exists(path):
        return {"error": "无法截取画面"}, None
    temp_files.append(path)
    return {"video_id": selected["video_id"], "timestamp_sec": timestamp, "status": "image_attached"}, {"type": "image", "image": path}


def _dispatch(runner, video_items, name, args, temp_files):
    if name == "read_frames":
        frames = args.get("frames")
        if not isinstance(frames, list) or not 1 <= len(frames) <= 4:
            return {"error": "frames 须含 1 到 4 项"}, []
        results, images = [], []
        for frame in frames:
            result, image = _frame(runner, video_items, frame if isinstance(frame, dict) else {}, temp_files)
            results.append(result)
            if image:
                images.extend([{"type": "text", "text": json.dumps(result, ensure_ascii=False)}, image])
        return {"frames": results}, images
    if name == "read_frame_image":
        result, image = _frame(runner, video_items, args, temp_files)
        return result, ([{"type": "text", "text": json.dumps(result, ensure_ascii=False)}, image] if image else [])
    if name == "search_face_tracks":
        workspace_id = video_items[0].get("meta", {}).get("workspace_id")
        if workspace_id is None:
            return {"error": "缺少工作区上下文"}, []
        segment_ids = [item.get("meta", {}).get("id") for item in video_items if item.get("meta", {}).get("id") is not None]
        return runner.tools.search_face_tracks(int(workspace_id), segment_ids, str(args.get("query_text", ""))), []
    selected = resolve_selected_video(video_items, args)
    if not selected:
        return {"error": "video_id 不属于本次已选视频"}, []
    video_id = selected["video_id"]
    query = str(args.get("query_text", ""))
    if name == "search_objects":
        return runner.tools.spatiotemporal_search("semantic", query, video_id), []
    if name == "search_visual_semantics":
        return runner.tools.search_visual_semantics(query, video_id), []
    if name == "search_visual_semantics_batch":
        queries = args.get("queries")
        if not isinstance(queries, list) or not 1 <= len(queries) <= 4 or not all(isinstance(q, str) for q in queries):
            return {"error": "queries 须含 1 到 4 个字符串"}, []
        return {"results": [{"query": q, "result": runner.tools.search_visual_semantics(q, video_id)} for q in queries]}, []
    if name == "search_video_text":
        return runner.tools.search_video_text(query, video_id), []
    if name == "track_target":
        track_id = str(args.get("track_id", ""))
        return runner.tools.spatiotemporal_search("identity", track_id, video_id,
                                                  video_ids=[item["video_id"] for item in video_items]), []
    return {"error": f"未知工具: {name}"}, []


def execute_native(runner, video_items, messages, user_query, progress_callback=None):
    messages[0]["content"] = SYSTEM_PROMPT
    temp_files, used_tools = [], []
    seen_frames = set()
    frame_budget = 4 if len(video_items) == 1 else 8
    max_rounds = min(runner.max_feedback_loops, 4 if len(video_items) == 1 else 5)
    visual_evidence_count = 0
    available_tools = []
    question_lower = user_query.casefold()
    text_question = any(term in question_lower for term in ("文字", "车牌", "招牌", "屏幕", "字幕", "ocr", "text"))
    face_question = any(term in question_lower for term in ("人脸", "面部", "face"))
    short_action_question = (
        len(video_items) == 1
        and float(video_items[0].get("duration") or 0) <= 60
        and any(term in question_lower for term in ("倒", "跌", "摔", "跑", "停", "走", "浏览", "观看", "打斗", "打架", "冲突", "搏斗", "拳打脚踢", "fight", "fall", "run", "walk", "stop"))
        and not any(term in question_lower for term in ("颜色", "衣服", "车牌", "物品", "相似", "color", "clothing"))
    )
    for tool in TOOLS:
        name = tool["function"]["name"]
        if name == "search_objects" or (name == "track_target" and len(video_items) == 1):
            continue
        if short_action_question and name in ("search_visual_semantics", "search_visual_semantics_batch"):
            continue
        if name == "search_video_text" and not text_question:
            continue
        if name == "search_face_tracks" and not face_question:
            continue
        available_tools.append(tool)
    indexes = []
    for item in video_items:
        try:
            index = runner.tools.spatiotemporal_search("semantic", user_query, item["video_id"])
            index["sampled_results"] = index.get("sampled_results", [])[:10]
            indexes.append({"video_id": item["video_id"], "index": index})
        except Exception as exc:
            logger.warning("Initial object-index lookup failed: %s", exc)
    if indexes:
        messages.append({"role": "user", "content": "【已自动检索完整视频目标索引，勿重复检索】\n" + json.dumps(indexes, ensure_ascii=False, default=str)})
    if short_action_question:
        messages.append({"role": "user", "content": "这是不超过一分钟的动作判断题。目标索引已覆盖全片；请直接选取分散且能分别验证各条件的关键原帧，不必启动耗时的 CLIP 文本模型。"})
    final_answer = ""
    identity_terms = ("同一", "是不是同", "是否为同", "同一个", "reid", "跨镜", "跨摄像头")
    requires_identity = len(video_items) > 1 and any(term in user_query.casefold() for term in identity_terms)
    try:
        for iteration in range(max_rounds):
            loop_idx = iteration + 1
            if progress_callback:
                progress_callback({"stage": "reasoning", "status": "running", "message": f"正在调查证据（第 {loop_idx} 轮）",
                                   "data": {"iteration": loop_idx, "phase": "thinking"}})
            force_answer = loop_idx == max_rounds or (loop_idx >= 2 and visual_evidence_count >= 2)
            if force_answer:
                messages.append({"role": "user", "content": "现在停止工具调查。请根据现有证据给出最终答案；不确定处直说，不要再调用工具。选项题第一行只写选项字母。"})
            setattr(api_config, "loop_idx", loop_idx)
            setattr(api_config, "force_answer", force_answer)
            model_started = time.monotonic()
            response = Qwen_VL(messages, tools=available_tools)
            model_seconds = round(time.monotonic() - model_started, 2)
            setattr(api_config, "force_answer", False)
            calls = response.get("tool_calls") or []
            content = response.get("content") or ""
            if not calls:
                messages.append({"role": "assistant", "content": content})
                if requires_identity and "track_target" not in used_tools and loop_idx < max_rounds:
                    messages.append({"role": "user", "content": "跨视频同一目标结论尚无 track_target 支撑。请先从目标索引获取 track_id，调用 track_target 并核验原帧。"})
                    continue
                if content.strip():
                    final_answer = content.strip()
                    break
                messages.append({"role": "user", "content": "请继续调用工具或给出有证据的最终答案。"})
                continue
            messages.append({"role": "assistant", "content": content or None, "tool_calls": calls})
            images = []
            for call in calls:
                name = (call.get("function") or {}).get("name", "")
                tool_started = time.monotonic()
                try:
                    args = json.loads((call.get("function") or {}).get("arguments") or "{}")
                    if not isinstance(args, dict):
                        raise ValueError("工具参数必须为对象")
                    if not name:
                        if "frames" in args:
                            name = "read_frames"
                        elif "timestamp_sec" in args:
                            name = "read_frame_image"
                        elif "queries" in args:
                            name = "search_visual_semantics_batch"
                        else:
                            raise ValueError("模型返回了缺少工具名称的调用")
                    used_tools.append(name)
                    if name in ("read_frames", "read_frame_image"):
                        requested = args.get("frames", [args]) if name == "read_frames" else [args]
                        fresh = []
                        for frame in requested:
                            if not isinstance(frame, dict):
                                continue
                            key = (frame.get("video_id"), frame.get("timestamp_sec"))
                            if key not in seen_frames and len(seen_frames) < frame_budget:
                                fresh.append(frame)
                                seen_frames.add(key)
                        if not fresh:
                            result, new_images = {"notice": "这些时间点已经看过，或已达到 8 帧预算。请根据现有画面作答。"}, []
                        else:
                            result, new_images = _dispatch(runner, video_items, "read_frames", {"frames": fresh[:4]}, temp_files)
                    else:
                        result, new_images = _dispatch(runner, video_items, name, args, temp_files)
                    images.extend(new_images)
                    visual_evidence_count += sum(1 for part in new_images if part.get("type") == "image")
                except Exception as exc:
                    logger.exception("Tool %s failed", name)
                    result = {"error": str(exc)}
                    args = {}
                if progress_callback:
                    progress_callback({"stage": "reasoning", "status": "running", "message": f"正在调用 {name}",
                                       "data": {"iteration": loop_idx, "phase": "action", "tool_name": name, "tool_params": args,
                                                "model_seconds": model_seconds, "tool_seconds": round(time.monotonic() - tool_started, 2)}})
                messages.append({"role": "tool", "tool_call_id": call.get("id"),
                                 "content": json.dumps(result, ensure_ascii=False, default=str)})
            if images:
                messages.append({"role": "user", "content": images + [{"type": "text", "text": "以上为工具返回的原始画面，请按对应时间核验。"}]})
        if progress_callback:
            progress_callback({"stage": "reasoning", "status": "completed", "message": "视频调查完成",
                               "data": {"iteration": loop_idx, "phase": "completed", "model_seconds": model_seconds}})
        if re.search(r"选项|答案第一行|只选择一个", user_query):
            choice = re.search(r"^\s*\*{0,2}([A-D])\*{0,2}\s*(?:\n|$)", final_answer)
            if choice:
                final_answer = choice.group(1) + final_answer[choice.end(1):].lstrip("* ")
                final_answer = re.sub(r"^([A-D])\n?", r"\1\n", final_answer, count=1)
        return final_answer or "证据不足，暂时无法可靠回答。"
    finally:
        setattr(api_config, "force_answer", False)
        for path in temp_files:
            try:
                os.remove(path)
            except OSError:
                logger.warning("Could not remove temporary frame: %s", path)
