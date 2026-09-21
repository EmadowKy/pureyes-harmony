from datetime import datetime
from app.core.db import db

class Monitor(db.Model):
    __tablename__ = "monitors"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    group_id = db.Column(db.Integer, db.ForeignKey("groups.id"), nullable=False)
    name = db.Column(db.String(128), nullable=False)
    stream_url = db.Column(db.String(255), nullable=True)  # RTSP/RTMP address or local ID
    cover_path = db.Column(db.String(255), nullable=True)
    cover_updated_at = db.Column(db.DateTime, nullable=True)
    status = db.Column(db.String(20), nullable=False, default="online")
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self, include_stream_url=False, can_manage=False):
        from app.core.media_auth import build_media_url, monitor_scope, path_scope
        scope = monitor_scope(self.id)
        raw_stream_url = (self.stream_url or "").strip()
        is_backend_path = raw_stream_url and not raw_stream_url.lower().startswith((
            "rtsp://", "rtmp://", "http://", "https://"
        ))
        return {
            "id": self.id,
            "group_id": self.group_id,
            "name": self.name,
            # Stream credentials are infrastructure configuration, not monitor
            # metadata. Group members receive the signed live URL instead.
            "stream_url": self.stream_url if include_stream_url else "",
            "source_configured": bool(raw_stream_url),
            "can_manage": bool(can_manage),
            "cover_url": build_media_url(f"/api/monitors/{self.id}/cover", scope) if self.cover_path else "",
            "live_url": build_media_url(f"/api/video/live/{self.id}/index.m3u8", scope) if self.stream_url else "",
            "media_url": build_media_url(
                f"/api/video/{raw_stream_url}",
                path_scope(raw_stream_url),
            ) if is_backend_path else "",
            "cover_updated_at": self.cover_updated_at.isoformat() + "Z" if self.cover_updated_at else "",
            "status": self.status,
            "created_at": self.created_at.isoformat() + "Z"
        }
