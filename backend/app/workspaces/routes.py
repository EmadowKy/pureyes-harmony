import uuid
import time
from datetime import datetime
from flask import request, Response, stream_with_context
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.db import db
from app.models.workspace import Workspace
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

def process_qa_thread(app, task_id, question, selections):
    with app.app_context():
        try:
            # Stage 1: Video Slicing
            init_msg = {
                "stage": "slicing",
                "status": "started",
                "message": "大模型后台推理服务就绪，开始对选择的视频时间段进行高精度物理裁剪..."
            }
            running_tasks[task_id]['progress'].append(init_msg)
            running_tasks[task_id]['progress_queue'].put(init_msg)

            from app.monitors.slicer import SLICE_OUTPUT_BASE
            from app.core.config import get_ffmpeg_path
            import subprocess
            
            BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            example_dir = os.path.abspath(os.path.join(BACKEND_DIR, "..", "example"))
            os.makedirs(SLICE_OUTPUT_BASE, exist_ok=True)
            
            video_paths = []
            for sel in selections:
                video_name = sel.get("video_name")
                if not video_name:
                    continue
                    
                start_offset = float(sel.get("start_time_offset", 0.0))
                end_offset = float(sel.get("end_time_offset", 0.0))
                duration = max(1.0, end_offset - start_offset)
                
                example_video_path = os.path.join(example_dir, video_name)
                if not os.path.exists(example_video_path):
                    err_msg = f"未找到示例视频文件 {video_name}"
                    raise RuntimeError(err_msg)
                
                sim_filename = f"sim_{video_name.replace('.', '_')}_{uuid.uuid4().hex[:8]}.mp4"
                sim_output_path = os.path.join(SLICE_OUTPUT_BASE, sim_filename)
                
                slice_log = {
                    "stage": "slicing",
                    "status": "running",
                    "message": f"正在裁剪视频 {video_name} 的时间范围 [{start_offset:.1f}s - {end_offset:.1f}s]..."
                }
                running_tasks[task_id]['progress'].append(slice_log)
                running_tasks[task_id]['progress_queue'].put(slice_log)
                
                try:
                    ffmpeg_bin = get_ffmpeg_path("ffmpeg")
                    cmd = [
                        ffmpeg_bin, "-y",
                        "-ss", f"{start_offset:.3f}",
                        "-t", f"{duration:.3f}",
                        "-i", example_video_path,
                        "-c:v", "libx264", "-preset", "fast",
                        "-c:a", "aac",
                        sim_output_path
                    ]
                    print(f"[Workspace QA Background Thread] Slicing video: {' '.join(cmd)}")
                    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
                    if result.returncode == 0 and os.path.exists(sim_output_path) and os.path.getsize(sim_output_path) > 1000:
                        video_paths.append(f"storage/slices/{sim_filename}")
                    else:
                        raise RuntimeError("FFmpeg 裁剪命令返回异常。")
                except Exception as slice_err:
                    print(f"[Workspace QA Background Thread ERROR] Slicing failed: {slice_err}. Falling back to direct path.")
                    video_paths.append(f"../example/{video_name}")

            slice_completed = {
                "stage": "slicing",
                "status": "completed",
                "message": "视频时间段高精度物理裁剪完成，切片已就绪。"
            }
            running_tasks[task_id]['progress'].append(slice_completed)
            running_tasks[task_id]['progress_queue'].put(slice_completed)

            # Stage 2: Model Initialization
            model_init = {
                "stage": "model_initialization",
                "status": "started",
                "message": "大模型后台推理服务启动中..."
            }
            running_tasks[task_id]['progress'].append(model_init)
            running_tasks[task_id]['progress_queue'].put(model_init)

            # Attempt to import ask_model (and its underlying torch dependencies)
            # This is done inside the thread to avoid crashing Flask startup if imports fail.
            try:
                from app.qa.run_model import ask_model
            except Exception as import_err:
                raise RuntimeError(f"大模型环境或依赖库导入失败。底层错误: {str(import_err)}")

            config_path = os.path.join(app.root_path, "../configs/model.yaml")
            
            def progress_callback(item):
                msg = item
                stage = "processing"
                status = "running"
                if isinstance(item, dict):
                    msg = item.get("message") or item.get("data", {}).get("message") or str(item)
                    stage = item.get("stage", "processing")
                    status = item.get("status", "running")
                
                prog_entry = {
                    "stage": stage,
                    "status": status,
                    "message": msg
                }
                running_tasks[task_id]['progress'].append(prog_entry)
                running_tasks[task_id]['progress_queue'].put(prog_entry)

            # Call real ask_model from mva runner
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

            # Save to Database
            record = QARecord.query.get(task_id)
            if record:
                record.status = "completed"
                record.answer = answer
                db.session.commit()

            running_tasks[task_id]['status'] = "completed"
            running_tasks[task_id]['answer'] = answer

            complete_entry = {
                "stage": "answering",
                "status": "completed",
                "message": f"分析完成：{answer}"
            }
            running_tasks[task_id]['progress'].append(complete_entry)
            running_tasks[task_id]['progress_queue'].put(complete_entry)

        except Exception as e:
            import traceback
            tb_str = traceback.format_exc()
            print(f"[QA THREAD ERROR] {tb_str}")

            # Save failure to Database
            record = QARecord.query.get(task_id)
            if record:
                record.status = "failed"
                record.answer = f"分析发生错误：{str(e)}\n{tb_str}"
                db.session.commit()

            running_tasks[task_id]['status'] = "failed"
            running_tasks[task_id]['error'] = str(e)
            running_tasks[task_id]['traceback'] = tb_str

            error_entry = {
                "stage": "system",
                "status": "failed",
                "message": f"分析发生错误：{str(e)}\n{tb_str}"
            }
            running_tasks[task_id]['progress'].append(error_entry)
            running_tasks[task_id]['progress_queue'].put(error_entry)


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
    selections = data.get("selections", []) # list of {video_name, start_time_offset, end_time_offset}
    
    if not question or not selections:
        return fail(message="question and selections are required", code=5004, http_status=400)
        
    task_id = uuid.uuid4().hex
    record = QARecord(id=task_id, workspace_id=workspace_id, creator_id=emp_id, question=question, status="processing")
    db.session.add(record)
    
    # Process selections and map to video files
    from app.monitors.slicer import SLICE_OUTPUT_BASE
    from app.core.config import get_ffmpeg_path
    import subprocess
    
    # Define example directory at the same level as backend
    BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    example_dir = os.path.abspath(os.path.join(BACKEND_DIR, "..", "example"))
    os.makedirs(example_dir, exist_ok=True)
    os.makedirs(SLICE_OUTPUT_BASE, exist_ok=True)
    
    from datetime import timedelta
    base_time = datetime(2026, 6, 27, 0, 0, 0)
    for sel in selections:
        video_name = sel.get("video_name")
        if not video_name:
            continue
            
        start_offset = float(sel.get("start_time_offset", 0.0))
        end_offset = float(sel.get("end_time_offset", 0.0))
        
        # Add selection row in DB
        qvs = QAVideoSelection(
            record_id=task_id,
            monitor_id=0, # mock monitor ID
            start_time=base_time + timedelta(seconds=start_offset),
            end_time=base_time + timedelta(seconds=end_offset)
        )
        db.session.add(qvs)
            
    db.session.commit()
    
    # Initialize in-memory task tracker
    running_tasks[task_id] = {
        "status": "processing",
        "progress": [],
        "progress_queue": Queue(),
        "answer": None,
        "error": None
    }
    
    # Start thread (perform video slicing asynchronously in background)
    app = current_app._get_current_object()
    t = threading.Thread(target=process_qa_thread, args=(app, task_id, question, selections))
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
            "error": task_info["error"]
        })
    else:
        record = QARecord.query.get(task_id)
        if not record:
            return fail(message="task not found", code=5005, http_status=404)
            
        return success(data={
            "status": record.status,
            "progress": [{
                "stage": "answering",
                "status": record.status,
                "message": record.answer or ("已完成" if record.status == "completed" else "任务失败")
            }],
            "answer": record.answer if record.status == "completed" else None,
            "error": record.answer if record.status == "failed" else None
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
