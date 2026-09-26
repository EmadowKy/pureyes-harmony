import uuid
import time
import re
import math
import json
from datetime import datetime, timedelta
from flask import request, Response, stream_with_context
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.db import db
from app.models.workspace import Workspace, WorkspaceVideoSegment
from app.models.group import GroupMember
from app.models.qa_record import QARecord, QAVideoSelection
from app.models.agent_conversation import AgentConversation
from app.core.response import success, fail
from app.core.media_auth import build_media_url, path_scope
from sqlalchemy.exc import IntegrityError
from . import workspaces_bp

@workspaces_bp.post("/<int:group_id>")
@jwt_required()
def create_workspace(group_id):
    emp_id = get_jwt_identity()
    member = GroupMember.query.filter_by(group_id=group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)
        
    data = request.get_json() or {}
    name = data.get("name")
    if not name:
        return fail(message="workspace name is required", code=5002, http_status=400)
        
    workspace = Workspace(group_id=group_id, name=name, creator_id=emp_id)
    db.session.add(workspace)
    db.session.commit()
    
    return success(message="workspace created", data=workspace.to_dict(), http_status=201)

@workspaces_bp.get("/<int:group_id>")
@jwt_required()
def get_workspaces(group_id):
    emp_id = get_jwt_identity()
    member = GroupMember.query.filter_by(group_id=group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)
        
    workspaces = Workspace.query.filter_by(group_id=group_id).all()
    # attach counts
    results = []
    for w in workspaces:
        d = w.to_dict()
        d["qa_count"] = QARecord.query.filter_by(workspace_id=w.id).count()
        results.append(d)
        
    return success(data=results)

import os
import threading
from flask import current_app

# Global in-memory running tasks registry
running_tasks = {}
TASK_MEMORY_RETENTION_SECONDS = 3600
TASK_STALE_AFTER = timedelta(minutes=3)
AGENT_TASK_TIMEOUT_SECONDS = max(60, int(os.environ.get("AGENT_TASK_TIMEOUT_SECONDS", "1200")))
MAX_AGENT_RECENT_TURNS = 4
MAX_AGENT_RELEVANT_TURNS = 3
MAX_AGENT_HISTORY_CHARS = 16000


def _prune_running_tasks():
    cutoff = time.time() - TASK_MEMORY_RETENTION_SECONDS
    for task_id, task in list(running_tasks.items()):
        finished_at = task.get("finished_at")
        if finished_at and finished_at < cutoff:
            running_tasks.pop(task_id, None)

ALLOWED_VIDEO_EXTENSIONS = ('.mp4', '.avi', '.mov', '.mkv', '.webm')
ALLOWED_PREPROCESS_RESOLUTIONS = {"480P", "720P", "1080P", "4K"}


def _require_workspace_member(workspace_id, emp_id=None):
    workspace = db.session.get(Workspace, workspace_id)
    if not workspace:
        return None, fail(message="workspace not found", code=5003, http_status=404)
    member = GroupMember.query.filter_by(
        group_id=workspace.group_id,
        emp_id=emp_id or get_jwt_identity(),
        status="accepted",
    ).first()
    if not member:
        return None, fail(message="not a group member", code=5001, http_status=403)
    return workspace, None


def _segment_has_active_qa(segment_id):
    """The database, rather than this worker's task cache, owns QA state."""
    active_records = (QARecord.query.join(QAVideoSelection, QAVideoSelection.record_id == QARecord.id)
                      .filter(QAVideoSelection.segment_id == segment_id,
                              QARecord.status == "processing").all())
    for record in active_records:
        _recover_stalled_record(record)
        if record.status == "processing":
            return True
    return False


def _context_keywords(value):
    """Small local relevance signal; no extra model request before a turn starts."""
    normalized = re.sub(r"[^\w\u4e00-\u9fff]+", "", (value or "").lower())
    return {normalized[i:i + 2] for i in range(len(normalized) - 1)}


def _context_turn(record, compact=False):
    question = (record.question or "").strip()
    answer = (record.answer or "").strip() if record.status == "completed" else ""
    calls = _tool_calls_from_progress(record.progress_json)
    observations = []
    for call in calls[-(2 if compact else 5):]:
        if call.get("status") not in ("completed", "success"):
            continue
        detail = "; ".join(str(item)[:100] for item in call.get("details", [])[:2])
        evidence = ", ".join(
            f"片段 {item.get('segment_id')} @ {item.get('timestamp_sec')}s"
            for item in call.get("evidence", [])[:3] if isinstance(item, dict)
        )
        observations.append(" | ".join(part for part in (
            str(call.get("name") or "工具")[:50], str(call.get("summary") or "")[:180],
            detail, evidence,
        ) if part))
    return {
        "turn_index": record.turn_index,
        "status": record.status,
        "question": question[:350 if compact else 700],
        "answer": answer[:650 if compact else 1800],
        "observations": observations,
    }


def _conversation_context(conversation_id, before_turn, question=""):
    """Rebuild shared memory from persisted turns, with a bounded recent/relevant window."""
    if not conversation_id:
        return {"summary": "", "turns": [], "omitted": 0}
    records = (QARecord.query.filter(
        QARecord.conversation_id == conversation_id,
        QARecord.turn_index < before_turn,
        QARecord.status.in_(("completed", "failed", "stopped")),
    ).order_by(QARecord.turn_index.asc()).all())
    from app.mva_v2.evidence_memory import select_memory, format_memory
    evidence_cards = []
    for record in records:
        if record.status != "completed":
            continue
        try:
            progress = json.loads(record.progress_json or "[]")
        except (ValueError, TypeError):
            continue
        if not isinstance(progress, list):
            continue
        for entry in progress:
            if not isinstance(entry, dict) or entry.get("status") != "completed":
                continue
            data = entry.get("data") or {}
            if not isinstance(data, dict):
                continue
            for card in data.get("evidence_cards") or []:
                if isinstance(card, dict):
                    evidence_cards.append({**card, "turn_index": record.turn_index,
                                           "question": record.question or ""})
    evidence_memory = format_memory(select_memory(evidence_cards, question))
    history_budget = MAX_AGENT_HISTORY_CHARS - len(evidence_memory)
    older, recent = records[:-MAX_AGENT_RECENT_TURNS], records[-MAX_AGENT_RECENT_TURNS:]
    query_terms = _context_keywords(question)

    def relevance(record):
        evidence = (record.question or "") + " " + (record.answer or "")[:800]
        return len(query_terms & _context_keywords(evidence))

    relevant = sorted(sorted(older, key=lambda record: (relevance(record), record.turn_index),
                             reverse=True)[:MAX_AGENT_RELEVANT_TURNS],
                      key=lambda record: record.turn_index)
    chosen = {record.id for record in relevant}
    remaining = [record for record in older if record.id not in chosen]
    # Older turns remain in the database; this short chronological index avoids
    # silently treating the latest window as the entire investigation.
    index_lines = [
        f"第 {record.turn_index} 轮（{record.status}）：{record.question[:110]}"
        + (f" → {(record.answer or '')[:160]}" if record.status == "completed" else "")
        for record in remaining
    ]
    summary = "\n".join(index_lines)
    omitted = 0
    if len(summary) > 3000:
        selected_lines = []
        used = 0
        for line in reversed(index_lines):
            if used + len(line) + 1 > 3000:
                break
            selected_lines.append(line)
            used += len(line) + 1
        omitted = len(index_lines) - len(selected_lines)
        summary = "\n".join(reversed(selected_lines))
    turns = [_context_turn(record, compact=record.id in chosen) for record in
             sorted(relevant + recent, key=lambda record: record.turn_index)]
    # Preserve recent turns first if a long answer or tool trace exceeds the budget.
    while len(json.dumps(turns, ensure_ascii=False)) + len(summary) > history_budget and relevant:
        dropped = relevant.pop(0)
        turns = [turn for turn in turns if turn["turn_index"] != dropped.turn_index]
        omitted += 1
    if len(json.dumps(turns, ensure_ascii=False)) + len(summary) > history_budget:
        available = max(0, history_budget - len(json.dumps(turns, ensure_ascii=False)))
        kept_lines = []
        used = 0
        for line in reversed(summary.splitlines()):
            if used + len(line) + 1 > available:
                break
            kept_lines.append(line)
            used += len(line) + 1
        omitted += len(summary.splitlines()) - len(kept_lines)
        summary = "\n".join(reversed(kept_lines))
    while len(json.dumps(turns, ensure_ascii=False)) + len(summary) > history_budget:
        reduced = False
        for turn in turns:
            if turn["observations"]:
                turn["observations"].pop(0)
                reduced = True
                break
            if len(turn["answer"]) > 800:
                turn["answer"] = turn["answer"][:800]
                reduced = True
                break
        if not reduced:
            break
    return {"summary": summary, "turns": turns, "omitted": omitted,
            "evidence_memory": evidence_memory}


def _conversation_segments(conversation):
    segment_ids = conversation.segment_ids()
    if not segment_ids:
        return []
    return WorkspaceVideoSegment.query.filter(
        WorkspaceVideoSegment.workspace_id == conversation.workspace_id,
        WorkspaceVideoSegment.id.in_(segment_ids),
    ).all()


def _serialize_conversation(conversation):
    data = conversation.to_dict()
    data["turn_count"] = QARecord.query.filter_by(conversation_id=conversation.id).count()
    latest = (QARecord.query.filter_by(conversation_id=conversation.id)
              .order_by(QARecord.turn_index.desc()).first())
    _recover_stalled_record(latest)
    data["latest_status"] = latest.status if latest else "idle"
    data["latest_question"] = latest.question if latest else ""
    return data


