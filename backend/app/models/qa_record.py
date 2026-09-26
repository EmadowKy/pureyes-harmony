from datetime import datetime
from app.core.db import db

class QARecord(db.Model):
    __tablename__ = "qa_records"
    __table_args__ = (
        db.Index(
            "uq_qa_active_conversation", "conversation_id", unique=True,
            sqlite_where=db.text("status = 'processing' AND conversation_id IS NOT NULL"),
            postgresql_where=db.text("status = 'processing' AND conversation_id IS NOT NULL"),
        ),
    )

    id = db.Column(db.String(64), primary_key=True)  # task_id as UUID
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    creator_id = db.Column(db.String(64), db.ForeignKey("users.emp_id"), nullable=False)
    
    question = db.Column(db.Text, nullable=False)
    answer = db.Column(db.Text, nullable=True)
    status = db.Column(db.String(20), nullable=False, default="processing")  # processing, completed, failed, stopped
    progress_json = db.Column(db.Text, nullable=True)
    heartbeat_at = db.Column(db.DateTime, nullable=True)
    model_config_label = db.Column(db.String(120), nullable=True)
    # New fields are nullable to preserve every historical one-shot record.
    conversation_id = db.Column(db.String(64), db.ForeignKey("agent_conversations.id"), nullable=True, index=True)
    turn_index = db.Column(db.Integer, nullable=False, default=1)
    
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
            "conversation_id": self.conversation_id,
            "turn_index": self.turn_index,
            "model_config_label": self.model_config_label,
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
