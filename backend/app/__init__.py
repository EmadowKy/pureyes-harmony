from flask import Flask
import os
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

def create_app():
    app = Flask(__name__)

    app.config.from_object(Config)

    db.init_app(app)
    jwt.init_app(app)
    cors.init_app(app, resources={r"/api/*": {"origins": "*"}, "/*": {"origins": "*"}})

    @jwt.token_in_blocklist_loader
    def check_if_token_in_blacklist(jwt_header, jwt_payload):
        from app.models.blacklist import TokenBlacklist
        jti = jwt_payload["jti"]
        return TokenBlacklist.is_blacklisted(jti)

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

    from app.video.routes import video_bp as video_manage_bp
    app.register_blueprint(video_manage_bp)

    @app.get("/api/health")
    def health():
        return {"code": 0, "message": "ok", "data": {"service": "backend"}}, 200

    with app.app_context():
        from app import models  # Use from import to avoid shadowing local `app` variable
        from app.video.views import Video
        db.create_all()
        _ensure_monitor_schema()

        # Inject super_admin
        from app.models.user import User
        if not User.query.filter_by(emp_id="admin").first():
            super_admin = User(
                emp_id="admin",
                name="Super Admin",
                role="super_admin"
            )
            super_admin.set_password("admin")
            db.session.add(super_admin)
            db.session.commit()
            print("Super Admin (admin/admin) created.")

        # Start background stream recording service
        from app.core.recorder import start_all_recordings
        from app.monitors.routes import start_cover_refresh_loop
        if os.environ.get("PUREYES_DISABLE_BACKGROUND") != "1":
            start_all_recordings(app)
            start_cover_refresh_loop(app)

    return app