def _recover_stalled_record(record):
    """Release a lost worker or a task that exceeded its total runtime."""
    if not record or record.status != "processing":
        return
    elapsed = datetime.utcnow() - record.created_at
    timed_out = elapsed.total_seconds() >= AGENT_TASK_TIMEOUT_SECONDS
    if not timed_out and datetime.utcnow() - (record.heartbeat_at or record.created_at) < TASK_STALE_AFTER:
        return
    reason = (f"本轮运行超过 {AGENT_TASK_TIMEOUT_SECONDS // 60} 分钟，已自动停止。"
              if timed_out else "调查任务已中断，请重新追问。")
    try:
        progress = json.loads(record.progress_json or "[]")
    except (TypeError, ValueError):
        progress = []
    if not isinstance(progress, list):
        progress = []
    progress.append({"stage": "system", "status": "failed", "message": reason,
                     "at": datetime.utcnow().isoformat() + "Z", "data": {}})
    changed = QARecord.query.filter_by(id=record.id, status="processing").update({
        "status": "failed", "answer": reason,
        "progress_json": json.dumps(progress, ensure_ascii=False),
    }, synchronize_session=False)
    if changed:
        db.session.commit()
    else:
        db.session.rollback()
    db.session.refresh(record)


def _safe_tool_params(params):
    if not isinstance(params, dict):
        return {}
    safe = {key: params[key] for key in ("video_id", "video_path", "query_text", "track_id",
                                        "query_type", "timestamp_sec") if key in params}
    if isinstance(params.get("frames"), list):
        safe["frames"] = [
            {key: frame[key] for key in ("video_id", "timestamp_sec") if key in frame}
            for frame in params["frames"][:4] if isinstance(frame, dict)
        ]
    if isinstance(params.get("queries"), list):
        safe["queries"] = [query[:120] for query in params["queries"][:4]
                           if isinstance(query, str)]
    return safe


def _public_progress(progress):
    """Never expose model thought or unbounded tool output to the client."""
    public = []
    if not isinstance(progress, list):
        return public
    for entry in progress:
        if not isinstance(entry, dict):
            continue
        data = entry.get("data") or {}
        if not isinstance(data, dict):
            data = {}
        phase = data.get("phase")
        if entry.get("stage") == "reasoning":
            clean = {"iteration": data.get("iteration"), "phase": phase}
            if phase == "action":
                clean.update(tool_name=data.get("tool_name"),
                             tool_params=_safe_tool_params(data.get("tool_params")))
                message = f"正在调用 {data.get('tool_name') or '工具'} 核验线索"
            elif phase == "observation":
                clean.update(tool_name=data.get("tool_name"), summary=data.get("summary") or "",
                             times=data.get("times") or [], evidence=data.get("evidence") or [],
                             details=data.get("details") or [], result_status=data.get("result_status") or entry.get("status"))
                message = clean["summary"]
            else:
                message = "正在整理证据链" if phase == "completed" else "正在分析视频线索"
        else:
            clean = {}
            message = str(entry.get("message") or "")[:180]
        public.append({"stage": entry.get("stage"), "status": entry.get("status"),
                       "message": message, "at": entry.get("at"), "data": clean})
    return public


def _tool_calls_from_progress(progress_json):
    """Expose a compact, user-safe tool timeline without returning model reasoning."""
    if not progress_json:
        return []
    try:
        progress = _public_progress(json.loads(progress_json))
    except (TypeError, ValueError, json.JSONDecodeError):
        return []
    calls = []
    for entry in progress:
        data = entry.get("data") or {}
        if entry.get("stage") != "reasoning":
            continue
        if data.get("phase") == "observation":
            for call in reversed(calls):
                if call["iteration"] == data.get("iteration"):
                    call["summary"] = data.get("summary") or ""
                    call["times"] = data.get("times") or []
                    call["evidence"] = data.get("evidence") or []
                    call["details"] = data.get("details") or []
                    call["status"] = data.get("result_status") or entry.get("status")
                    break
            continue
        if data.get("phase") != "action":
            continue
        tool_name = data.get("tool_name")
        if not tool_name:
            continue
        calls.append({
            "name": tool_name,
            "params": _safe_tool_params(data.get("tool_params")),
            "iteration": data.get("iteration"),
            "summary": "",
            "times": [],
            "evidence": [],
            "details": [],
            "status": "running",
        })
    # A native model may issue several calls in one round. Keep the entire
    # persisted chain so revisiting an investigation shows its early evidence.
    return calls


def _parse_preprocess_options(data):
    try:
        sample_fps = float(data.get("sample_fps", 1.0))
    except (TypeError, ValueError):
        return None, None, fail(message="sample_fps must be a number", code=5016, http_status=400)
    if not math.isfinite(sample_fps) or sample_fps <= 0 or sample_fps > 30:
        return None, None, fail(message="sample_fps must be greater than 0 and at most 30", code=5016, http_status=400)

    resolution = str(data.get("resolution", "1080P")).upper()
    if resolution not in ALLOWED_PREPROCESS_RESOLUTIONS:
        return None, None, fail(message="unsupported resolution", code=5017, http_status=400)
    return sample_fps, resolution, None


def _is_path_within(path, root):
    try:
        return os.path.commonpath([os.path.abspath(path), os.path.abspath(root)]) == os.path.abspath(root)
    except ValueError:
        return False


def _backend_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _remove_backend_file(relative_path):
    """Best-effort removal restricted to backend-owned storage."""
    if not relative_path:
        return False
    root = os.path.abspath(_backend_root())
    full_path = os.path.abspath(os.path.join(root, relative_path))
    if not _is_path_within(full_path, root) or not os.path.isfile(full_path):
        return False
    try:
        os.remove(full_path)
        return True
    except OSError as exc:
        print(f"[Storage Cleanup] Failed to remove {full_path}: {exc}")
        return False


def _clear_segment_face_records(segment_id):
    """Remove a segment's face rows and return files to delete after commit."""
    from app.models.face import WorkspaceFaceGroup, WorkspaceFaceRecord

    records = WorkspaceFaceRecord.query.filter_by(segment_id=segment_id).all()
    group_ids = {record.group_id for record in records}
    paths_to_remove = [record.crop_path for record in records if record.crop_path]
    for record in records:
        db.session.delete(record)
    db.session.flush()

    for group_id in group_ids:
        group = db.session.get(WorkspaceFaceGroup, group_id)
        if group and WorkspaceFaceRecord.query.filter_by(group_id=group_id).count() == 0:
            if group.avatar_path:
                paths_to_remove.append(group.avatar_path)
            db.session.delete(group)
    db.session.flush()

    return paths_to_remove

def extract_segment_features_bg(app, filepath, video_id, duration, sample_fps=1.0, resolution="1080P"):
    with app.app_context():
        # 获取对应的数据库记录，设置状态为 processing
        seg = WorkspaceVideoSegment.query.filter_by(filepath=filepath).first()
        if seg:
            seg.status = "processing"
            seg.progress = 0
            seg.sample_fps = sample_fps
            seg.resolution = resolution
            db.session.commit()
            
        try:
            import asyncio
            import time
            from app.mva_v2.database import SpatiotemporalDB
            from app.mva_v2.pipeline import JITVideoPipeline
            
            db_client = SpatiotemporalDB()
            
            # 定义更新数据库进度的回调函数 (增加写库节流阀)
            last_db_pct = -1
            last_db_time = 0.0
            def progress_callback(pct):
                nonlocal last_db_pct, last_db_time
                now = time.time()
                if (pct - last_db_pct >= 5 or pct >= 100) and (now - last_db_time >= 0.8 or pct >= 100):
                    last_db_pct = pct
                    last_db_time = now
                    try:
                        db.session.query(WorkspaceVideoSegment).filter_by(filepath=filepath).update({"progress": pct})
                        db.session.commit()
                    except Exception:
                        db.session.rollback()

            print(f"[BG FEATURE EXTRACTION] Starting JIT feature extraction for {video_id} (sample_fps={sample_fps}, resolution={resolution})...")
            pipeline = JITVideoPipeline(db_client)
            
            BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            abs_filepath = os.path.join(BACKEND_DIR, filepath)
            
            asyncio.run(pipeline.process_clip(
                abs_filepath,
                video_id,
                0.0,
                duration,
                progress_callback=progress_callback,
                sample_fps=sample_fps,
                resolution=resolution,
                workspace_id=seg.workspace_id if seg else None,
            ))
            
            # The segment may have been removed while a long analysis was running.
            db.session.expire_all()
            seg = WorkspaceVideoSegment.query.filter_by(filepath=filepath).first()
            if not seg:
                db_client.delete_video(video_id)
                return

            # 执行新增工序：人脸识别检测、归类与连贯时间段聚合
            if seg:
                process_segment_face_recognition(seg.workspace_id, seg.id, abs_filepath, seg.video_name or seg.filepath, sample_fps)

            # 更新状态为 completed
            db.session.query(WorkspaceVideoSegment).filter_by(filepath=filepath).update({
                "status": "completed",
                "progress": 100
            })
            db.session.commit()
            print(f"[BG FEATURE EXTRACTION] Successfully processed {video_id}.")
            
        except Exception as e:
            print(f"[BG FEATURE EXTRACTION ERROR] Failed to extract features for {video_id}: {e}")
            db.session.query(WorkspaceVideoSegment).filter_by(filepath=filepath).update({
                "status": "failed",
                "error_msg": str(e)
            })
            db.session.commit()

