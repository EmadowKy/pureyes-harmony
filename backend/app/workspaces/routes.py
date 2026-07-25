import uuid
import time
import re
from datetime import datetime
from flask import request, Response, stream_with_context
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.db import db
from app.models.workspace import Workspace, WorkspaceVideoSegment
from app.models.group import GroupMember
from app.models.qa_record import QARecord, QAVideoSelection
from app.core.response import success, fail
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
from queue import Queue
from flask import current_app

# Global in-memory running tasks registry
running_tasks = {}

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
            
            asyncio.run(pipeline.process_clip(abs_filepath, video_id, 0.0, duration, progress_callback=progress_callback, sample_fps=sample_fps, resolution=resolution))
            
            db_client.flush()

            # 执行新增工序：人脸识别检测、归类与连贯时间段聚合
            try:
                if seg:
                    process_segment_face_recognition(seg.workspace_id, seg.id, abs_filepath, seg.video_name or seg.filepath, sample_fps)
            except Exception as face_err:
                print(f"[FACE EXTRACTION ERROR] {face_err}")

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
    """
    预处理工序：人脸识别分类与连贯时间段聚合
    1. 逐帧检测截取人脸
    2. 将连续或间隔很短 (<= 3.5s) 的检测帧合成为一条包含起止时间段的轨迹记录
    3. 与工作区现有人脸库进行归类聚类 (Group Classifier)
    """
    try:
        import cv2
        import numpy as np
        import os
        from datetime import datetime
        from app.core.db import db
        from app.models.face import WorkspaceFaceGroup, WorkspaceFaceRecord

        if not os.path.exists(abs_filepath):
            return

        BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        face_storage_dir = os.path.join(BACKEND_DIR, "storage", "faces")
        os.makedirs(face_storage_dir, exist_ok=True)

        cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        face_cascade = cv2.CascadeClassifier(cascade_path)

        cap = cv2.VideoCapture(abs_filepath)
        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps <= 0:
            fps = 30.0

        frame_interval = max(1, int(fps / sample_fps))
        frame_idx = 0

        raw_hits = []

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret or frame is None:
                break

            if frame_idx % frame_interval == 0:
                timestamp = frame_idx / fps
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(30, 30))

                for (x, y, w, h) in faces:
                    pad_w = int(w * 0.15)
                    pad_h = int(h * 0.15)
                    h_img, w_img = frame.shape[:2]

                    x1 = max(0, x - pad_w)
                    y1 = max(0, y - pad_h)
                    x2 = min(w_img, x + w + pad_w)
                    y2 = min(h_img, y + h + pad_h)

                    face_crop = frame[y1:y2, x1:x2]
                    if face_crop.shape[0] < 10 or face_crop.shape[1] < 10:
                        continue

                    hsv = cv2.cvtColor(face_crop, cv2.COLOR_BGR2HSV)
                    hist = cv2.calcHist([hsv], [0, 1], None, [180, 256], [0, 180, 0, 256])
                    cv2.normalize(hist, hist, alpha=0, beta=1, norm_type=cv2.NORM_MINMAX)

                    raw_hits.append({
                        'timestamp': timestamp,
                        'crop_img': face_crop,
                        'hist': hist
                    })

            frame_idx += 1

        cap.release()

        if not raw_hits:
            return

        # 连贯时间段聚合算法
        aggregated_tracks = []
        if raw_hits:
            curr_track = [raw_hits[0]]
            for i in range(1, len(raw_hits)):
                prev_hit = curr_track[-1]
                hit = raw_hits[i]

                sim = cv2.compareHist(prev_hit['hist'], hit['hist'], cv2.HISTCMP_CORREL)
                if (hit['timestamp'] - prev_hit['timestamp'] <= 3.5) and (sim >= 0.40):
                    curr_track.append(hit)
                else:
                    aggregated_tracks.append(curr_track)
                    curr_track = [hit]
            if curr_track:
                aggregated_tracks.append(curr_track)

        # 聚类归类
        existing_groups = WorkspaceFaceGroup.query.filter_by(workspace_id=workspace_id).all()
        group_hists = {}
        for g in existing_groups:
            if g.avatar_path:
                full_avatar_path = os.path.join(BACKEND_DIR, g.avatar_path)
                if os.path.exists(full_avatar_path):
                    av_img = cv2.imread(full_avatar_path)
                    if av_img is not None:
                        av_hsv = cv2.cvtColor(av_img, cv2.COLOR_BGR2HSV)
                        av_hist = cv2.calcHist([av_hsv], [0, 1], None, [180, 256], [0, 180, 0, 256])
                        cv2.normalize(av_hist, av_hist, alpha=0, beta=1, norm_type=cv2.NORM_MINMAX)
                        group_hists[g.id] = av_hist

        for track in aggregated_tracks:
            start_sec = track[0]['timestamp']
            end_sec = track[-1]['timestamp']
            
            if end_sec == start_sec:
                end_sec = start_sec + 1.5

            def format_time_str(sec):
                m = int(sec // 60)
                s = int(sec % 60)
                return f"{m:02d}:{s:02d}"

            start_str = format_time_str(start_sec)
            end_str = format_time_str(end_sec)

            best_hit = track[len(track) // 2]
            crop_filename = f"crop_ws{workspace_id}_seg{segment_id}_{int(start_sec)}_{uuid.uuid4().hex[:6]}.jpg"
            rel_crop_path = os.path.join("storage", "faces", crop_filename)
            abs_crop_path = os.path.join(BACKEND_DIR, rel_crop_path)
            cv2.imwrite(abs_crop_path, best_hit['crop_img'])

            matched_group_id = None
            max_sim = -1.0
            for g_id, av_hist in group_hists.items():
                sim = cv2.compareHist(best_hit['hist'], av_hist, cv2.HISTCMP_CORREL)
                if sim > max_sim:
                    max_sim = sim
                    matched_group_id = g_id

            if matched_group_id is None or max_sim < 0.55:
                next_num = len(WorkspaceFaceGroup.query.filter_by(workspace_id=workspace_id).all()) + 1
                group_name = f"人脸 #{next_num}"
                
                avatar_filename = f"avatar_ws{workspace_id}_g{next_num}_{uuid.uuid4().hex[:6]}.jpg"
                rel_avatar_path = os.path.join("storage", "faces", avatar_filename)
                abs_avatar_path = os.path.join(BACKEND_DIR, rel_avatar_path)
                cv2.imwrite(abs_avatar_path, best_hit['crop_img'])

                new_group = WorkspaceFaceGroup(
                    workspace_id=workspace_id,
                    name=group_name,
                    avatar_path=rel_avatar_path
                )
                db.session.add(new_group)
                db.session.flush()

                matched_group_id = new_group.id
                group_hists[matched_group_id] = best_hit['hist']

            record = WorkspaceFaceRecord(
                workspace_id=workspace_id,
                group_id=matched_group_id,
                segment_id=segment_id,
                crop_path=rel_crop_path,
                video_name=video_name,
                start_time_offset=round(start_sec, 2),
                end_time_offset=round(end_sec, 2),
                start_time_str=start_str,
                end_time_str=end_str
            )
            db.session.add(record)

        db.session.commit()
        print(f"[FACE RECOGNITION] Successfully processed face recognition for segment {segment_id}. Detected {len(aggregated_tracks)} tracks.")

    except Exception as err:
        print(f"[FACE RECOGNITION ERROR] Failed to process face recognition: {err}")

def process_qa_thread(app, task_id, question, video_paths, segment_metas=None):
    with app.app_context():
        try:
            # Stage 1: Video Slicing
            init_msg = {
                "stage": "slicing",
                "status": "started",
                "message": "检测到预剪切视频片段，准备模型推理"
            }
            running_tasks[task_id]['progress'].append(init_msg)
            running_tasks[task_id]['progress_queue'].put(init_msg)

            slice_completed = {
                "stage": "slicing",
                "status": "completed",
                "message": "视频时间段高精度物理裁剪完成，切片已就绪"
            }
            running_tasks[task_id]['progress'].append(slice_completed)
            running_tasks[task_id]['progress_queue'].put(slice_completed)

            # Stage 2: MVA V2 Engine Initialization
            model_init = {
                "stage": "model_initialization",
                "status": "started",
                "message": "MVA V2 按需分析引擎初始化中..."
            }
            running_tasks[task_id]['progress'].append(model_init)
            running_tasks[task_id]['progress_queue'].put(model_init)

            record = QARecord.query.get(task_id)
            if not record:
                raise RuntimeError("QA 记录未找到。")

            from app.models.user import User
            creator = User.query.filter_by(emp_id=record.creator_id).first()
            if not creator or not creator.llm_api_key or not creator.llm_base_url:
                raise RuntimeError("未配置大模型 API 参数，请先到‘我的’页面配置 API KEY 和 BASE URL。")

            # 配置 api_config 供后端的 Qwen_VL 调用
            import sys
            import importlib
            mva_utils = importlib.import_module("app.mva.utils")
            sys.modules['utils'] = mva_utils
            
            api_config = mva_utils.api_config
            api_config.api_key = creator.llm_api_key
            api_config.base_url = creator.llm_base_url
            api_config.model = creator.llm_model
            api_config.task_id = task_id
            api_config.is_final_answer = True

            # Import MVA V2 ask_model (interface contract identical to old version)
            try:
                from app.qa.run_model import ask_model
            except Exception as import_err:
                raise RuntimeError(f"MVA V2 引擎依赖库导入失败: {str(import_err)}")

            config_path = os.path.join(app.root_path, "../configs/model.yaml")
            
            def progress_callback(item):
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
                    "data": data_val
                }
                running_tasks[task_id]['progress'].append(prog_entry)
                running_tasks[task_id]['progress_queue'].put(prog_entry)

            # Call MVA V2 ask_model
            result = ask_model(
                question=question,
                video_paths=video_paths,
                config_path=config_path,
                progress_callback=progress_callback,
                segment_metas=segment_metas
            )

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
                "data": {}
            }
            running_tasks[task_id]['progress'].append(complete_entry)
            running_tasks[task_id]['progress_queue'].put(complete_entry)

            # Save to Database
            record = QARecord.query.get(task_id)
            if record:
                record.status = "completed"
                record.answer = answer
                import json
                record.progress_json = json.dumps(running_tasks[task_id]['progress'])
                db.session.commit()

            running_tasks[task_id]['status'] = "completed"
            running_tasks[task_id]['answer'] = answer

        except Exception as e:
            import traceback
            tb_str = traceback.format_exc()
            print(f"[QA THREAD ERROR] {tb_str}")

            error_entry = {
                "stage": "system",
                "status": "failed",
                "message": f"分析发生错误：{str(e)}\n{tb_str}",
                "data": {}
            }
            running_tasks[task_id]['progress'].append(error_entry)
            running_tasks[task_id]['progress_queue'].put(error_entry)

            # Save failure to Database
            record = QARecord.query.get(task_id)
            if record:
                record.status = "failed"
                record.answer = f"分析发生错误：{str(e)}\n{tb_str}"
                import json
                record.progress_json = json.dumps(running_tasks[task_id]['progress'])
                db.session.commit()

            running_tasks[task_id]['status'] = "failed"
            running_tasks[task_id]['error'] = str(e)
            running_tasks[task_id]['traceback'] = tb_str


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
            "duration": duration
        })
        
    return success(data=results)


