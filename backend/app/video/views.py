import os
import uuid
import cv2
import yaml
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity, get_jwt
from datetime import datetime

from app.core.db import db
from app.core.config import Config
from app.core.response import success, fail
from app.models.user import User

class Video(db.Model):
    __tablename__ = "video"
    video_id = db.Column(db.String(32), primary_key = True)
    uid = db.Column(db.String(32))
    video_name = db.Column(db.String, nullable = False)
    video_path = db.Column(db.String)
    upload_time = db.Column(db.DateTime, default = datetime.now)
    duration = db.Column(db.Float, default = 0.0)  # 视频时长，单位秒
    file_size = db.Column(db.BigInteger, default = 0)  # 视频文件大小，单位字节
    is_ticked = db.Column(db.Boolean, default = False)
    
    def to_dict(self):
        # 将时长转换为分:秒格式
        minutes = int(self.duration // 60)
        seconds = int(self.duration % 60)
        duration_str = f"{minutes:02d}:{seconds:02d}"
        # 从 video_id 动态构建相对路径，不依赖数据库的 video_path 字段
        relative_video_path = f"uploads/{self.video_id}.mp4"
        return {
            "video_id": self.video_id,
            "uid": self.uid,
            "video_name": self.video_name,
            "video_path": relative_video_path,
            "duration": duration_str,
            "file_size": self.file_size  # 返回文件大小
        }

# 视频存储路径
VIDEO_PATH = Config.VIDEO_UPLOAD_PATH
os.makedirs(VIDEO_PATH, exist_ok = True)

# 加载视频配置
def load_video_config():
    """加载视频上传限制配置"""
    config_path = os.path.join(os.path.dirname(Config.VIDEO_UPLOAD_PATH), 'configs', 'qa_storage.yaml')
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
            video_config = config.get('video', {})
            return {
                'max_single_video_size': video_config.get('max_single_video_size', 524288000),  # 默认500MB
                'max_storage_per_user': video_config.get('max_storage_per_user', 2147483648),  # 默认2GB
                'max_videos_per_user': video_config.get('max_videos_per_user', 30)  # 默认30个
            }
    except Exception as e:
        print(f"加载视频配置失败: {str(e)}")
        # 返回默认配置
        return {
            'max_single_video_size': 524288000,
            'max_storage_per_user': 2147483648,
            'max_videos_per_user': 30
        }

VIDEO_CONFIG = load_video_config()



# 上传视频
@jwt_required()
def upload_video():
    # 从 JWT 获取 uid（identity）与 username（claims）
    uid = get_jwt_identity()
    claims = get_jwt()
    username = claims.get("username")

    video_name = request.form.get("video_name")
    video_file = request.files.get("video_file")

    if not uid:
        return fail(message="token无效或已过期", code=401)
    if not video_name:
        return fail(message="缺少视频名称", code=400)
    if not video_file:
        return fail(message="缺少视频文件", code=400)

    try:
        user = User.query.filter_by(id=int(uid)).first()
        if not user:
            return fail(message="用户不存在", code=404)

        video_file.seek(0, 2)
        file_size = video_file.tell()
        video_file.seek(0)

        if file_size > VIDEO_CONFIG['max_single_video_size']:
            max_size_mb = VIDEO_CONFIG['max_single_video_size'] / (1024 * 1024)
            current_size_mb = file_size / (1024 * 1024)
            return fail(
                message=f"视频文件过大。最大允许大小: {max_size_mb:.0f}MB，当前大小: {current_size_mb:.2f}MB",
                code=400
            )
        
        # 【验证2】检查用户视频数量限制
        video_count = Video.query.filter_by(uid=uid).count()
        if video_count >= VIDEO_CONFIG['max_videos_per_user']:
            return fail(
                message=f"您已达到上传数量限制（{VIDEO_CONFIG['max_videos_per_user']}个）。请删除部分视频后再试。",
                code=400
            )
        
        # 【验证3】检查用户总存储限制
        if user.total_video_size + file_size > VIDEO_CONFIG['max_storage_per_user']:
            max_storage_gb = VIDEO_CONFIG['max_storage_per_user'] / (1024 * 1024 * 1024)
            current_usage_gb = user.total_video_size / (1024 * 1024 * 1024)
            remaining_gb = (VIDEO_CONFIG['max_storage_per_user'] - user.total_video_size) / (1024 * 1024 * 1024)
            return fail(
                message=f"存储空间不足。总限制: {max_storage_gb:.2f}GB，已用: {current_usage_gb:.2f}GB，剩余: {remaining_gb:.2f}GB，无法上传 {file_size / (1024 * 1024):.2f}MB 的视频",
                code=400
            )
        
        video_id = str(uuid.uuid4()).replace("-", "")[:32]
        video_filename = f"{video_id}.mp4" 
        full_video_path = os.path.join(VIDEO_PATH, video_filename)

        # 保存视频到服务器
        video_file.save(full_video_path)

        # 计算视频时长
        def get_video_duration(video_path):
            try:
                cap = cv2.VideoCapture(video_path)
                if not cap.isOpened():
                    return 0.0
                fps = cap.get(cv2.CAP_PROP_FPS)
                frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
                duration = frame_count / fps if fps > 0 else 0.0
                cap.release()
                return duration
            except Exception as e:
                print(f"计算视频时长失败: {str(e)}")
                return 0.0

        duration = get_video_duration(full_video_path)

        # 写入数据库
        video = Video(
            video_id = video_id,
            uid = uid,
            video_name = video_name,
            duration = duration,
            file_size = file_size
        )
        
        # 更新用户统计信息
        user.total_video_size += file_size
        user.video_count += 1
        
        db.session.add(video)
        db.session.commit()
        return success(data = video.to_dict(), message="视频上传成功")
    except Exception as e:
        db.session.rollback()
        return fail(message=f"视频上传失败：{str(e)}", code=500)

# 删除视频
@jwt_required()
def delete_video():
    data = request.get_json() or {}
    video_id = data.get("video_id")

    uid = get_jwt_identity()
    if not uid:
        return fail(message="token无效或已过期", code=401)
    if not video_id:
        return fail(message="缺少视频ID", code=400)
    
    try:
        video = Video.query.filter_by(video_id = video_id, uid = uid).first()
        if not video:
            return fail(message="视频不存在", code=404)
        
        absolute_video_path = os.path.join(VIDEO_PATH, f"{video_id}.mp4")
        
        if os.path.exists(absolute_video_path):
            try:
                os.remove(absolute_video_path)
            except Exception as file_e:
                return fail(message=f"视频文件删除失败：{str(file_e)}", code=500)
        
        # 获取用户并更新统计信息
        user = User.query.filter_by(id=int(uid)).first()
        if user:
            user.total_video_size = max(0, user.total_video_size - video.file_size)
            user.video_count = max(0, user.video_count - 1)
        
        # 删除数据库记录
        db.session.delete(video)
        db.session.commit() 
        return success(message="视频删除成功")
    except Exception as e:
        db.session.rollback() 
        return fail(message=f"视频删除失败：{str(e)}", code=500)

# 重命名视频
@jwt_required()
def rename_video():
    data = request.get_json() or {}
    video_id = data.get("video_id")
    new_name = data.get("new_name")

    uid = get_jwt_identity()
    if not uid:
        return fail(message="token无效或已过期", code=401)
    if not video_id:
        return fail(message="缺少视频ID", code=400)
    if not new_name:
        return fail(message="缺少新视频名称", code=400)

    try:
        video = Video.query.filter_by(video_id = video_id, uid = uid).first()
        if not video:
            return fail(message="视频不存在", code=404)

        absolute_video_path = os.path.join(VIDEO_PATH, f"{video_id}.mp4")

        if not os.path.exists(absolute_video_path):
            return fail(message="视频文件不存在", code=404)

        video.video_name = new_name
        db.session.commit()

        return success(
            data = {
                "video_id": video.video_id,
                "uid": video.uid,
                "video_name": video.video_name,
                "video_path": f"uploads/{video.video_id}.mp4",
                "duration": f"{int(video.duration // 60):02d}:{int(video.duration % 60):02d}"
            },
            message="视频重命名成功"
        )
    except Exception as e:
        db.session.rollback()
        return fail(message=f"视频重命名失败：{str(e)}", code=500)

# 勾选视频
@jwt_required()
def tick_video():
    data = request.get_json() or {}
    video_ids = data.get("video_ids", []) # 勾选视频的ID列表
    is_ticked = data.get("is_ticked")
    if not isinstance(video_ids, list) or not video_ids:
        return fail(message="视频ID列表不能为空", code=400)

    uid = get_jwt_identity()
    if not uid:
        return fail(message="token无效或已过期", code=401)
    
    try:
        Video.query.filter(
            Video.video_id.in_(video_ids), 
            Video.uid == uid
        ).update({"is_ticked": is_ticked}) 
        db.session.commit()
        message = "视频勾选成功" if is_ticked else "视频取消勾选成功"
        return success(message=message)
    except Exception as e:
        db.session.rollback()
        return fail(message=f"视频勾选失败：{str(e)}", code=500)

# 查看所有视频的列表
@jwt_required()
def get_video_list():
    """
    获取用户的视频列表
    直接从数据库取元数据（video_name, upload_time等），
    路径采用统一格式：uploads/{video_id}.mp4
    """
    uid = get_jwt_identity()
    if not uid:
        return fail(message="token无效或已过期", code=401)

    try:
        videos = Video.query.filter_by(uid = uid).order_by(Video.upload_time.desc()).all()
        
        video_list = []
        for video in videos:
            relative_video_path = f"uploads/{video.video_id}.mp4"
            
            video_list.append({
                "video_id": video.video_id,
                "uid": video.uid,
                "video_name": video.video_name,
                "video_path": relative_video_path,
                "duration": f"{int(video.duration // 60):02d}:{int(video.duration % 60):02d}",
                "file_size": video.file_size,
                "upload_time": video.upload_time.isoformat() if video.upload_time else None
            })
        
        total = len(video_list)
        return success(
            data = {
                "videos": video_list,
                "total": total
            },
            message="获取视频列表成功"
        )
    except Exception as e:
        return fail(message=f"获取视频列表失败：{str(e)}", code=500)

# 查看单个视频
@jwt_required()
def get_single_video():
    uid = get_jwt_identity()
    video_id = request.args.get("video_id")
    if not uid:
        return fail(message="token无效或已过期", code=401)
    if not video_id:
        return fail(message="缺少视频ID", code=400)

    try:
        video = Video.query.filter_by(video_id = video_id, uid = uid).first()
        if not video:
            return fail(message="视频不存在", code=404)
        return success(data = video.to_dict(), message="获取视频信息成功")
    except Exception as e:
        return fail(message=f"获取视频信息失败：{str(e)}", code=500)