def process_segment_face_recognition(workspace_id, segment_id, abs_filepath, video_name, sample_fps=1.0):
    """Index aligned face embeddings, with one assignment per face/track per frame."""
    from app.models.face import WorkspaceFaceGroup, WorkspaceFaceRecord
    from .face_engine import (FaceEmbeddingModel, ProvisionalFaceDetector, GROUP_SIMILARITY,
                              assign_frame, assign_frame_by_bbox, configured_face_backend, cosine)

    if not os.path.isfile(abs_filepath):
        raise RuntimeError("人脸预处理视频不存在")
    import cv2

    mode = configured_face_backend()
    model = FaceEmbeddingModel() if mode == "server" else ProvisionalFaceDetector()
    cap = cv2.VideoCapture(abs_filepath)
    if not cap.isOpened():
        cap.release()
        raise RuntimeError("无法打开视频进行人脸预处理")

    created_paths = []
    old_paths = []
    root = _backend_root()
    face_dir = os.path.join(root, "storage", "faces")
    os.makedirs(face_dir, exist_ok=True)
    tracks = []
    try:
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        interval = max(1, round(fps / sample_fps))
        frame_index = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if frame_index % interval == 0:
                timestamp = frame_index / fps
                detections = model.detect(frame)
                assignments = (assign_frame(tracks, detections, timestamp) if mode == "server"
                               else assign_frame_by_bbox(tracks, detections, timestamp))
                for detection_index, detection in enumerate(detections):
                    if detection_index in assignments:
                        track = tracks[assignments[detection_index]]
                        track["last_time"] = timestamp
                        if mode == "server":
                            track["embedding"] = detection["embedding"]
                        else:
                            track["bbox"] = detection["bbox"]
                        if detection["crop_img"].size > track["crop_img"].size:
                            track["crop_img"] = detection["crop_img"]
                            if mode == "server":
                                track["best_embedding"] = detection["embedding"]
                    else:
                        track = {"start_time": timestamp, "last_time": timestamp,
                                 "crop_img": detection["crop_img"]}
                        if mode == "server":
                            track.update(embedding=detection["embedding"],
                                         best_embedding=detection["embedding"])
                        else:
                            track["bbox"] = detection["bbox"]
                        tracks.append(track)
            frame_index += 1
        cap.release()

        old_paths = _clear_segment_face_records(segment_id)
        gallery = {}
        for group in WorkspaceFaceGroup.query.filter_by(workspace_id=workspace_id).all() if mode == "server" else []:
            embeddings = []
            for record in group.records:
                try:
                    value = json.loads(record.embedding_json or "null")
                    if isinstance(value, list) and value:
                        embeddings.append(value)
                except (TypeError, ValueError):
                    pass
            if embeddings:
                gallery[group.id] = embeddings

        occupied = {}
        for track in sorted(tracks, key=lambda item: item["start_time"]):
            embedding = track.get("best_embedding")
            group_id, best_score = None, GROUP_SIMILARITY
            for candidate_id, vectors in gallery.items() if mode == "server" else []:
                intervals = occupied.get(candidate_id, [])
                if any(track["start_time"] <= end and track["last_time"] >= start
                       for start, end in intervals):
                    continue
                score = max(cosine(embedding, vector) for vector in vectors)
                if score >= best_score:
                    group_id, best_score = candidate_id, score
            if group_id is None:
                group = WorkspaceFaceGroup(workspace_id=workspace_id, name="待命名人脸")
                db.session.add(group)
                db.session.flush()
                group.name = f"人脸 #{group.id}"
                avatar_path = f"storage/faces/avatar_ws{workspace_id}_g{group.id}_{uuid.uuid4().hex[:6]}.jpg"
                if not cv2.imwrite(os.path.join(root, avatar_path), track["crop_img"]):
                    raise RuntimeError("无法保存人脸头像")
                created_paths.append(avatar_path)
                group.avatar_path = avatar_path
                group_id = group.id
                gallery[group_id] = []
            if mode == "server":
                gallery[group_id].append(embedding)
            occupied.setdefault(group_id, []).append((track["start_time"], track["last_time"]))

            crop_path = f"storage/faces/crop_ws{workspace_id}_seg{segment_id}_{uuid.uuid4().hex[:8]}.jpg"
            if not cv2.imwrite(os.path.join(root, crop_path), track["crop_img"]):
                raise RuntimeError("无法保存人脸抓拍")
            created_paths.append(crop_path)
            start = track["start_time"]
            end = max(track["last_time"], start + 1 / sample_fps)
            def time_label(seconds):
                minutes, secs = divmod(int(seconds), 60)
                return f"{minutes:02d}:{secs:02d}"

            db.session.add(WorkspaceFaceRecord(
                workspace_id=workspace_id, group_id=group_id, segment_id=segment_id,
                crop_path=crop_path, embedding_json=json.dumps(embedding) if embedding else None,
                classification_backend="server" if mode == "server" else "harmony_pending",
                video_name=video_name,
                start_time_offset=round(start, 2), end_time_offset=round(end, 2),
                start_time_str=time_label(start), end_time_str=time_label(end),
            ))
        db.session.commit()
        for old_path in old_paths:
            _remove_backend_file(old_path)
    except Exception:
        cap.release()
        db.session.rollback()
        for created_path in created_paths:
            _remove_backend_file(created_path)
        raise


def process_qa_thread(app, task_id, question, video_paths, segment_metas=None, conversation_context=""):
    with app.app_context():
        heartbeat_stop = threading.Event()
        task_info = running_tasks[task_id]
        cancel_event = task_info["cancel_event"]
        last_cancel_check = 0.0

        def is_cancelled():
            nonlocal last_cancel_check
            if cancel_event.is_set():
                return True
            now = time.monotonic()
            if now - last_cancel_check >= 1:
                last_cancel_check = now
                db.session.expire_all()
                active = db.session.get(QARecord, task_id)
                if not active or active.status != "processing":
                    cancel_event.set()
                    return True
            return False

        def ensure_active():
            if is_cancelled():
                raise RuntimeError("调查已停止")

        def heartbeat():
            while not heartbeat_stop.wait(20):
                with app.app_context():
                    try:
                        current = db.session.get(QARecord, task_id)
                        if not current or current.status != "processing":
                            cancel_event.set()
                            break
                        if (datetime.utcnow() - current.created_at).total_seconds() >= AGENT_TASK_TIMEOUT_SECONDS:
                            _recover_stalled_record(current)
                            cancel_event.set()
                            break
                        QARecord.query.filter_by(id=task_id, status="processing").update(
                            {"heartbeat_at": datetime.utcnow()})
                        db.session.commit()
                    except Exception:
                        db.session.rollback()

        threading.Thread(target=heartbeat, daemon=True).start()
        try:
            ensure_active()
            # Stage 1: Video Slicing
            init_msg = {
                "stage": "slicing",
                "status": "started",
                "message": "检测到预剪切视频片段，准备模型推理",
                "at": datetime.utcnow().isoformat() + "Z",
            }
            running_tasks[task_id]['progress'].append(init_msg)

            slice_completed = {
                "stage": "slicing",
                "status": "completed",
                "message": "视频时间段高精度物理裁剪完成，切片已就绪",
                "at": datetime.utcnow().isoformat() + "Z",
            }
            running_tasks[task_id]['progress'].append(slice_completed)

            # Stage 2: MVA V2 Engine Initialization
            model_init = {
                "stage": "model_initialization",
                "status": "started",
                "message": "MVA V2 按需分析引擎初始化中...",
                "at": datetime.utcnow().isoformat() + "Z",
            }
            running_tasks[task_id]['progress'].append(model_init)

            updated = QARecord.query.filter_by(id=task_id, status="processing").update({
                "progress_json": json.dumps(task_info['progress'], ensure_ascii=False),
                "heartbeat_at": datetime.utcnow(),
            }, synchronize_session=False)
            if not updated:
                db.session.rollback()
                cancel_event.set()
                return
            db.session.commit()

            record = db.session.get(QARecord, task_id)
            if not record:
                raise RuntimeError("QA 记录未找到。")

            settings = task_info["llm_settings"]

            # 配置 api_config 供后端的 Qwen_VL 调用
            import sys
            import importlib
            mva_utils = importlib.import_module("app.mva.utils")
            sys.modules['utils'] = mva_utils
            
            api_config = mva_utils.api_config
            api_config.api_key = settings["api_key"]
            api_config.base_url = settings["base_url"]
            api_config.model = settings["model"]
            api_config.task_id = task_id
            api_config.is_final_answer = True
            api_config.should_cancel = is_cancelled

            # Import MVA V2 ask_model (interface contract identical to old version)
            try:
                from app.qa.run_model import ask_model
            except Exception as import_err:
                raise RuntimeError(f"MVA V2 引擎依赖库导入失败: {str(import_err)}")

            config_path = os.path.join(app.root_path, "../configs/model.yaml")
            
            def progress_callback(item):
                ensure_active()
                msg = item
                stage = "processing"
                status = "running"
                data_val = {}
                if isinstance(item, dict):
                    msg = item.get("message") or item.get("data", {}).get("message") or str(item)
                    stage = item.get("stage", "processing")
                    status = item.get("status", "running")
                    data_val = item.get("data") or {}
                
                prog_entry = {
                    "stage": stage,
                    "status": status,
                    "message": msg,
                    "data": data_val,
                    "at": datetime.utcnow().isoformat() + "Z",
                }
                running_tasks[task_id]['progress'].append(prog_entry)
                updated = QARecord.query.filter_by(id=task_id, status="processing").update({
                    "progress_json": json.dumps(task_info['progress'], ensure_ascii=False),
                    "heartbeat_at": datetime.utcnow(),
                }, synchronize_session=False)
                if not updated:
                    db.session.rollback()
                    cancel_event.set()
                    raise RuntimeError("调查已停止")
                db.session.commit()

            # Call MVA V2 ask_model
            result = ask_model(
                question=question,
                video_paths=video_paths,
                config_path=config_path,
                progress_callback=progress_callback,
                segment_metas=segment_metas,
                conversation_context=conversation_context,
            )
            ensure_active()

            if result.get("success", True) is False:
                raise Exception(result.get("error", "多视频大模型推理失败。"))

            # Extract answer
            answer = result.get('predicted_answer') or \
                     (result.get('answer_generation') or {}).get('raw_output') or \
                     '模型未输出回答'

            complete_entry = {
                "stage": "answering",
                "status": "completed",
                "message": "生成最终回答完成",
                "data": {},
                "at": datetime.utcnow().isoformat() + "Z",
            }
            running_tasks[task_id]['progress'].append(complete_entry)

            # Save to Database
            updated = QARecord.query.filter_by(id=task_id, status="processing").update({
                "status": "completed", "answer": answer,
                "progress_json": json.dumps(task_info['progress'], ensure_ascii=False),
            }, synchronize_session=False)
            if not updated:
                db.session.rollback()
                cancel_event.set()
                return
            if record.conversation_id:
                conversation = db.session.get(AgentConversation, record.conversation_id)
                if conversation:
                    conversation.updated_at = datetime.utcnow()
            db.session.commit()

            running_tasks[task_id]['status'] = "completed"
            running_tasks[task_id]['answer'] = answer
            running_tasks[task_id]['finished_at'] = time.time()

        except Exception as e:
            db.session.rollback()
            if is_cancelled():
                task_info['status'] = "stopped"
                task_info['finished_at'] = time.time()
                return
            import traceback
            tb_str = traceback.format_exc()
            print(f"[QA THREAD ERROR] {tb_str}")

            error_entry = {
                "stage": "system",
                "status": "failed",
                "message": f"分析发生错误：{str(e)}",
                "data": {},
                "at": datetime.utcnow().isoformat() + "Z",
            }
            running_tasks[task_id]['progress'].append(error_entry)

            # Save failure to Database
            updated = QARecord.query.filter_by(id=task_id, status="processing").update({
                "status": "failed", "answer": f"分析发生错误：{str(e)}",
                "progress_json": json.dumps(task_info['progress'], ensure_ascii=False),
            }, synchronize_session=False)
            if not updated:
                db.session.rollback()
                cancel_event.set()
                return
            db.session.commit()

            running_tasks[task_id]['status'] = "failed"
            running_tasks[task_id]['error'] = str(e)
            running_tasks[task_id]['finished_at'] = time.time()
        finally:
            heartbeat_stop.set()
            task_info.pop("llm_settings", None)
            if 'api_config' in locals():
                api_config.should_cancel = None
                api_config.api_key = None


