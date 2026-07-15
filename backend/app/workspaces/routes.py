import uuid
import time
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

def extract_segment_features_bg(app, filepath, video_id, duration):
    with app.app_context():
        # 获取对应的数据库记录，设置状态为 processing
        seg = WorkspaceVideoSegment.query.filter_by(filepath=filepath).first()
        if seg:
            seg.status = "processing"
            seg.progress = 0
            db.session.commit()
            
        try:
            import asyncio
            from app.mva_v2.database import SpatiotemporalDB
            from app.mva_v2.pipeline import JITVideoPipeline
            
            db_client = SpatiotemporalDB()
            
            # 定义更新数据库进度的回调函数
            def progress_callback(pct):
                db.session.query(WorkspaceVideoSegment).filter_by(filepath=filepath).update({"progress": pct})
                db.session.commit()

            print(f"[BG FEATURE EXTRACTION] Starting JIT feature extraction for {video_id}...")
            pipeline = JITVideoPipeline(db_client)
            
            BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            abs_filepath = os.path.join(BACKEND_DIR, filepath)
            
            asyncio.run(pipeline.process_clip(abs_filepath, video_id, 0.0, duration, progress_callback=progress_callback))
            
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

def process_qa_thread(app, task_id, question, video_paths):
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
                progress_callback=progress_callback
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
        
    from app.core.config import get_ffmpeg_path
    import subprocess
    
    video_files = [f for f in os.listdir(example_dir) if f.endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm'))]
    results = []
    
    for vf in video_files:
        path = os.path.join(example_dir, vf)
        duration = 0.0
        try:
            cmd = [
                get_ffmpeg_path('ffprobe'), '-v', 'quiet', '-show_entries', 'format=duration',
                '-of', 'default=noprint_wrappers=1:nokey=1', path
            ]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            duration = float(res.stdout.strip())
        except Exception as e:
            print(f"[Workspace QA] Failed to get duration of {vf}: {e}")
            
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
    from datetime import timedelta
    base_time = datetime(2026, 6, 27, 0, 0, 0)
    for seg_id in segment_ids:
        segment = WorkspaceVideoSegment.query.filter_by(id=seg_id, workspace_id=workspace_id).first()
        if not segment:
            return fail(message=f"segment {seg_id} not found in this workspace", code=5011, http_status=404)
        
        # 校验分析状态：提问时不可选择未分析完的片段
        if segment.status != "completed":
            return fail(message=f"片段 '{segment.video_name}' (ID: {seg_id}) 仍在分析预处理中 ({segment.progress}%)，请稍候再提问", code=5012, http_status=400)
        
        video_paths.append(segment.filepath)
        
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
    t = threading.Thread(target=process_qa_thread, args=(app, task_id, question, video_paths))
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
    video_name = data.get("video_name")
    start_offset = data.get("start_offset")
    end_offset = data.get("end_offset")
    remark = data.get("remark") or ""

    if not video_name or start_offset is None or end_offset is None:
        return fail(message="video_name, start_offset, and end_offset are required", code=5006, http_status=400)

    start_offset = float(start_offset)
    end_offset = float(end_offset)
    duration = max(0.1, end_offset - start_offset)

    from app.monitors.slicer import SLICE_OUTPUT_BASE
    from app.core.config import get_ffmpeg_path
    import subprocess

    BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    example_dir = os.path.abspath(os.path.join(BACKEND_DIR, "..", "example"))
    os.makedirs(SLICE_OUTPUT_BASE, exist_ok=True)

    example_video_path = os.path.join(example_dir, video_name)
    if not os.path.exists(example_video_path):
        return fail(message=f"example video file {video_name} not found", code=5007, http_status=404)

    sim_filename = f"slice_{workspace_id}_{uuid.uuid4().hex[:8]}.mp4"
    sim_output_path = os.path.join(SLICE_OUTPUT_BASE, sim_filename)

    try:
        ffmpeg_bin = get_ffmpeg_path("ffmpeg")
        cmd = [
            ffmpeg_bin, "-y",
            "-ss", f"{start_offset:.3f}",
            "-t", f"{duration:.3f}",
            "-i", example_video_path,
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

        # Save to database
        segment = WorkspaceVideoSegment(
            workspace_id=workspace_id,
            video_name=video_name,
            start_offset=start_offset,
            end_offset=end_offset,
            duration=duration,
            remark=remark,
            filepath=f"storage/slices/{sim_filename}"
        )
        db.session.add(segment)
        db.session.commit()

        # Trigger background JIT feature extraction immediately after slicing
        app = current_app._get_current_object()
        t_analysis = threading.Thread(
            target=extract_segment_features_bg,
            args=(app, segment.filepath, os.path.basename(segment.filepath), segment.duration)
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
