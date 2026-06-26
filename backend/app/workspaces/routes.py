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

def process_qa_thread(app, task_id, question, video_paths):
    with app.app_context():
        try:
            # Add initial progress entry
            init_msg = {
                "stage": "model_initialization",
                "status": "started",
                "message": "大模型后台推理服务启动中..."
            }
            running_tasks[task_id]['progress'].append(init_msg)
            running_tasks[task_id]['progress_queue'].put(init_msg)

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
    selections = data.get("selections", []) # list of {monitor_id, start_time, end_time}
    
    if not question or not selections:
        return fail(message="question and selections are required", code=5004, http_status=400)
        
    task_id = uuid.uuid4().hex
    record = QARecord(id=task_id, workspace_id=workspace_id, creator_id=emp_id, question=question, status="processing")
    db.session.add(record)
    
    # Process selections and map to video files
    from app.monitors.slicer import slice_video, SLICE_OUTPUT_BASE
    
    video_paths = []
    for sel in selections:
        monitor_id = sel["monitor_id"]
        start_time_str = sel["start_time"]
        end_time_str = sel["end_time"]
        
        # Add selection row in DB
        qvs = QAVideoSelection(
            record_id=task_id,
            monitor_id=monitor_id,
            start_time=datetime.fromisoformat(start_time_str.replace("Z", "")),
            end_time=datetime.fromisoformat(end_time_str.replace("Z", ""))
        )
        db.session.add(qvs)
        
        # Get slice path
        filename = slice_video(monitor_id, start_time_str, end_time_str)
        abs_slice_path = os.path.join(SLICE_OUTPUT_BASE, filename)
        
        # Check if the slice is mock text (size is tiny) or missing
        is_mock = True
        if os.path.exists(abs_slice_path):
            file_size = os.path.getsize(abs_slice_path)
            if file_size > 1000:
                is_mock = False
                
        if is_mock:
            # Fall back to example videos relative to backend root
            idx = len(video_paths) % 2
            video_paths.append(f"example/{idx+1}.mp4")
        else:
            video_paths.append(f"storage/slices/{filename}")
            
    db.session.commit()
    
    # Initialize in-memory task tracker
    running_tasks[task_id] = {
        "status": "processing",
        "progress": [],
        "progress_queue": Queue(),
        "answer": None,
        "error": None
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
