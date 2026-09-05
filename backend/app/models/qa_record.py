from datetime import datetime
from app.core.db import db

class QARecord(db.Model):
    __tablename__ = "qa_records"

    id = db.Column(db.String(64), primary_key=True)  # task_id as UUID
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    creator_id = db.Column(db.String(64), db.ForeignKey("users.emp_id"), nullable=False)
    
    question = db.Column(db.Text, nullable=False)
    answer = db.Column(db.Text, nullable=True)
    status = db.Column(db.String(20), nullable=False, default="processing")  # processing, completed, failed
    progress_json = db.Column(db.Text, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "creator_id": self.creator_id,
            "question": self.question,
            "answer": self.answer,
            "status": self.status,
            "progress_json": self.progress_json,
            "created_at": self.created_at.isoformat() + "Z"
        }

class QAVideoSelection(db.Model):
    __tablename__ = "qa_video_selections"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    record_id = db.Column(db.String(64), db.ForeignKey("qa_records.id"), nullable=False)
    monitor_id = db.Column(db.Integer, db.ForeignKey("monitors.id"), nullable=False)
    segment_id = db.Column(db.Integer, db.ForeignKey("workspace_video_segments.id"), nullable=True)
    
    start_time = db.Column(db.DateTime, nullable=False)
    end_time = db.Column(db.DateTime, nullable=False)

    def to_dict(self):
        return {
            "id": self.id,
            "record_id": self.record_id,
            "monitor_id": self.monitor_id,
            "segment_id": self.segment_id,
            "start_time": self.start_time.isoformat() + "Z",
            "end_time": self.end_time.isoformat() + "Z"
        }