def _get_video_duration(video_path):
    from app.core.config import get_ffmpeg_path
    import subprocess
    try:
        cmd = [
            get_ffmpeg_path('ffprobe'), '-v', 'quiet', '-show_entries', 'format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1', video_path
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        d = float(res.stdout.strip())
        if d > 0:
            return round(d, 2)
    except Exception:
        pass
    try:
        import cv2
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0
        cap.release()
        if frame_count > 0 and fps > 0:
            return round(frame_count / fps, 2)
    except Exception:
        pass
    return 60.0


@workspaces_bp.get("/example-videos")
@jwt_required()
def get_example_videos():
    """
    列出与 backend 同级的 example 目录下的所有视频文件及时长。
    """
    BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    example_dir = os.path.abspath(os.path.join(BACKEND_DIR, "..", "example"))
    
    if not os.path.exists(example_dir) or not os.path.isdir(example_dir):
        return success(data=[])
        
    video_files = [f for f in os.listdir(example_dir) if f.endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm'))]
    results = []
    
    for vf in video_files:
        path = os.path.join(example_dir, vf)
        duration = _get_video_duration(path)
            
        results.append({
            "name": vf,
            "url": f"example/{vf}",
            "media_url": build_media_url(
                f"/api/video/example/{vf}",
                path_scope(f"example/{vf}"),
            ),
            "duration": duration
        })
        
    return success(data=results)


@workspaces_bp.post("/<int:workspace_id>/qa")
@jwt_required()
def submit_qa(workspace_id):
    emp_id = get_jwt_identity()
    workspace = db.session.get(Workspace, workspace_id)
    if not workspace:
        return fail(message="workspace not found", code=5003, http_status=404)
        
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)
    data = request.get_json() or {}
    question = data.get("question")
    segment_ids = data.get("segment_ids", [])
    conversation_id = data.get("conversation_id")
    config_id = data.get("model_config_id")

    if not isinstance(question, str) or not question.strip():
        return fail(message="question is required", code=5004, http_status=400)
    question = question.strip()
    if len(question) > 4000:
        return fail(message="question is too long", code=5022, http_status=400)

    conversation = None
    if conversation_id:
        if not isinstance(conversation_id, str) or len(conversation_id) > 64:
            return fail(message="invalid conversation_id", code=5025, http_status=400)
        conversation = db.session.get(AgentConversation, conversation_id)
        if not conversation or conversation.workspace_id != workspace_id:
            return fail(message="conversation not found in this workspace", code=5026, http_status=404)
        processing = QARecord.query.filter_by(conversation_id=conversation.id, status="processing").first()
        _recover_stalled_record(processing)
        if processing and processing.status == "processing":
            return fail(message="this investigation is still processing a turn", code=5028, http_status=409)
        # Every accepted workspace member may continue the shared investigation.
        # Follow-up turns always use its original evidence scope.
        segment_ids = conversation.segment_ids()

    if not isinstance(segment_ids, list) or not segment_ids:
        return fail(message="select at least one video segment", code=5004, http_status=400)
    if len(segment_ids) > 20 or any(type(segment_id) is not int for segment_id in segment_ids):
        return fail(message="segment_ids must contain at most 20 integer IDs", code=5023, http_status=400)
    segment_ids = list(dict.fromkeys(segment_ids))

    selected_segments = []
    for seg_id in segment_ids:
        segment = WorkspaceVideoSegment.query.filter_by(id=seg_id, workspace_id=workspace_id).first()
        if not segment:
            return fail(message=f"segment {seg_id} not found in this workspace", code=5011, http_status=404)
        if segment.status in ("pending", "processing"):
            return fail(message=f"segment {seg_id} preprocessing is still running", code=5021, http_status=409)
        selected_segments.append(segment)

    from app.models.llm_config import LLMConfig
    from app.model_configs.routes import available_config
    config = db.session.get(LLMConfig, config_id) if type(config_id) is int else None
    if not config or not available_config(config, emp_id, workspace.group_id):
        return fail(message="请选择当前可用的模型配置", code=6105, http_status=403)
    # Freeze credentials for this turn before another member can edit/delete the entry.
    llm_settings = {"api_key": config.api_key, "base_url": config.base_url, "model": config.model}

    if conversation is None:
        conversation = AgentConversation(
            id=uuid.uuid4().hex,
            workspace_id=workspace_id,
            creator_id=emp_id,
            title=question[:80],
            segment_ids_json=json.dumps(segment_ids, ensure_ascii=False),
        )
        db.session.add(conversation)
    else:
        conversation.updated_at = datetime.utcnow()

    last_turn = (db.session.query(db.func.max(QARecord.turn_index))
                 .filter_by(conversation_id=conversation.id).scalar() or 0)
    turn_index = int(last_turn) + 1
    task_id = uuid.uuid4().hex
    record = QARecord(
        id=task_id,
        workspace_id=workspace_id,
        creator_id=emp_id,
        question=question,
        status="processing",
        heartbeat_at=datetime.utcnow(),
        conversation_id=conversation.id,
        turn_index=turn_index,
        model_config_label=("个人 · " if config.scope == "personal" else "小组 · ") + config.name,
    )
    db.session.add(record)
    
    video_paths = []
    segment_metas = []
    from datetime import timedelta
    base_time = datetime(2026, 6, 27, 0, 0, 0)
    for segment in selected_segments:
        video_paths.append(segment.filepath)
        segment_metas.append(segment.to_dict())
        
        # Add selection row in DB
        qvs = QAVideoSelection(
            record_id=task_id,
            monitor_id=0,
            segment_id=segment.id,
            start_time=base_time + timedelta(seconds=segment.start_offset),
            end_time=base_time + timedelta(seconds=segment.end_offset)
        )
        db.session.add(qvs)

    initial_progress = [{
        "stage": "metadata", "status": "completed",
        "message": "Metadata initialization", "data": {"video_paths": video_paths},
        "at": datetime.utcnow().isoformat() + "Z",
    }]
    record.progress_json = json.dumps(initial_progress, ensure_ascii=False)
    try:
        db.session.commit()
    except IntegrityError as exc:
        db.session.rollback()
        detail = str(exc.orig)
        if ("uq_qa_active_conversation" in detail or
                "qa_records.conversation_id" in detail):
            return fail(message="this investigation is still processing a turn", code=5028, http_status=409)
        raise
    conversation_context = _conversation_context(conversation.id, turn_index, question)
    
    # Initialize in-memory task tracker
    _prune_running_tasks()
    running_tasks[task_id] = {
        "status": "processing",
        "cancel_event": threading.Event(),
        "created_at": time.time(),
        "progress": initial_progress,
        "answer": None,
        "error": None,
        "video_paths": video_paths,
        "conversation_id": conversation.id,
        "turn_index": turn_index,
        "llm_settings": llm_settings,
    }
    
    # Start thread
    app = current_app._get_current_object()
    t = threading.Thread(
        target=process_qa_thread,
        args=(app, task_id, question, video_paths, segment_metas, conversation_context),
    )
    t.daemon = True
    t.start()
    
    return success(message="agent turn submitted", data={
        "task_id": task_id,
        "conversation_id": conversation.id,
        "turn_index": turn_index,
    })


@workspaces_bp.get("/<int:workspace_id>/qa")
@jwt_required()
def list_qa_records(workspace_id):
    emp_id = get_jwt_identity()
    workspace = db.session.get(Workspace, workspace_id)
    if not workspace:
        return fail(message="workspace not found", code=5003, http_status=404)
        
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)
        
    records = QARecord.query.filter_by(workspace_id=workspace_id).order_by(QARecord.created_at.desc()).all()
    results = []
    for r in records:
        d = r.to_dict()
        sels = QAVideoSelection.query.filter_by(record_id=r.id).all()
        d["selections"] = [s.to_dict() for s in sels]
        results.append(d)
        
    return success(data=results)


@workspaces_bp.get("/<int:workspace_id>/agent/conversations")
@jwt_required()
def list_agent_conversations(workspace_id):
    """List persistent investigation threads visible in the current workspace."""
    _, error = _require_workspace_member(workspace_id)
    if error:
        return error
    conversations = (AgentConversation.query.filter_by(workspace_id=workspace_id)
                     .order_by(AgentConversation.updated_at.desc()).all())
    return success(data=[_serialize_conversation(item) for item in conversations])


@workspaces_bp.get("/<int:workspace_id>/model-configs")
@jwt_required()
def workspace_model_configs(workspace_id):
    workspace, error = _require_workspace_member(workspace_id)
    if error:
        return error
    from app.models.group import Group
    from app.models.llm_config import LLMConfig
    emp_id = get_jwt_identity()
    group = db.session.get(Group, workspace.group_id)
    personal = LLMConfig.query.filter_by(scope="personal", owner_id=emp_id).all()
    shared = LLMConfig.query.filter_by(scope="group", group_id=workspace.group_id).all()
    return success(data=[config.public(emp_id, group.creator_id if group else None)
                         for config in personal + shared])


