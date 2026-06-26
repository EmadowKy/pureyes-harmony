from flask import Flask
import os
from .core.db import db
from .extensions import jwt, cors
from .core.config import Config

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
            print("✅ Super Admin (admin/admin) created.")
            
        # Start background stream recording service
        import atexit
        from app.core.recorder import start_all_recordings, stop_all_recordings
        from app.video_stream_routes import stop_all_live_converters
        start_all_recordings(app)
        atexit.register(stop_all_recordings)
        atexit.register(stop_all_live_converters)
    
    return app