@workspaces_bp.post("/<int:workspace_id>/qa")
@jwt_required()
def submit_qa(workspace_id):
    emp_id = get_jwt_identity()
    workspace = Workspace.query.get(workspace_id)
    if not workspace:
        return fail(message="workspace not found", code=5003, http_status=404)
        
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)
        
    data = request.get_json() or {}
    question = data.get("question")
    segment_ids = data.get("segment_ids", [])
    
    if not question or not segment_ids:
        return fail(message="question and segment_ids are required", code=5004, http_status=400)
        
    task_id = uuid.uuid4().hex
    record = QARecord(id=task_id, workspace_id=workspace_id, creator_id=emp_id, question=question, status="processing")
    db.session.add(record)
    
    video_paths = []
    segment_metas = []
    from datetime import timedelta
    base_time = datetime(2026, 6, 27, 0, 0, 0)
    for seg_id in segment_ids:
        segment = WorkspaceVideoSegment.query.filter_by(id=seg_id, workspace_id=workspace_id).first()
        if not segment:
            return fail(message=f"segment {seg_id} not found in this workspace", code=5011, http_status=404)
        
        video_paths.append(segment.filepath)
        segment_metas.append(segment.to_dict())
        
        # Add selection row in DB
        qvs = QAVideoSelection(
            record_id=task_id,
            monitor_id=0,
            start_time=base_time + timedelta(seconds=segment.start_offset),
            end_time=base_time + timedelta(seconds=segment.end_offset)
        )
        db.session.add(qvs)
            
    db.session.commit()
    
    # Initialize in-memory task tracker
    running_tasks[task_id] = {
        "status": "processing",
        "progress": [
            {
                "stage": "metadata",
                "status": "completed",
                "message": "Metadata initialization",
                "data": {"video_paths": video_paths}
            }
        ],
        "progress_queue": Queue(),
        "answer": None,
        "error": None,
        "video_paths": video_paths
    }
    
    # Start thread
    app = current_app._get_current_object()
    t = threading.Thread(target=process_qa_thread, args=(app, task_id, question, video_paths, segment_metas))
    t.daemon = True
    t.start()
    
    return success(message="qa task submitted", data={"task_id": task_id})


