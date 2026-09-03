from datetime import datetime
from app.core.db import db

class Workspace(db.Model):
    __tablename__ = "workspaces"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    group_id = db.Column(db.Integer, db.ForeignKey("groups.id"), nullable=False)
    name = db.Column(db.String(128), nullable=False)
    creator_id = db.Column(db.String(64), db.ForeignKey("users.emp_id"), nullable=False)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        return {
            "id": self.id,
            "group_id": self.group_id,
            "name": self.name,
            "creator_id": self.creator_id,
            "created_at": self.created_at.isoformat() + "Z"
        }

class WorkspaceVideoSegment(db.Model):
    __tablename__ = "workspace_video_segments"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    video_name = db.Column(db.String(128), nullable=False)
    start_offset = db.Column(db.Float, nullable=False)
    end_offset = db.Column(db.Float, nullable=False)
    duration = db.Column(db.Float, nullable=False)
    remark = db.Column(db.String(256), nullable=True)
    filepath = db.Column(db.String(256), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    
    # 新增特征提取状态与进度字段
    status = db.Column(db.String(32), default="pending", nullable=False)  # pending, processing, completed, failed, none
    progress = db.Column(db.Integer, default=0, nullable=False)            # 0 - 100
    error_msg = db.Column(db.String(512), nullable=True)
    sample_fps = db.Column(db.Float, default=1.0, nullable=True)
    resolution = db.Column(db.String(32), default="1080P", nullable=True)
    orig_resolution = db.Column(db.String(32), default="1080P", nullable=True)

    def to_dict(self):
        from app.core.media_auth import build_media_url, path_scope
        media_path = f"/api/video/{self.filepath}"
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "video_name": self.video_name,
            "start_offset": self.start_offset,
            "end_offset": self.end_offset,
            "duration": self.duration,
            "remark": self.remark,
            "filepath": self.filepath,
            "media_url": build_media_url(media_path, path_scope(self.filepath)),
            "thumbnail_url": build_media_url(
                f"/api/video/thumbnail/{self.filepath}",
                path_scope(self.filepath),
            ),
            "created_at": self.created_at.isoformat() + "Z",
            "status": self.status,
            "progress": self.progress,
            "error_msg": self.error_msg,
            "sample_fps": self.sample_fps if self.sample_fps is not None else 1.0,
            "resolution": self.resolution or "1080P",
            "orig_resolution": self.orig_resolution or "1080P"
        }
