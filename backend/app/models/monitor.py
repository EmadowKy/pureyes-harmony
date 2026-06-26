from datetime import datetime
from app.core.db import db

class Monitor(db.Model):
    __tablename__ = "monitors"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    group_id = db.Column(db.Integer, db.ForeignKey("groups.id"), nullable=False)
    name = db.Column(db.String(128), nullable=False)
    stream_url = db.Column(db.String(255), nullable=True)  # RTSP/RTMP address or local ID
    status = db.Column(db.String(20), nullable=False, default="online")
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        return {
            "id": self.id,
            "group_id": self.group_id,
            "name": self.name,
            "stream_url": self.stream_url,
            "status": self.status,
            "created_at": self.created_at.isoformat() + "Z"
        }
