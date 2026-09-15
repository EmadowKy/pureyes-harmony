"""Persistent investigation conversations for the video Agent."""

from datetime import datetime

from app.core.db import db


class AgentConversation(db.Model):
    """A thread groups follow-up questions that share the same evidence scope."""

    __tablename__ = "agent_conversations"

    id = db.Column(db.String(64), primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False, index=True)
    creator_id = db.Column(db.String(64), db.ForeignKey("users.emp_id"), nullable=False)
    title = db.Column(db.String(160), nullable=False, default="未命名调查")
    segment_ids_json = db.Column(db.Text, nullable=False, default="[]")
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, onupdate=datetime.utcnow)

    def segment_ids(self):
        import json
        try:
            values = json.loads(self.segment_ids_json or "[]")
            return [value for value in values if type(value) is int]
        except (TypeError, ValueError, json.JSONDecodeError):
            return []

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "creator_id": self.creator_id,
            "title": self.title,
            "segment_ids": self.segment_ids(),
            "created_at": self.created_at.isoformat() + "Z",
            "updated_at": self.updated_at.isoformat() + "Z",
        }