@workspaces_bp.get("/<int:workspace_id>/qa")
@jwt_required()
def list_qa_records(workspace_id):
    emp_id = get_jwt_identity()
    workspace = Workspace.query.get(workspace_id)
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


@workspaces_bp.get("/qa/<task_id>/status")
@jwt_required()
def get_qa_status(task_id):
    # Fetch from memory if running, otherwise database
    if task_id in running_tasks:
        task_info = running_tasks[task_id]
        return success(data={
            "status": task_info["status"],
            "progress": task_info["progress"],
            "answer": task_info["answer"],
            "error": task_info["error"],
            "video_paths": task_info.get("video_paths", [])
        })
    else:
        record = QARecord.query.get(task_id)
        if not record:
            return fail(message="task not found", code=5005, http_status=404)
            
        progress_data = []
        if record.progress_json:
            try:
                import json
                progress_data = json.loads(record.progress_json)
            except:
                pass
        
        if not progress_data:
            progress_data = [{
                "stage": "answering",
                "status": record.status,
                "message": record.answer or ("已完成" if record.status == "completed" else "任务失败")
            }]
            
        video_paths = []
        for entry in progress_data:
            if entry.get("stage") == "metadata":
                video_paths = entry.get("data", {}).get("video_paths", [])
                break
                
        # Database Fallback for older historical records
        if not video_paths:
            from app.models.qa_record import QAVideoSelection
            from app.models.workspace import WorkspaceVideoSegment
            from datetime import datetime
            base_time = datetime(2026, 6, 27, 0, 0, 0)
            sels = QAVideoSelection.query.filter_by(record_id=task_id).all()
            for s in sels:
                start_offset = (s.start_time - base_time).total_seconds()
                end_offset = (s.end_time - base_time).total_seconds()
                seg = WorkspaceVideoSegment.query.filter(
                    WorkspaceVideoSegment.workspace_id == record.workspace_id,
                    WorkspaceVideoSegment.start_offset >= start_offset - 0.5,
                    WorkspaceVideoSegment.start_offset <= start_offset + 0.5,
                    WorkspaceVideoSegment.end_offset >= end_offset - 0.5,
                    WorkspaceVideoSegment.end_offset <= end_offset + 0.5
                ).first()
                if seg:
                    video_paths.append(seg.filepath)
                else:
                    video_paths.append(f"deleted_placeholder_{s.id}")
                    
        return success(data={
            "status": record.status,
            "progress": progress_data,
            "answer": record.answer if record.status == "completed" else None,
            "error": record.answer if record.status == "failed" else None,
            "video_paths": video_paths
        })