@workspaces_bp.get("/agent/conversations/<conversation_id>/messages")
@jwt_required()
def get_agent_conversation_messages(conversation_id):
    conversation = db.session.get(AgentConversation, conversation_id)
    if not conversation:
        return fail(message="conversation not found", code=5026, http_status=404)
    _, error = _require_workspace_member(conversation.workspace_id)
    if error:
        return error
    records = (QARecord.query.filter_by(conversation_id=conversation_id)
               .order_by(QARecord.turn_index.asc()).all())
    messages = []
    for record in records:
        _recover_stalled_record(record)
        data = record.to_dict()
        data.pop("progress_json", None)
        selections = QAVideoSelection.query.filter_by(record_id=record.id).all()
        data["selections"] = [selection.to_dict() for selection in selections]
        data["tool_calls"] = _tool_calls_from_progress(record.progress_json)
        messages.append(data)
    return success(data={"conversation": _serialize_conversation(conversation), "messages": messages})


@workspaces_bp.post("/qa/<task_id>/stop")
@jwt_required()
def stop_qa(task_id):
    record = db.session.get(QARecord, task_id)
    if not record:
        return fail(message="task not found", code=5005, http_status=404)
    _, error = _require_workspace_member(record.workspace_id)
    if error:
        return error
    if not record.conversation_id:
        return fail(message="only agent investigations can be stopped here", code=5026, http_status=400)

    message = "本轮已由组员停止，可继续追问。"
    try:
        progress = json.loads(record.progress_json or "[]")
    except (TypeError, ValueError):
        progress = []
    if not isinstance(progress, list):
        progress = []
    progress.append({"stage": "system", "status": "stopped", "message": message,
                     "at": datetime.utcnow().isoformat() + "Z", "data": {}})
    updated = QARecord.query.filter_by(id=task_id, status="processing").update({
        "status": "stopped", "answer": message,
        "progress_json": json.dumps(progress, ensure_ascii=False),
    }, synchronize_session=False)
    if updated:
        conversation = db.session.get(AgentConversation, record.conversation_id)
        if conversation:
            conversation.updated_at = datetime.utcnow()
        db.session.commit()
        task_info = running_tasks.get(task_id)
        if task_info:
            task_info["cancel_event"].set()
            task_info["status"] = "stopped"
            task_info["answer"] = message
            task_info["progress"].append(progress[-1])
            task_info["finished_at"] = time.time()
        return success(data={"status": "stopped", "conversation_id": record.conversation_id})
    db.session.rollback()
    db.session.refresh(record)
    return success(data={"status": record.status, "conversation_id": record.conversation_id})


@workspaces_bp.get("/qa/<task_id>/status")
@jwt_required()
def get_qa_status(task_id):
    emp_id = get_jwt_identity()
    record = db.session.get(QARecord, task_id)
    if not record:
        return fail(message="task not found", code=5005, http_status=404)
    _, error = _require_workspace_member(record.workspace_id, emp_id)
    if error:
        return error
    db.session.refresh(record)
    _recover_stalled_record(record)
    try:
        progress_data = json.loads(record.progress_json or "[]")
    except (TypeError, ValueError):
        progress_data = []
    if not isinstance(progress_data, list):
        progress_data = []
    if not progress_data:
        progress_data = [{
            "stage": "answering", "status": record.status,
            "message": record.answer or ("已完成" if record.status == "completed" else "任务失败"),
        }]

    video_paths = []
    for entry in progress_data:
        if isinstance(entry, dict) and entry.get("stage") == "metadata":
            video_paths = (entry.get("data") or {}).get("video_paths", [])
            break
    if not video_paths:
        # Historical records did not persist the metadata entry.
        for selection in QAVideoSelection.query.filter_by(record_id=task_id).all():
            if selection.segment_id:
                segment = db.session.get(WorkspaceVideoSegment, selection.segment_id)
                if segment and segment.workspace_id == record.workspace_id:
                    video_paths.append(segment.filepath)

    return success(data={
        "status": record.status,
        "progress": _public_progress(progress_data),
        "answer": record.answer if record.status == "completed" else None,
        "error": record.answer if record.status == "failed" else None,
        "video_paths": video_paths,
        "conversation_id": record.conversation_id,
        "turn_index": record.turn_index,
    })


@workspaces_bp.get("/qa/<task_id>/stream")
@jwt_required()
def qa_stream(task_id):
    emp_id = get_jwt_identity()
    record = db.session.get(QARecord, task_id)
    if not record:
        return fail(message="task not found", code=5005, http_status=404)
    _, error = _require_workspace_member(record.workspace_id, emp_id)
    if error:
        return error

    def generate():
        yield f"data: {json.dumps({'type': 'connected', 'task_id': task_id})}\n\n"
        seen = 0
        while True:
            db.session.expire_all()
            current = db.session.get(QARecord, task_id)
            if not current:
                break
            try:
                progress = json.loads(current.progress_json or "[]")
            except (TypeError, ValueError):
                progress = []
            if not isinstance(progress, list):
                progress = []
            for entry in _public_progress(progress[seen:]):
                yield f"data: {json.dumps({'type': 'progress', 'data': entry}, ensure_ascii=False)}\n\n"
            seen = len(progress)
            _recover_stalled_record(current)
            if current.status in ("completed", "failed", "stopped"):
                yield f"data: {json.dumps({'type': 'complete', 'status': current.status, 'answer': current.answer}, ensure_ascii=False)}\n\n"
                break
            time.sleep(0.75)
    return Response(stream_with_context(generate()), mimetype="text/event-stream")


@workspaces_bp.delete("/qa/<task_id>")
@jwt_required()
def delete_qa_record(task_id):
    emp_id = get_jwt_identity()
    record = db.session.get(QARecord, task_id)
    if not record:
        return fail(message="record not found", code=5005, http_status=404)
        
    workspace = db.session.get(Workspace, record.workspace_id)
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)
    if record.status == "processing":
        return fail(message="stop the running investigation before deleting it", code=5028, http_status=409)
        
    QAVideoSelection.query.filter_by(record_id=task_id).delete()
    db.session.delete(record)
    db.session.commit()
    
    # Cleanup memory tracker
    if task_id in running_tasks:
        del running_tasks[task_id]
        
    return success(message="record deleted")


def parse_time_to_ts(time_str):
    time_str = (time_str or "").strip()
    match = re.match(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})', time_str)
    if not match:
        raise ValueError(f"时间格式无效: {time_str}，请使用 YYYY-MM-DD HH:mm:ss 格式")
    dt = datetime(
        int(match.group(1)), int(match.group(2)), int(match.group(3)),
        int(match.group(4)), int(match.group(5)), int(match.group(6))
    )
    return dt.timestamp(), dt


