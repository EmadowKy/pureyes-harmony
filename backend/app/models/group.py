from datetime import datetime
from app.core.db import db

class Group(db.Model):
    __tablename__ = "groups"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(128), nullable=False)
    creator_id = db.Column(db.String(64), db.ForeignKey("users.emp_id"), nullable=False)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "creator_id": self.creator_id,
            "created_at": self.created_at.isoformat() + "Z"
        }

class GroupMember(db.Model):
    __tablename__ = "group_members"

    group_id = db.Column(db.Integer, db.ForeignKey("groups.id"), primary_key=True)
    emp_id = db.Column(db.String(64), db.ForeignKey("users.emp_id"), primary_key=True)
    status = db.Column(db.String(20), nullable=False, default="pending")  # pending / accepted
    
    joined_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self):
        return {
            "group_id": self.group_id,
            "emp_id": self.emp_id,
            "status": self.status,
            "joined_at": self.joined_at.isoformat() + "Z"
        }