@workspaces_bp.get("/qa/<task_id>/stream")
def qa_stream(task_id):
    # SSE stream endpoint
    if task_id not in running_tasks:
        record = QARecord.query.get(task_id)
        if not record:
            return "Not found", 404
            
        def generate_static():
            import json
            yield f"data: {json.dumps({'type': 'connected', 'task_id': task_id})}\n\n"
            yield f"data: {json.dumps({'type': 'complete', 'status': record.status, 'answer': record.answer})}\n\n"
        return Response(stream_with_context(generate_static()), mimetype="text/event-stream")
        
    def generate():
        import json
        yield f"data: {json.dumps({'type': 'connected', 'task_id': task_id})}\n\n"
        
        # Yield existing progress logs
        task_info = running_tasks[task_id]
        for p in task_info['progress']:
            yield f"data: {json.dumps({'type': 'progress', 'data': p})}\n\n"
            
        # Stream new progress logs from queue
        q = task_info['progress_queue']
        while True:
            if task_info['status'] in ['completed', 'failed']:
                # Drain the queue first
                while not q.empty():
                    p = q.get()
                    yield f"data: {json.dumps({'type': 'progress', 'data': p})}\n\n"
                
                yield f"data: {json.dumps({'type': 'complete', 'status': task_info['status'], 'answer': task_info['answer'], 'error': task_info['error']})}\n\n"
                break
                
            try:
                # Wait for new progress with a timeout to check if status changed
                p = q.get(timeout=0.2)
                yield f"data: {json.dumps({'type': 'progress', 'data': p})}\n\n"
            except:
                pass
                
    return Response(stream_with_context(generate()), mimetype="text/event-stream")