def slice_and_concat_monitor_stream(monitor_id, start_time_str, end_time_str, output_path):
    """
    根据起止时间戳范围查找监控录像切片，进行连续性与完整性校验。
    如果包含缺失，返回 (False, 错误提示)；若无缺失，使用 FFmpeg 进行拼接与精密截取。
    """
    BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    mon_dir = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "streams", str(monitor_id)))

    if not os.path.exists(mon_dir) or not os.path.isdir(mon_dir):
        return False, "该监控设备暂未产生任何后台录像文件", 0.0

    try:
        start_ts, start_dt = parse_time_to_ts(start_time_str)
        end_ts, end_dt = parse_time_to_ts(end_time_str)
    except ValueError as ve:
        return False, str(ve), 0.0

    if end_ts <= start_ts:
        return False, "结束时间必须大于起始时间", 0.0

    target_duration = end_ts - start_ts
    if target_duration > 7200:
        return False, "单次截取的时间跨度不能超过 2 小时", 0.0

    video_files = [f for f in os.listdir(mon_dir) if f.endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm'))]
    if not video_files:
        return False, "该监控设备目录下无录像切片文件", 0.0

    file_info_list = []
    for vf in video_files:
        path = os.path.join(mon_dir, vf)
        base = os.path.splitext(vf)[0]
        try:
            f_dt = datetime.strptime(base, "%Y%m%d_%H%M%S")
            f_start = f_dt.timestamp()
            f_dur = _get_video_duration(path)
            f_end = f_start + f_dur
            file_info_list.append({
                'file': vf,
                'path': path,
                'start_ts': f_start,
                'end_ts': f_end,
                'duration': f_dur
            })
        except Exception:
            continue

    if not file_info_list:
        return False, "未能识别出符合时间规范的监控切片", 0.0

    file_info_list.sort(key=lambda x: x['start_ts'])

    # 筛选与 [start_ts, end_ts] 相较重叠的文件
    overlapping_files = []
    for fi in file_info_list:
        if fi['end_ts'] > start_ts and fi['start_ts'] < end_ts:
            overlapping_files.append(fi)

    if not overlapping_files:
        return False, f"所选时间段（{start_time_str} ~ {end_time_str}）内监控录像存在缺失（未找到录像文件）", 0.0

    # 连续性与覆盖完整性校验
    # 1. 检查开端是否覆盖到 start_ts
    first_file = overlapping_files[0]
    if first_file['start_ts'] > start_ts + 3.0:
        return False, f"所选时间段起始部分录像存在缺失（缺失起点: {start_time_str}）", 0.0

    # 2. 检查末尾是否覆盖到 end_ts
    last_file = overlapping_files[-1]
    if last_file['end_ts'] < end_ts - 3.0:
        return False, f"所选时间段末尾部分录像存在缺失（缺失终点: {end_time_str}）", 0.0

    # 3. 检查中间相连接的缝隙 (Gaps)
    for i in range(len(overlapping_files) - 1):
        curr_f = overlapping_files[i]
        next_f = overlapping_files[i + 1]
        if next_f['start_ts'] - curr_f['end_ts'] > 3.5:
            gap_dt = datetime.fromtimestamp(curr_f['end_ts'])
            missing_gap_time = gap_dt.strftime("%Y-%m-%d %H:%M:%S")
            return False, f"所选时间段内监控录像存在中途缺失（缺失时间点约: {missing_gap_time}）", 0.0

    # 校验通过！使用 FFmpeg 进行拼接与精准裁剪
    from app.core.config import get_ffmpeg_path
    import subprocess
    ffmpeg_bin = get_ffmpeg_path("ffmpeg")

    first_offset = max(0.0, start_ts - first_file['start_ts'])

    if len(overlapping_files) == 1:
        cmd = [
            ffmpeg_bin, "-y",
            "-ss", f"{first_offset:.3f}",
            "-t", f"{target_duration:.3f}",
            "-i", first_file['path'],
            "-c:v", "libx264", "-preset", "veryfast",
            "-c:a", "aac",
            output_path
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode != 0 or not os.path.exists(output_path) or os.path.getsize(output_path) <= 1000:
            return False, f"FFmpeg 裁剪失败: {res.stderr}", 0.0
        return True, "ok", target_duration

    else:
        concat_list_path = os.path.join(os.path.dirname(output_path), f"concat_{uuid.uuid4().hex[:6]}.txt")
        try:
            with open(concat_list_path, "w", encoding="utf-8") as f:
                for fi in overlapping_files:
                    clean_p = fi['path'].replace("\\", "/")
                    f.write(f"file '{clean_p}'\n")

            cmd = [
                ffmpeg_bin, "-y",
                "-ss", f"{first_offset:.3f}",
                "-t", f"{target_duration:.3f}",
                "-f", "concat", "-safe", "0",
                "-i", concat_list_path,
                "-c:v", "libx264", "-preset", "veryfast",
                "-c:a", "aac",
                output_path
            ]
            print(f"[Monitor Stream Concat] Executing: {' '.join(cmd)}")
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            if res.returncode != 0 or not os.path.exists(output_path) or os.path.getsize(output_path) <= 1000:
                return False, f"FFmpeg 拼接切片失败: {res.stderr}", 0.0
            return True, "ok", target_duration

        finally:
            if os.path.exists(concat_list_path):
                try:
                    os.remove(concat_list_path)
                except Exception:
                    pass


@workspaces_bp.get("/<int:workspace_id>/video-sources")
@jwt_required()
def get_workspace_video_sources(workspace_id):
    """
    获取工作区可用于截取的视频源（包含同小组的监控设备、用户上传视频及示例视频）。
    按监控设备为单位展示，隐藏底层一分钟切片细节。
    """
    emp_id = get_jwt_identity()
    workspace = db.session.get(Workspace, workspace_id)
    if not workspace:
        return fail(message="workspace not found", code=5003, http_status=404)

    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)

    BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    results = []

    # 1. 查询同小组下的监控设备 (Monitors)
    from app.models.monitor import Monitor
    group_monitors = Monitor.query.filter_by(group_id=workspace.group_id).all()
    streams_base = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "streams"))

    for mon in group_monitors:
        mon_dir = os.path.join(streams_base, str(mon.id))
        earliest_time_str = None
        latest_time_str = None
        has_recs = False
        
        if os.path.exists(mon_dir) and os.path.isdir(mon_dir):
            video_files = [f for f in os.listdir(mon_dir) if f.endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm'))]
            video_files.sort(key=lambda x: x)
            if video_files:
                has_recs = True
                try:
                    f_first = video_files[0].replace(".mp4", "").replace(".avi", "").replace(".mov", "")
                    dt_first = datetime.strptime(f_first, "%Y%m%d_%H%M%S")
                    earliest_time_str = dt_first.strftime("%Y-%m-%d %H:%M:%S")
                except Exception:
                    earliest_time_str = video_files[0]
                    
                try:
                    f_last = video_files[-1].replace(".mp4", "").replace(".avi", "").replace(".mov", "")
                    dt_last = datetime.strptime(f_last, "%Y%m%d_%H%M%S")
                    latest_time_str = dt_last.strftime("%Y-%m-%d %H:%M:%S")
                except Exception:
                    latest_time_str = video_files[-1]

        results.append({
            "id": f"monitor_{mon.id}",
            "name": f"监控:{mon.name}",
            "source_type": "monitor",
            "monitor_id": mon.id,
            "monitor_name": mon.name,
            "has_recordings": has_recs,
            "earliest_time": earliest_time_str or "无录像记录",
            "latest_time": latest_time_str or "无录像记录"
        })

    # 2. 查询用户上传的视频 (Uploaded Videos)
    upload_dir = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "uploads", str(workspace_id)))
    if os.path.exists(upload_dir) and os.path.isdir(upload_dir):
        uploaded_files = [f for f in os.listdir(upload_dir) if f.endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm'))]
        uploaded_files.sort(key=lambda x: os.path.getmtime(os.path.join(upload_dir, x)), reverse=True)
        for uf in uploaded_files[:30]:
            uf_path = os.path.join(upload_dir, uf)
            duration = _get_video_duration(uf_path)
            results.append({
                "id": f"upload_{uf}",
                "name": f"已上传:{uf}",
                "raw_filename": uf,
                "filepath": f"storage/uploads/{workspace_id}/{uf}",
                "url": f"storage/uploads/{workspace_id}/{uf}",
                "media_url": build_media_url(
                    f"/api/video/storage/uploads/{workspace_id}/{uf}",
                    path_scope(f"storage/uploads/{workspace_id}/{uf}"),
                ),
                "duration": duration,
                "source_type": "upload",
                "monitor_id": None,
                "monitor_name": ""
            })

    # 3. 示例视频备用 (Example Videos)
    example_dir = os.path.abspath(os.path.join(BACKEND_DIR, "..", "example"))
    if os.path.exists(example_dir) and os.path.isdir(example_dir):
        ex_files = [f for f in os.listdir(example_dir) if f.endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm'))]
        for ef in ex_files:
            ef_path = os.path.join(example_dir, ef)
            duration = _get_video_duration(ef_path)
            results.append({
                "id": f"example_{ef}",
                "name": f"示例:{ef}",
                "raw_filename": ef,
                "filepath": f"../example/{ef}",
                "url": f"example/{ef}",
                "media_url": build_media_url(
                    f"/api/video/example/{ef}",
                    path_scope(f"example/{ef}"),
                ),
                "duration": duration,
                "source_type": "example",
                "monitor_id": None,
                "monitor_name": ""
            })

    return success(data=results)


@workspaces_bp.post("/<int:workspace_id>/upload-video")
@jwt_required()
def upload_workspace_video(workspace_id):
    """
    直接上传本地视频到工作区存储库。
    """
    emp_id = get_jwt_identity()
    workspace = db.session.get(Workspace, workspace_id)
    if not workspace:
        return fail(message="workspace not found", code=5003, http_status=404)

    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)

    if 'file' not in request.files:
        return fail(message="no file provided", code=5010, http_status=400)

    file = request.files['file']
    if not file or file.filename == '':
        return fail(message="empty file", code=5011, http_status=400)

    allowed_exts = ('.mp4', '.avi', '.mov', '.mkv', '.webm')
    if not file.filename.lower().endswith(allowed_exts):
        return fail(message="unsupported video format", code=5012, http_status=400)

    BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    upload_dir = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "uploads", str(workspace_id)))
    os.makedirs(upload_dir, exist_ok=True)

    from werkzeug.utils import secure_filename
    orig_name = file.filename
    clean_name = secure_filename(orig_name) or "video.mp4"
    saved_filename = f"{uuid.uuid4().hex[:6]}_{clean_name}"
    save_path = os.path.join(upload_dir, saved_filename)

    file.save(save_path)
    duration = _get_video_duration(save_path)

    video_info = {
        "id": f"upload_{saved_filename}",
        "name": f"已上传:{orig_name}",
        "raw_filename": saved_filename,
        "filepath": f"storage/uploads/{workspace_id}/{saved_filename}",
        "url": f"storage/uploads/{workspace_id}/{saved_filename}",
        "media_url": build_media_url(
            f"/api/video/storage/uploads/{workspace_id}/{saved_filename}",
            path_scope(f"storage/uploads/{workspace_id}/{saved_filename}"),
        ),
        "duration": duration,
        "source_type": "upload"
    }

    return success(message="video uploaded successfully", data=video_info, http_status=201)


