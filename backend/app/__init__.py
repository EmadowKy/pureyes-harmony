from flask import Flask
import os
import secrets
from .core.db import db
from .extensions import jwt, cors
from .core.config import Config

def _ensure_monitor_schema():
    """Keep existing sqlite databases compatible with added monitor columns."""
    try:
        from sqlalchemy import inspect, text
        inspector = inspect(db.engine)
        columns = {column["name"] for column in inspector.get_columns("monitors")}
        additions = []
        if "cover_path" not in columns:
            additions.append("ALTER TABLE monitors ADD COLUMN cover_path VARCHAR(255)")
        if "cover_updated_at" not in columns:
            additions.append("ALTER TABLE monitors ADD COLUMN cover_updated_at DATETIME")
        if additions:
            with db.engine.begin() as conn:
                for statement in additions:
                    conn.execute(text(statement))
    except Exception as exc:
        print(f"[DB] monitor schema check skipped: {exc}")


def _ensure_user_schema():
    """Keep existing sqlite databases compatible with token revocation metadata."""
    try:
        from sqlalchemy import inspect, text
        inspector = inspect(db.engine)
        columns = {column["name"] for column in inspector.get_columns("users")}
        with db.engine.begin() as conn:
            if "auth_version" not in columns:
                conn.execute(text(
                    "ALTER TABLE users ADD COLUMN auth_version INTEGER NOT NULL DEFAULT 0"
                ))
            else:
                conn.execute(text("UPDATE users SET auth_version = 0 WHERE auth_version IS NULL"))
    except Exception as exc:
        print(f"[DB] user schema check skipped: {exc}")


def _ensure_qa_selection_schema():
    """Add direct segment references while preserving existing QA history."""
    try:
        from sqlalchemy import inspect, text
        inspector = inspect(db.engine)
        columns = {column["name"] for column in inspector.get_columns("qa_video_selections")}
        if "segment_id" not in columns:
            with db.engine.begin() as conn:
                conn.execute(text(
                    "ALTER TABLE qa_video_selections ADD COLUMN segment_id INTEGER"
                ))
    except Exception as exc:
        print(f"[DB] QA selection schema check skipped: {exc}")


def _encrypt_legacy_api_keys():
    """Encrypt API keys written by versions that stored them as plain text."""
    try:
        from sqlalchemy import text
        from sqlalchemy.orm.attributes import flag_modified
        from app.models.user import User

        raw_rows = db.session.execute(text(
            "SELECT emp_id, llm_api_key FROM users WHERE llm_api_key IS NOT NULL AND llm_api_key != ''"
        )).all()
        changed = False
        for emp_id, stored_value in raw_rows:
            if str(stored_value).startswith("enc:v1:"):
                continue
            user = db.session.get(User, emp_id)
            if user:
                user.llm_api_key = stored_value
                flag_modified(user, "llm_api_key")
                changed = True
        if changed:
            db.session.commit()
    except Exception as exc:
        db.session.rollback()
        print(f"[DB] API key encryption migration skipped: {exc}")

def create_app():
    app = Flask(__name__)

    app.config.from_object(Config)

    db.init_app(app)
    jwt.init_app(app)
    cors.init_app(app, resources={r"/api/*": {"origins": "*"}, "/*": {"origins": "*"}})

    @jwt.token_in_blocklist_loader
    def check_if_token_in_blacklist(jwt_header, jwt_payload):
        from app.models.blacklist import TokenBlacklist
        from app.models.user import User
        jti = jwt_payload["jti"]
        if TokenBlacklist.is_blacklisted(jti):
            return True
        user = db.session.get(User, jwt_payload.get("sub"))
        if not user or not user.is_active:
            return True
        return jwt_payload.get("auth_version") != (user.auth_version or 0)

    from app.auth import auth_bp
    app.register_blueprint(auth_bp, url_prefix="/api/auth")

    from app.users import users_bp
    app.register_blueprint(users_bp, url_prefix="/api/users")

    from app.groups import groups_bp
    app.register_blueprint(groups_bp, url_prefix="/api/groups")

    from app.monitors import monitors_bp
    app.register_blueprint(monitors_bp, url_prefix="/api/monitors")

    from app.workspaces import workspaces_bp
    app.register_blueprint(workspaces_bp, url_prefix="/api/workspaces")

    from app.video_stream_routes import video_stream_bp
    app.register_blueprint(video_stream_bp)

    @app.get("/api/health")
    def health():
        return {"code": 0, "message": "ok", "data": {"service": "backend"}}, 200

    with app.app_context():
        from app import models  # Use from import to avoid shadowing local `app` variable
        db.create_all()
        _ensure_monitor_schema()
        _ensure_user_schema()
        _ensure_qa_selection_schema()
        _encrypt_legacy_api_keys()
        from app.models.blacklist import TokenBlacklist
        TokenBlacklist.cleanup_expired(max_age_hours=25)

        # Inject super_admin
        from app.models.user import User
        if not User.query.filter_by(emp_id="admin").first():
            bootstrap_password = os.environ.get("PUREYES_BOOTSTRAP_ADMIN_PASSWORD")
            generated_password = False
            if not bootstrap_password:
                bootstrap_password = secrets.token_urlsafe(18)
                generated_password = True
            super_admin = User(
                emp_id="admin",
                name="Super Admin",
                role="super_admin"
            )
            super_admin.set_password(bootstrap_password)
            db.session.add(super_admin)
            db.session.commit()
            if generated_password:
                print(f"Super Admin created. One-time password: {bootstrap_password}")
            else:
                print("Super Admin created from PUREYES_BOOTSTRAP_ADMIN_PASSWORD.")

        # Start background stream recording service
        from app.core.recorder import start_all_recordings
        from app.monitors.routes import start_cover_refresh_loop
        if os.environ.get("PUREYES_DISABLE_BACKGROUND") != "1":
            start_all_recordings(app)
            start_cover_refresh_loop(app)

    return app
