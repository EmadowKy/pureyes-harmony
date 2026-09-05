from datetime import datetime
from app.core.db import db

class WorkspaceFaceGroup(db.Model):
    __tablename__ = 'workspace_face_groups'

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey('workspaces.id'), nullable=False)
    name = db.Column(db.String(100), nullable=False, default='未命名人脸')
    avatar_path = db.Column(db.String(255), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # 关联
    records = db.relationship('WorkspaceFaceRecord', backref='group', lazy=True, cascade='all, delete-orphan')

    def to_dict(self):
        from app.core.media_auth import build_media_url, path_scope
        return {
            'id': self.id,
            'workspace_id': self.workspace_id,
            'name': self.name,
            'avatar_path': self.avatar_path,
            'avatar_url': build_media_url(
                f"/api/video/{self.avatar_path}",
                path_scope(self.avatar_path),
            ) if self.avatar_path else "",
            'record_count': len(self.records),
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else ''
        }

class WorkspaceFaceRecord(db.Model):
    __tablename__ = 'workspace_face_records'

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey('workspaces.id'), nullable=False)
    group_id = db.Column(db.Integer, db.ForeignKey('workspace_face_groups.id'), nullable=False)
    segment_id = db.Column(db.Integer, db.ForeignKey('workspace_video_segments.id'), nullable=True)
    
    crop_path = db.Column(db.String(255), nullable=False)
    video_name = db.Column(db.String(255), nullable=False, default='')
    start_time_offset = db.Column(db.Float, nullable=False, default=0.0)
    end_time_offset = db.Column(db.Float, nullable=False, default=0.0)
    start_time_str = db.Column(db.String(50), nullable=False, default='00:00')
    end_time_str = db.Column(db.String(50), nullable=False, default='00:00')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        from app.core.media_auth import build_media_url, path_scope
        # 获取关联 segment 的真实 relative filepath，供点击跳转播放
        seg_filepath = ""
        if self.segment_id:
            from app.models.workspace import WorkspaceVideoSegment
            seg = db.session.get(WorkspaceVideoSegment, self.segment_id)
            if seg:
                seg_filepath = seg.filepath

        return {
            'id': self.id,
            'workspace_id': self.workspace_id,
            'group_id': self.group_id,
            'segment_id': self.segment_id,
            'segment_filepath': seg_filepath,
            'segment_media_url': build_media_url(
                f"/api/video/{seg_filepath}",
                path_scope(seg_filepath),
            ) if seg_filepath else "",
            'crop_path': self.crop_path,
            'crop_url': build_media_url(
                f"/api/video/{self.crop_path}",
                path_scope(self.crop_path),
            ) if self.crop_path else "",
            'video_name': self.video_name,
            'start_time_offset': self.start_time_offset,
            'end_time_offset': self.end_time_offset,
            'time_range_str': f"{self.start_time_str} - {self.end_time_str}",
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else ''
        }
