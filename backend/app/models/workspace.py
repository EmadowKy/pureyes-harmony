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
    status = db.Column(db.String(32), default="pending", nullable=False)  # pending, processing, completed, failed
    progress = db.Column(db.Integer, default=0, nullable=False)            # 0 - 100
    error_msg = db.Column(db.String(512), nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "video_name": self.video_name,
            "start_offset": self.start_offset,
            "end_offset": self.end_offset,
            "duration": self.duration,
            "remark": self.remark,
            "filepath": self.filepath,
            "created_at": self.created_at.isoformat() + "Z",
            "status": self.status,
            "progress": self.progress,
            "error_msg": self.error_msg
        }
