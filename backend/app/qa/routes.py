"""QA 模块的 API 路由 - 支持异步处理"""

from flask import Blueprint, request, jsonify, send_file, Response
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from .qa_manager import QAManager
from .run_model import ask_model
import os
import json
import tempfile
import time
import threading
import uuid
import hashlib
import hmac
import secrets
from datetime import datetime
from queue import Queue

qa_bp = Blueprint('qa', __name__, url_prefix='/api/qa')

# 初始化 QA 管理器
config_path = os.path.join(os.path.dirname(__file__), "../../configs/qa_storage.yaml")
qa_manager = QAManager(config_path)

# 存储正在运行的任务（内存存储，重启后清空）
# 格式：{ task_id: { "uid": str, "username": str, "question": str, "status": str, "created_at": datetime, "progress_queue": Queue } }
running_tasks = {}

# 任务 token 映射，用于 SSE 接口验证 { task_id: access_token }
task_tokens = {}

# Token 过期时间（秒）
TOKEN_EXPIRY_SECONDS = 3600


def generate_task_token(task_id, uid):
    """为任务生成安全的访问 token"""
    token = secrets.token_urlsafe(32)
    task_tokens[task_id] = {
        'token': token,
        'uid': uid,
        'created_at': time.time()
    }
    return token


def validate_task_token(task_id, token):
    """验证任务访问 token"""
    if task_id not in task_tokens:
        return False
    token_info = task_tokens[task_id]
    if not hmac.compare_digest(token_info['token'], token):
        return False
    if time.time() - token_info['created_at'] > TOKEN_EXPIRY_SECONDS:
        del task_tokens[task_id]
        return False
    return True


def cleanup_task(task_id):
    """清理任务相关的内存数据"""
    if task_id in running_tasks:
        del running_tasks[task_id]
    if task_id in task_tokens:
        del task_tokens[task_id]


def get_current_user(request_data=None):
    """获取当前用户信息，返回 (uid, username)。

    优先使用 JWT 身份和声明，其次回退到请求数据或请求头。

    uid 如果 JWT 不存在则可能为 None。username 可能也为 None。
    """
    uid = None
    username = None

    # 优先尝试 JWT
    try:
        uid = get_jwt_identity()
        claims = get_jwt()
        username = claims.get('username')
    except Exception:
        uid = None
        username = None

    # 回退到请求体
    if not username and request_data and isinstance(request_data, dict):
        username = request_data.get('username')

    # 回退到查询参数
    if not username:
        username = request.args.get('username')

    # 回退到请求头
    if not username:
        username = request.headers.get('X-Username')

    return uid, username


def process_question_async(task_id, user_id, username, question, video_paths, config_path):
    """后台线程处理问题"""
    try:
        print(f"[QA] 任务启动: {task_id}, 用户: {username}")

        running_tasks[task_id]['progress'] = []

        def progress_callback(item):
            running_tasks[task_id].setdefault('progress', []).append(item)
            progress_queue = running_tasks[task_id].get('progress_queue')
            if progress_queue:
                progress_queue.put(item)

        result = ask_model(question, video_paths, config_path, progress_callback=progress_callback)

        answer = result.get('predicted_answer') or \
                 (result.get('answer_generation') or {}).get('raw_output') or \
                 '无回答'

        result['answer'] = answer

        if 'process_logs' not in result:
            result['process_logs'] = {}

        progress_data = running_tasks[task_id].get('progress', [])
        if progress_data and not result['process_logs'].get('progress'):
            result['process_logs']['progress'] = progress_data

        submit_time = running_tasks[task_id].get('submit_time')
        if submit_time:
            result['process_logs']['submit_time'] = submit_time

        final_record = {
            'record_id': task_id,
            'timestamp': datetime.now().isoformat(),
            'question': question,
            'video_paths': video_paths,
            'success': result.get('success', True),
            'model_result': result,
            'status': 'completed'
        }

        qa_manager.update_record(user_id, task_id, final_record)
        print(f"[QA] 任务完成: {task_id}")

        running_tasks[task_id]['status'] = 'completed'
        running_tasks[task_id]['result'] = result
        running_tasks[task_id]['completed_at'] = datetime.now().isoformat()

        cleanup_task(task_id)

    except Exception as e:
        print(f"[QA] 任务失败: {task_id}, 错误: {str(e)}")
        import traceback
        traceback.print_exc()

        error_record = {
            'success': False,
            'model_result': {
                'success': False,
                'error': str(e),
                'answer': f'处理失败：{str(e)}'
            },
            'status': 'failed'
        }
        qa_manager.update_record(user_id, task_id, error_record)

        running_tasks[task_id]['status'] = 'failed'
        running_tasks[task_id]['error'] = str(e)
        running_tasks[task_id]['completed_at'] = datetime.now().isoformat()

        cleanup_task(task_id)