@workspaces_bp.delete("/qa/<task_id>")
@jwt_required()
def delete_qa_record(task_id):
    emp_id = get_jwt_identity()
    record = QARecord.query.get(task_id)
    if not record:
        return fail(message="record not found", code=5005, http_status=404)
        
    workspace = Workspace.query.get(record.workspace_id)
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)
        
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
    workspace = Workspace.query.get(workspace_id)
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
    upload_dir = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "uploads"))
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
                "filepath": f"storage/uploads/{uf}",
                "url": f"storage/uploads/{uf}",
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
    workspace = Workspace.query.get(workspace_id)
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
    upload_dir = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "uploads"))
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
        "filepath": f"storage/uploads/{saved_filename}",
        "url": f"storage/uploads/{saved_filename}",
        "duration": duration,
        "source_type": "upload"
    }

    return success(message="video uploaded successfully", data=video_info, http_status=201)


@workspaces_bp.post("/<int:workspace_id>/segments")
@jwt_required()
def create_video_segment(workspace_id):
    emp_id = get_jwt_identity()
    workspace = Workspace.query.get(workspace_id)
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
    sample_fps = float(data.get("sample_fps", 1.0))
    resolution = str(data.get("resolution", "1080P"))

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

        ok, msg, seg_duration = slice_and_concat_monitor_stream(monitor_id, start_time, end_time, sim_output_path)
        if not ok:
            return fail(message=msg, code=5015, http_status=400)

        from app.models.monitor import Monitor
        mon_obj = Monitor.query.get(monitor_id)
        mon_name = mon_obj.name if mon_obj else f"监控设备#{monitor_id}"
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

    start_offset = float(start_offset)
    end_offset = float(end_offset)
    duration = max(0.1, end_offset - start_offset)

    src_video_path = None
    if filepath_param:
        abs_p = os.path.abspath(os.path.join(BACKEND_DIR, filepath_param))
        if os.path.exists(abs_p) and os.path.isfile(abs_p):
            src_video_path = abs_p

    if not src_video_path and video_name:
        cand_direct = os.path.abspath(os.path.join(BACKEND_DIR, video_name))
        if os.path.exists(cand_direct) and os.path.isfile(cand_direct):
            src_video_path = cand_direct

        if not src_video_path:
            cand_up = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "uploads", video_name))
            if os.path.exists(cand_up):
                src_video_path = cand_up

        if not src_video_path:
            streams_base = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "streams"))
            if os.path.exists(streams_base):
                for root, dirs, files in os.walk(streams_base):
                    if video_name in files:
                        src_video_path = os.path.join(root, video_name)
                        break

        if not src_video_path:
            example_dir = os.path.abspath(os.path.join(BACKEND_DIR, "..", "example"))
            cand_ex = os.path.join(example_dir, video_name)
            if os.path.exists(cand_ex):
                src_video_path = cand_ex

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
    workspace = Workspace.query.get(workspace_id)
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
    segment = WorkspaceVideoSegment.query.get(segment_id)
    if not segment:
        return fail(message="segment not found", code=5010, http_status=404)

    workspace = Workspace.query.get(segment.workspace_id)
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
    segment = WorkspaceVideoSegment.query.get(segment_id)
    if not segment:
        return fail(message="segment not found", code=5010, http_status=404)

    workspace = Workspace.query.get(segment.workspace_id)
    member = GroupMember.query.filter_by(group_id=workspace.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=5001, http_status=403)

    # Delete physical file if exists
    from app.monitors.slicer import SLICE_OUTPUT_BASE
    if segment.filepath:
        filename = os.path.basename(segment.filepath)
        file_path = os.path.join(SLICE_OUTPUT_BASE, filename)
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception as e:
                print(f"[Segment Delete] Failed to remove physical file {file_path}: {e}")

    db.session.delete(segment)
    db.session.commit()

    return success(message="segment deleted")