@workspaces_bp.post("/<int:workspace_id>/segments")
@jwt_required()
def create_video_segment(workspace_id):
    emp_id = get_jwt_identity()
    workspace = db.session.get(Workspace, workspace_id)
    if not workspace:
        return fail(message="workspace not found", code=5003, http_status=404)
        
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)

    data = request.get_json() or {}
    source_type = data.get("source_type", "upload")
    monitor_id = data.get("monitor_id")
    start_time = data.get("start_time")
    end_time = data.get("end_time")

    video_name = data.get("video_name")
    filepath_param = data.get("filepath")
    start_offset = data.get("start_offset")
    end_offset = data.get("end_offset")
    remark = data.get("remark") or ""
    enable_preprocess = data.get("enable_preprocess", True)
    sample_fps, resolution, option_error = _parse_preprocess_options(data)
    if option_error:
        return option_error

    from app.monitors.slicer import SLICE_OUTPUT_BASE
    from app.core.config import get_ffmpeg_path
    import subprocess

    BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    os.makedirs(SLICE_OUTPUT_BASE, exist_ok=True)

    sim_filename = f"slice_{workspace_id}_{uuid.uuid4().hex[:8]}.mp4"
    sim_output_path = os.path.join(SLICE_OUTPUT_BASE, sim_filename)

    # ================= 模式 1: 监控设备按起止日期时间截取 =================
    if source_type == "monitor" or (monitor_id and start_time and end_time):
        if not monitor_id or not start_time or not end_time:
            return fail(message="monitor_id, start_time, and end_time are required for monitor slicing", code=5014, http_status=400)

        from app.models.monitor import Monitor
        mon_obj = db.session.get(Monitor, monitor_id)
        if not mon_obj or mon_obj.group_id != workspace.group_id:
            return fail(message="monitor not found in this workspace group", code=5018, http_status=404)

        ok, msg, seg_duration = slice_and_concat_monitor_stream(monitor_id, start_time, end_time, sim_output_path)
        if not ok:
            return fail(message=msg, code=5015, http_status=400)

        mon_name = mon_obj.name
        display_video_name = f"{mon_name} ({start_time} - {end_time})"

        segment = WorkspaceVideoSegment(
            workspace_id=workspace_id,
            video_name=display_video_name,
            start_offset=0.0,
            end_offset=seg_duration,
            duration=seg_duration,
            remark=remark,
            filepath=f"storage/slices/{sim_filename}",
            status="pending" if enable_preprocess else "none",
            sample_fps=sample_fps,
            resolution=resolution,
            orig_resolution="1080P"
        )
        db.session.add(segment)
        db.session.commit()

        if enable_preprocess:
            app = current_app._get_current_object()
            t_analysis = threading.Thread(
                target=extract_segment_features_bg,
                args=(app, segment.filepath, os.path.basename(segment.filepath), segment.duration, sample_fps, resolution)
            )
            t_analysis.daemon = True
            t_analysis.start()

        return success(message="segment created from monitor", data=segment.to_dict(), http_status=201)

    # ================= 模式 2: 上传/示例视频文件偏移量裁剪 =================
    if (not video_name and not filepath_param) or start_offset is None or end_offset is None:
        return fail(message="video_name/filepath, start_offset, and end_offset are required", code=5006, http_status=400)

    try:
        start_offset = float(start_offset)
        end_offset = float(end_offset)
    except (TypeError, ValueError):
        return fail(message="start_offset and end_offset must be numbers", code=5019, http_status=400)
    if not math.isfinite(start_offset) or not math.isfinite(end_offset) or start_offset < 0 or end_offset <= start_offset:
        return fail(message="end_offset must be greater than start_offset", code=5019, http_status=400)
    duration = end_offset - start_offset
    if duration > 7200:
        return fail(message="a segment cannot exceed 2 hours", code=5019, http_status=400)

    src_video_path = None
    workspace_upload_dir = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "uploads", str(workspace_id)))
    example_dir = os.path.abspath(os.path.join(BACKEND_DIR, "..", "example"))
    allowed_source_roots = (workspace_upload_dir, example_dir)
    if filepath_param:
        abs_p = os.path.abspath(os.path.join(BACKEND_DIR, filepath_param))
        if any(_is_path_within(abs_p, root) for root in allowed_source_roots) and os.path.isfile(abs_p):
            src_video_path = abs_p

    if not src_video_path and video_name:
        safe_name = os.path.basename(str(video_name))
        for root in allowed_source_roots:
            candidate = os.path.abspath(os.path.join(root, safe_name))
            if _is_path_within(candidate, root) and os.path.isfile(candidate):
                src_video_path = candidate
                break

    if not src_video_path or not os.path.exists(src_video_path):
        return fail(message=f"source video file {video_name or filepath_param} not found", code=5007, http_status=404)

    orig_res = "1080P"
    try:
        import cv2
        cap = cv2.VideoCapture(src_video_path)
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()
        if h >= 2160:
            orig_res = "4K"
        elif h >= 1080:
            orig_res = "1080P"
        elif h >= 720:
            orig_res = "720P"
        else:
            orig_res = "480P"
    except Exception:
        orig_res = "1080P"

    try:
        ffmpeg_bin = get_ffmpeg_path("ffmpeg")
        cmd = [
            ffmpeg_bin, "-y",
            "-ss", f"{start_offset:.3f}",
            "-t", f"{duration:.3f}",
            "-i", src_video_path,
            "-c:v", "copy",
            "-c:a", "aac",
            "-map", "0:v",
            "-map", "0:a?",
            sim_output_path
        ]
        print(f"[Workspace API Slicing Segment] command: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if result.returncode != 0 or not os.path.exists(sim_output_path) or os.path.getsize(sim_output_path) <= 1000:
            print(f"[Workspace API Slicing ERROR] exit code {result.returncode}. Stderr:\n{result.stderr}")
            return fail(message="FFmpeg slicing failed", code=5008, http_status=500)

        segment = WorkspaceVideoSegment(
            workspace_id=workspace_id,
            video_name=video_name or os.path.basename(src_video_path),
            start_offset=start_offset,
            end_offset=end_offset,
            duration=duration,
            remark=remark,
            filepath=f"storage/slices/{sim_filename}",
            status="pending" if enable_preprocess else "none",
            sample_fps=sample_fps,
            resolution=resolution,
            orig_resolution=orig_res
        )
        db.session.add(segment)
        db.session.commit()

        if enable_preprocess:
            app = current_app._get_current_object()
            t_analysis = threading.Thread(
                target=extract_segment_features_bg,
                args=(app, segment.filepath, os.path.basename(segment.filepath), segment.duration, sample_fps, resolution)
            )
            t_analysis.daemon = True
            t_analysis.start()

        return success(message="segment created", data=segment.to_dict(), http_status=201)

    except Exception as e:
        print(f"[Workspace API Slicing EXCEPTION] {e}")
        return fail(message=f"slicing exception: {str(e)}", code=5009, http_status=500)


@workspaces_bp.get("/<int:workspace_id>/segments")
@jwt_required()
def list_video_segments(workspace_id):
    emp_id = get_jwt_identity()
    workspace = db.session.get(Workspace, workspace_id)
    if not workspace:
        return fail(message="workspace not found", code=5003, http_status=404)
        
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)

    segments = WorkspaceVideoSegment.query.filter_by(workspace_id=workspace_id).order_by(WorkspaceVideoSegment.created_at.desc()).all()
    return success(data=[s.to_dict() for s in segments])


@workspaces_bp.put("/segments/<int:segment_id>")
@jwt_required()
def edit_video_segment(segment_id):
    emp_id = get_jwt_identity()
    segment = db.session.get(WorkspaceVideoSegment, segment_id)
    if not segment:
        return fail(message="segment not found", code=5010, http_status=404)

    workspace = db.session.get(Workspace, segment.workspace_id)
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)

    data = request.get_json() or {}
    remark = data.get("remark")
    if remark is not None:
        segment.remark = remark
        db.session.commit()

    return success(message="segment updated", data=segment.to_dict())


@workspaces_bp.delete("/segments/<int:segment_id>")
@jwt_required()
def delete_video_segment(segment_id):
    emp_id = get_jwt_identity()
    segment = db.session.get(WorkspaceVideoSegment, segment_id)
    if not segment:
        return fail(message="segment not found", code=5010, http_status=404)

    workspace = db.session.get(Workspace, segment.workspace_id)
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)
    if _segment_has_active_qa(segment_id):
        return fail(message="QA task is still running", code=5024, http_status=409)
    if segment.status in ("pending", "processing"):
        return fail(message="segment preprocessing is still running", code=5021, http_status=409)
    if (QAVideoSelection.query.filter_by(segment_id=segment_id).first()
            or any(segment_id in conversation.segment_ids() for conversation in
                   AgentConversation.query.filter_by(workspace_id=segment.workspace_id).all())):
        return fail(message="segment is referenced by investigation history", code=5024, http_status=409)

    video_id = os.path.basename(segment.filepath)
    try:
        from app.mva_v2.database import SpatiotemporalDB
        SpatiotemporalDB().delete_video(video_id, workspace_id=segment.workspace_id)
    except Exception as exc:
        return fail(message=f"failed to clear segment features: {exc}", code=5020, http_status=500)

    face_paths = _clear_segment_face_records(segment.id)

    db.session.delete(segment)
    db.session.commit()

    # Delete files only after the relational transaction has committed.
    for face_path in face_paths:
        _remove_backend_file(face_path)
    _remove_backend_file(segment.filepath)
    base, _ = os.path.splitext(segment.filepath)
    _remove_backend_file(f"{base}_thumb.jpg")

    return success(message="segment deleted")


@workspaces_bp.post("/segments/<int:segment_id>/preprocess")
@jwt_required()
def preprocess_segment(segment_id):
    emp_id = get_jwt_identity()
    segment = db.session.get(WorkspaceVideoSegment, segment_id)
    if not segment:
        return fail(message="segment not found", code=5003, http_status=404)
    _, error = _require_workspace_member(segment.workspace_id, emp_id)
    if error:
        return error
    data = request.get_json(silent=True) or {}
    sample_fps, resolution, option_error = _parse_preprocess_options(data)
    if option_error:
        return option_error
    if segment.status in ("pending", "processing"):
        return fail(message="segment preprocessing is already running", code=5021, http_status=409)
    if _segment_has_active_qa(segment_id):
        return fail(message="QA task is still running", code=5024, http_status=409)

    segment.sample_fps = sample_fps
    segment.resolution = resolution
    segment.status = "processing"
    segment.progress = 0
    segment.error_msg = None
    db.session.commit()

    app = current_app._get_current_object()
    t_analysis = threading.Thread(
        target=extract_segment_features_bg,
        args=(app, segment.filepath, os.path.basename(segment.filepath), segment.duration, sample_fps, resolution)
    )
    t_analysis.daemon = True
    t_analysis.start()

    return success(message="preprocess started", data=segment.to_dict())


@workspaces_bp.delete("/segments/<int:segment_id>/features")
@jwt_required()
def delete_segment_features(segment_id):
    emp_id = get_jwt_identity()
    segment = db.session.get(WorkspaceVideoSegment, segment_id)
    if not segment:
        return fail(message="segment not found", code=5003, http_status=404)
    _, error = _require_workspace_member(segment.workspace_id, emp_id)
    if error:
        return error
    if segment.status in ("pending", "processing"):
        return fail(message="segment preprocessing is still running", code=5021, http_status=409)
    if _segment_has_active_qa(segment_id):
        return fail(message="QA task is still running", code=5024, http_status=409)

    # 从时空特征库和人脸库中删除该片段的已知特征。
    video_id = os.path.basename(segment.filepath)
    try:
        from app.mva_v2.database import SpatiotemporalDB
        db_client = SpatiotemporalDB()
        db_client.delete_video(video_id, workspace_id=segment.workspace_id)
    except Exception as e:
        return fail(message=f"failed to clear segment features: {e}", code=5020, http_status=500)

    face_paths = _clear_segment_face_records(segment.id)

    segment.status = "none"
    segment.progress = 0
    segment.error_msg = None
    db.session.commit()

    for face_path in face_paths:
        _remove_backend_file(face_path)

    return success(message="features cleared", data=segment.to_dict())

# ========================================================
# 工作区人脸分类模块 API (Workspace Face Classification APIs)
# ========================================================

@workspaces_bp.get("/face-backend")
@jwt_required()
def get_face_backend():
    from app.user_center.permissions import current_user
    from .face_engine import configured_face_backend
    if not current_user() or not current_user().is_active:
        return fail(message="permission denied", code=5001, http_status=403)
    try:
        return success(data={"mode": configured_face_backend()})
    except ValueError as exc:
        return fail(message=str(exc), code=5020, http_status=500)