@qa_bp.route('/ask', methods=['POST'])
@jwt_required()
def ask():
    """
    提问接口（异步处理）
    POST /api/qa/ask
    {
        "question": "问题内容",
        "video_paths": ["视频路径 1", "视频路径 2"],
        "username": "用户名"
    }
    返回：
    {
        "code": 200,
        "msg": "已提交处理",
        "data": {
            "task_id": "任务 ID",
            "status": "processing"
        }
    }
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({"code": 400, "msg": "请求数据为空", "data": None}), 400
        
        question = data.get('question', '').strip()
        video_paths = data.get('video_paths', [])
        
        if not question:
            return jsonify({"code": 400, "msg": "问题不能为空", "data": None}), 400
        
        if not video_paths or len(video_paths) == 0:
            return jsonify({"code": 400, "msg": "请至少选择一个视频", "data": None}), 400
        
        # 获取当前用户 uid 与 username（优先使用 JWT）
        uid, username = get_current_user(data)
        if not uid:
            return jsonify({"code":401, "msg":"未认证的用户", "data":None}), 401
        
        # 生成任务 ID
        task_id = str(uuid.uuid4())
        
        # 创建"运行中"状态的记录
        temp_record = {
            'record_id': task_id,
            'timestamp': datetime.now().isoformat(),
            'question': question,
            'video_paths': video_paths,
            'success': None,  # None 表示正在处理
            'model_result': {
                'answer': 'AI 正在分析中，请稍候...',
                'status': 'processing'
            },
            'status': 'processing'
        }
        # 先保存一个临时记录到用户的记录中（按 uid 存储，保留 username 作展示）
        qa_manager.save_temp_record(uid, temp_record, username)
        
        # 记录任务（记录提交时间作为计时基准）
        submit_time = time.time()
        running_tasks[task_id] = {
            'uid': uid,
            'username': username,
            'question': question,
            'video_paths': video_paths,
            'status': 'processing',
            'created_at': datetime.now().isoformat(),
            'submit_time': submit_time,
            'record_id': task_id,
            'progress_queue': Queue()
        }
        
        # 启动后台线程处理
        config_path = os.path.join(os.path.dirname(__file__), "../../configs/model.yaml")
        thread = threading.Thread(
            target=process_question_async,
            args=(task_id, uid, username, question, video_paths, config_path)
        )
        thread.daemon = True
        thread.start()

        access_token = generate_task_token(task_id, uid)

        return jsonify({
            "code": 200,
            "msg": "问题已提交，正在处理中",
            "data": {
                "task_id": task_id,
                "task_token": access_token,
                "status": "processing",
                "record_id": task_id
            }
        })
        
    except Exception as e:
        return jsonify({
            "code": 500,
            "msg": f"服务器错误：{str(e)}",
            "data": None
        }), 500


@qa_bp.route('/task/<task_id>/status', methods=['GET'])
@jwt_required()
def get_task_status(task_id):
    """
    获取任务状态
    GET /api/qa/task/{task_id}/status
    """
    try:
        uid, username = get_current_user()
        if not uid:
            return jsonify({"code":401, "msg":"未认证的用户", "data":None}), 401
        records = qa_manager.get_user_records(uid)
        record = next((r for r in records if r.get('record_id') == task_id), None)
        
        if not record:
            return jsonify({
                "code": 404,
                "msg": "任务不存在",
                "data": None
            }), 404
        
        # 合并运行时进度（如果存在）
        progress = running_tasks.get(task_id, {}).get('progress')
        if progress:
            # 保留原有的 initialization、iterations 等数据，只更新 progress
            existing_process_logs = record.get('model_result', {}).get('process_logs', {})
            if 'model_result' not in record:
                record['model_result'] = {}
            record['model_result']['process_logs'] = {
                **existing_process_logs,
                'progress': progress
            }
        
        return jsonify({
            "code": 200,
            "msg": "获取成功",
            "data": {
                "status": record.get('status', 'completed'),
                "record": record,
                "progress": progress or record.get('model_result', {}).get('process_logs', {}).get('progress', [])
            }
        })
        
    except Exception as e:
        return jsonify({
            "code": 500,
            "msg": f"服务器错误：{str(e)}",
            "data": None
        }), 500


@qa_bp.route('/records', methods=['GET'])
@jwt_required()
def get_records():
    """
    获取用户的问答记录列表
    GET /api/qa/records?page=1&limit=10
    """
    try:
        page = int(request.args.get('page', 1))
        limit = int(request.args.get('limit', 10))
        
        uid, username = get_current_user()
        if not uid:
            return jsonify({"code":401, "msg":"未认证的用户", "data":None}), 401

        # 直接从存储中获取所有记录（包括正在处理的记录）
        all_records = qa_manager.get_user_records(uid)
        
        # 分页
        total = len(all_records)
        start = (page - 1) * limit
        end = start + limit
        records = all_records[start:end]
        
        return jsonify({
            "code": 200,
            "msg": "获取成功",
            "data": {
                "records": records,
                "total": total,
                "page": page,
                "limit": limit
            }
        })
        
    except Exception as e:
        return jsonify({
            "code": 500,
            "msg": f"服务器错误：{str(e)}",
            "data": None
        }), 500


@qa_bp.route('/record/<record_id>', methods=['GET'])
@jwt_required()
def get_record(record_id):
    """
    获取单条问答记录详情
    GET /api/qa/record/{record_id}
    """
    try:
        uid, username = get_current_user()
        if not uid:
            return jsonify({"code":401, "msg":"未认证的用户", "data":None}), 401
        
        # 从记录中查找
        records = qa_manager.get_user_records(uid)
        record = next((r for r in records if r.get('record_id') == record_id), None)
        
        if not record:
            return jsonify({
                "code": 404,
                "msg": "记录不存在",
                "data": None
            }), 404

        return jsonify({
            "code": 200,
            "msg": "获取成功",
            "data": record
        })

    except Exception as e:
        return jsonify({
            "code": 500,
            "msg": f"服务器错误：{str(e)}",
            "data": None
        }), 500


@qa_bp.route('/record/<record_id>', methods=['DELETE'])
@jwt_required()
def delete_record(record_id):
    """
    删除问答记录
    DELETE /api/qa/record/{record_id}
    """
    try:
        uid, username = get_current_user()
        if not uid:
            return jsonify({"code":401, "msg":"未认证的用户", "data":None}), 401

        success = qa_manager.delete_record(uid, record_id)
        
        if success:
            return jsonify({
                "code": 200,
                "msg": "删除成功",
                "data": None
            })
        else:
            return jsonify({
                "code": 404,
                "msg": "记录不存在或删除失败",
                "data": None
            }), 404
        
    except Exception as e:
        return jsonify({
            "code": 500,
            "msg": f"服务器错误：{str(e)}",
            "data": None
        }), 500


@qa_bp.route('/summary', methods=['GET'])
@jwt_required()
def get_summary():
    """
    获取统计摘要
    GET /api/qa/summary
    """
    try:
        uid, username = get_current_user()
        if not uid:
            return jsonify({"code":401, "msg":"未认证的用户", "data":None}), 401
        summary = qa_manager.get_record_summary(uid)
        
        return jsonify({
            "code": 200,
            "msg": "获取成功",
            "data": summary
        })
        
    except Exception as e:
        return jsonify({
            "code": 500,
            "msg": f"服务器错误：{str(e)}",
            "data": None
        }), 500


@qa_bp.route('/export', methods=['GET'])
@jwt_required()
def export_records():
    """
    导出问答记录
    GET /api/qa/export?format=json
    """
    try:
        format_type = request.args.get('format', 'json').lower()
        uid, username = get_current_user()
        if not uid:
            return jsonify({"code":401, "msg":"未认证的用户", "data":None}), 401

        records = qa_manager.get_user_records(uid)

        if not records:
            return jsonify({
                "code": 404,
                "msg": "当前用户暂无可导出的记录",
                "data": None
            }), 404
        
        if format_type == 'json':
            temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
            try:
                json.dump(records, temp_file, ensure_ascii=False, indent=2)
                temp_file.close()

                return send_file(
                    temp_file.name,
                    mimetype='application/json',
                    as_attachment=True,
                    download_name=f'qa_records_{username}_{int(time.time())}.json'
                )
            finally:
                if os.path.exists(temp_file.name):
                    os.remove(temp_file.name)
        else:
            return jsonify({
                "code": 400,
                "msg": f"不支持的导出格式：{format_type}",
                "data": None
            }), 400
        
    except Exception as e:
        import traceback
        traceback.print_exc()

        return jsonify({
            "code": 500,
            "msg": f"服务器错误：{str(e)}",
            "data": None
        }), 500


@qa_bp.route('/task/<task_id>/progress', methods=['GET'])
@jwt_required()
def get_task_progress(task_id):
    """获取任务实时进度"""
    try:
        uid, username = get_current_user()
        if not uid:
            return jsonify({"code":401, "msg":"未认证的用户", "data":None}), 401

        task = running_tasks.get(task_id)
        if not task:
            return jsonify({"code":404, "msg":"任务不存在", "data":None}), 404

        return jsonify({
            "code":200,
            "msg":"获取成功",
            "data":{
                "task_id": task_id,
                "status": task.get('status', 'processing'),
                "progress": task.get('progress', [])
            }
        })

    except Exception as e:
        return jsonify({"code":500, "msg": f"服务器错误：{str(e)}", "data":None}), 500


@qa_bp.route('/task/<task_id>/stream', methods=['GET'])
def stream_task_progress(task_id):
    """SSE 流式推送任务进度（使用 access_token 或 task_token 验证）"""
    try:
        token = request.args.get('token')

        if not token:
            return jsonify({"error": "缺少 token"}), 401

        if not validate_task_token(task_id, token):
            return jsonify({"error": "无效或过期的 token"}), 401

        task = running_tasks.get(task_id)
        if not task:
            return jsonify({"error": "任务不存在"}), 404

        def generate():
            progress_queue = task.get('progress_queue')

            submit_time = task.get('submit_time', time.time())
            yield f"data: {json.dumps({'type': 'connected', 'task_id': task_id, 'submit_time': submit_time})}\n\n"

            while True:
                while progress_queue and not progress_queue.empty():
                    try:
                        item = progress_queue.get_nowait()
                        yield f"data: {json.dumps({'type': 'progress', 'data': item})}\n\n"
                    except:
                        break

                if task.get('status') in ['completed', 'failed']:
                    yield f"data: {json.dumps({'type': 'complete', 'status': task.get('status'), 'result': task.get('result')})}\n\n"
                    break

                time.sleep(0.1)

        return Response(generate(), mimetype='text/event-stream', headers={
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'Content-Type': 'text/event-stream; charset=utf-8',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Credentials': 'true'
        })

    except Exception as e:
        print(f"SSE stream error: {e}")
        return jsonify({"error": f"服务器错误：{str(e)}"}), 500