@workspaces_bp.post("/segments/<int:segment_id>/preprocess")
@jwt_required()
def preprocess_segment(segment_id):
    segment = WorkspaceVideoSegment.query.get(segment_id)
    if not segment:
        return fail(message="segment not found", code=5003, http_status=404)
    
    data = request.get_json() or {}
    sample_fps = float(data.get("sample_fps", 1.0))
    resolution = str(data.get("resolution", "1080P"))

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
    segment = WorkspaceVideoSegment.query.get(segment_id)
    if not segment:
        return fail(message="segment not found", code=5003, http_status=404)

    # 从 spatiotemporal_db.json 中删除该片段的已知特征
    video_id = os.path.basename(segment.filepath)
    try:
        from app.mva_v2.database import SpatiotemporalDB
        db_client = SpatiotemporalDB()
        db_client.records = [r for r in db_client.records if r.get("video_id") != video_id]
        db_client._save_to_disk()
    except Exception as e:
        print(f"[CLEAR FEATURES ERROR] {e}")

    segment.status = "none"
    segment.progress = 0
    segment.error_msg = None
    db.session.commit()

    return success(message="features cleared", data=segment.to_dict())

# ========================================================
# 工作区人脸分类模块 API (Workspace Face Classification APIs)
# ========================================================

@workspaces_bp.get("/<int:workspace_id>/faces")
@jwt_required()
def get_workspace_faces(workspace_id):
    from app.models.face import WorkspaceFaceGroup
    groups = WorkspaceFaceGroup.query.filter_by(workspace_id=workspace_id).order_by(WorkspaceFaceGroup.id.asc()).all()
    res = [g.to_dict() for g in groups]
    return success(data=res)


@workspaces_bp.get("/<int:workspace_id>/faces/<int:group_id>/records")
@jwt_required()
def get_face_group_records(workspace_id, group_id):
    from app.models.face import WorkspaceFaceRecord
    records = WorkspaceFaceRecord.query.filter_by(workspace_id=workspace_id, group_id=group_id).order_by(WorkspaceFaceRecord.id.asc()).all()
    res = [r.to_dict() for r in records]
    return success(data=res)