@workspaces_bp.get("/<int:workspace_id>/faces/harmony/queue")
@jwt_required()
def get_harmony_face_queue(workspace_id):
    _, error = _require_workspace_member(workspace_id, get_jwt_identity())
    if error:
        return error
    from app.models.face import WorkspaceFaceRecord
    pending_query = WorkspaceFaceRecord.query.filter_by(
        workspace_id=workspace_id, classification_backend="harmony_pending")
    pending = pending_query.order_by(WorkspaceFaceRecord.id).limit(30).all()
    # A reference crop per classified group; pending groups join this gallery on the phone.
    representative_ids = db.session.query(db.func.min(WorkspaceFaceRecord.id)).filter(
        WorkspaceFaceRecord.workspace_id == workspace_id,
        WorkspaceFaceRecord.classification_backend.in_(("server", "harmony"))
    ).group_by(WorkspaceFaceRecord.group_id).all()
    gallery = WorkspaceFaceRecord.query.filter(
        WorkspaceFaceRecord.id.in_([record_id for (record_id,) in representative_ids])
    ).order_by(WorkspaceFaceRecord.id).all() if representative_ids else []
    return success(data={"pending": [record.to_dict() for record in pending],
                         "remaining": pending_query.count(), "gallery": [record.to_dict() for record in gallery]})


@workspaces_bp.post("/<int:workspace_id>/faces/harmony/classify")
@jwt_required()
def classify_harmony_faces(workspace_id):
    error = _face_edit_guard(workspace_id)
    if error:
        return error
    from app.models.face import WorkspaceFaceGroup, WorkspaceFaceRecord
    assignments = (request.get_json(silent=True) or {}).get("assignments")
    if not isinstance(assignments, list) or not 1 <= len(assignments) <= 30:
        return fail(message="provide 1 to 30 face assignments", code=5004, http_status=400)
    seen = set()
    records = {}
    for item in assignments:
        if not isinstance(item, dict) or type(item.get("record_id")) is not int or type(item.get("target_group_id")) is not int:
            return fail(message="invalid face assignment", code=5004, http_status=400)
        record_id, target_id = item["record_id"], item["target_group_id"]
        if record_id in seen:
            return fail(message="duplicate face record", code=5004, http_status=400)
        seen.add(record_id)
        record = WorkspaceFaceRecord.query.filter_by(id=record_id, workspace_id=workspace_id,
                                                     classification_backend="harmony_pending").first()
        target = WorkspaceFaceGroup.query.filter_by(id=target_id, workspace_id=workspace_id).first()
        if not record or not target:
            return fail(message="face record or group not found", code=5010, http_status=404)
        records[record_id] = (record, target_id)
    removed_avatars = []
    # Every target must already have a classified record, or precede the current
    # record in this batch. This prevents assigning into an untouched provisional group.
    finalized_groups = {group_id for (group_id,) in db.session.query(WorkspaceFaceRecord.group_id).filter(
        WorkspaceFaceRecord.workspace_id == workspace_id,
        WorkspaceFaceRecord.classification_backend.in_(("harmony", "server"))).distinct().all()}
    for item in assignments:
        record, target_id = records[item["record_id"]]
        if target_id not in finalized_groups and target_id != record.group_id:
            db.session.rollback()
            return fail(message="target group is not classified yet", code=5004, http_status=400)
        if target_id != record.group_id and WorkspaceFaceRecord.query.filter(
                WorkspaceFaceRecord.workspace_id == workspace_id,
                WorkspaceFaceRecord.segment_id == record.segment_id,
                WorkspaceFaceRecord.group_id == target_id,
                WorkspaceFaceRecord.classification_backend != "harmony_pending",
                WorkspaceFaceRecord.start_time_offset <= record.end_time_offset,
                WorkspaceFaceRecord.end_time_offset >= record.start_time_offset).first():
            # Two faces visible at the same time cannot be the same person.
            target_id = record.group_id
        old_group_id = record.group_id
        record.group_id = target_id
        record.classification_backend = "harmony"
        db.session.flush()
        finalized_groups.add(target_id)
        if old_group_id != target_id:
            avatar = _remove_empty_face_group(old_group_id)
            if avatar:
                removed_avatars.append(avatar)
    db.session.commit()
    for avatar in removed_avatars:
        _remove_backend_file(avatar)
    return success(data={"classified": len(assignments)})

@workspaces_bp.get("/<int:workspace_id>/faces")
@jwt_required()
def get_workspace_faces(workspace_id):
    emp_id = get_jwt_identity()
    _, error = _require_workspace_member(workspace_id, emp_id)
    if error:
        return error
    from app.models.face import WorkspaceFaceGroup, WorkspaceFaceRecord
    segment_id = request.args.get("segment_id", type=int)
    if segment_id is not None and not WorkspaceVideoSegment.query.filter_by(id=segment_id, workspace_id=workspace_id).first():
        return fail(message="segment not found in workspace", code=5011, http_status=404)
    groups = WorkspaceFaceGroup.query.filter_by(workspace_id=workspace_id).order_by(WorkspaceFaceGroup.id.asc()).all()
    res = []
    for group in groups:
        if segment_id is None:
            res.append(group.to_dict())
        else:
            count = WorkspaceFaceRecord.query.filter_by(group_id=group.id, segment_id=segment_id).count()
            if count:
                data = group.to_dict()
                data["record_count"] = count
                res.append(data)
    return success(data=res)


@workspaces_bp.get("/<int:workspace_id>/faces/<int:group_id>/records")
@jwt_required()
def get_face_group_records(workspace_id, group_id):
    emp_id = get_jwt_identity()
    _, error = _require_workspace_member(workspace_id, emp_id)
    if error:
        return error
    from app.models.face import WorkspaceFaceRecord
    segment_id = request.args.get("segment_id", type=int)
    records_query = WorkspaceFaceRecord.query.filter_by(workspace_id=workspace_id, group_id=group_id)
    if segment_id is not None:
        records_query = records_query.filter_by(segment_id=segment_id)
    records = records_query.order_by(WorkspaceFaceRecord.start_time_offset.asc()).all()
    res = [r.to_dict() for r in records]
    return success(data=res)


def _face_edit_guard(workspace_id):
    _, error = _require_workspace_member(workspace_id)
    if error:
        return error
    if WorkspaceVideoSegment.query.filter(
            WorkspaceVideoSegment.workspace_id == workspace_id,
            WorkspaceVideoSegment.status.in_(("pending", "processing"))).first():
        return fail(message="wait for face preprocessing to finish", code=5021, http_status=409)
    return None


def _remove_empty_face_group(group_id):
    from app.models.face import WorkspaceFaceGroup, WorkspaceFaceRecord
    group = db.session.get(WorkspaceFaceGroup, group_id)
    if group and not WorkspaceFaceRecord.query.filter_by(group_id=group_id).first():
        avatar = group.avatar_path
        db.session.delete(group)
        db.session.flush()
        return avatar
    return None


@workspaces_bp.post("/<int:workspace_id>/faces/merge")
@jwt_required()
def merge_face_groups(workspace_id):
    error = _face_edit_guard(workspace_id)
    if error:
        return error
    from app.models.face import WorkspaceFaceGroup, WorkspaceFaceRecord
    data = request.get_json() or {}
    source_id, target_id = data.get("source_group_id"), data.get("target_group_id")
    if type(source_id) is not int or type(target_id) is not int or source_id == target_id:
        return fail(message="select two different face groups", code=5004, http_status=400)
    source = WorkspaceFaceGroup.query.filter_by(id=source_id, workspace_id=workspace_id).first()
    target = WorkspaceFaceGroup.query.filter_by(id=target_id, workspace_id=workspace_id).first()
    if not source or not target:
        return fail(message="face group not found", code=5010, http_status=404)
    WorkspaceFaceRecord.query.filter_by(group_id=source_id, workspace_id=workspace_id).update({"group_id": target_id})
    avatar = _remove_empty_face_group(source_id)
    db.session.commit()
    if avatar:
        _remove_backend_file(avatar)
    return success(data=target.to_dict())


@workspaces_bp.post("/<int:workspace_id>/faces/records/<int:record_id>/move")
@jwt_required()
def move_face_record(workspace_id, record_id):
    error = _face_edit_guard(workspace_id)
    if error:
        return error
    from app.models.face import WorkspaceFaceGroup, WorkspaceFaceRecord
    record = WorkspaceFaceRecord.query.filter_by(id=record_id, workspace_id=workspace_id).first()
    if not record:
        return fail(message="face record not found", code=5010, http_status=404)
    target_id = (request.get_json() or {}).get("target_group_id")
    created_avatar = None
    if target_id is None:
        new_group = WorkspaceFaceGroup(workspace_id=workspace_id, name="待命名人脸")
        db.session.add(new_group)
        db.session.flush()
        new_group.name = f"人脸 #{new_group.id}"
        created_avatar = f"storage/faces/avatar_ws{workspace_id}_g{new_group.id}_{uuid.uuid4().hex[:6]}.jpg"
        import shutil
        try:
            shutil.copyfile(os.path.join(_backend_root(), record.crop_path),
                            os.path.join(_backend_root(), created_avatar))
        except OSError:
            db.session.rollback()
            return fail(message="face crop not available", code=5010, http_status=404)
        new_group.avatar_path = created_avatar
        target_id = new_group.id
    elif type(target_id) is not int or not WorkspaceFaceGroup.query.filter_by(id=target_id, workspace_id=workspace_id).first():
        return fail(message="target face group not found", code=5010, http_status=404)
    if target_id == record.group_id:
        return fail(message="record is already in this group", code=5004, http_status=400)
    old_group_id = record.group_id
    record.group_id = target_id
    db.session.flush()
    old_avatar = _remove_empty_face_group(old_group_id)
    try:
        db.session.commit()
    except Exception:
        db.session.rollback()
        if created_avatar:
            _remove_backend_file(created_avatar)
        raise
    if old_avatar:
        _remove_backend_file(old_avatar)
    return success(data={"group_id": target_id})
