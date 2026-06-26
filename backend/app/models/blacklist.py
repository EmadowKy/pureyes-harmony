from datetime import datetime
from app.core.db import db

class TokenBlacklist(db.Model):
    __tablename__ = "token_blacklist"

    id = db.Column(db.Integer, primary_key=True)
    jti = db.Column(db.String(64), unique=True, nullable=False, index=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    @classmethod
    def add(cls, jti):
        entry = cls(jti=jti)
        db.session.add(entry)
        db.session.commit()

    @classmethod
    def is_blacklisted(cls, jti):
        return cls.query.filter_by(jti=jti).first() is not None

    @classmethod
    def cleanup_expired(cls, max_age_hours=24):
        from datetime import timedelta
        cutoff = datetime.utcnow() - timedelta(hours=max_age_hours)
        cls.query.filter(cls.created_at < cutoff).delete()
        db.session.commit()