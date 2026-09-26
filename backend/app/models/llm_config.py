"""Named personal and group LLM configurations; API secrets are encrypted at rest."""

from datetime import datetime
from app.core.db import db
from app.core.crypto import EncryptedText


class LLMConfig(db.Model):
    __tablename__ = "llm_configs"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(80), nullable=False)
    scope = db.Column(db.String(16), nullable=False)  # personal or group
    owner_id = db.Column(db.String(64), db.ForeignKey("users.emp_id"), nullable=True)
    group_id = db.Column(db.Integer, db.ForeignKey("groups.id"), nullable=True, index=True)
    api_key = db.Column(EncryptedText(), nullable=False)
    base_url = db.Column(db.String(255), nullable=False)
    model = db.Column(db.String(128), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def public(self, emp_id, group_creator_id=None):
        return {
            "id": self.id, "name": self.name, "scope": self.scope,
            "group_id": self.group_id, "base_url": self.base_url,
            "model": self.model, "api_key_configured": bool(self.api_key),
            "can_edit": (self.owner_id == emp_id if self.scope == "personal"
                         else group_creator_id == emp_id),
        }
