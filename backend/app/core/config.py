import os
from datetime import timedelta

CORE_DIR = os.path.dirname(os.path.abspath(__file__))
APP_DIR = os.path.dirname(CORE_DIR)
BACKEND_DIR = os.path.dirname(APP_DIR)

class Config:
    SQLALCHEMY_DATABASE_URI = f"sqlite:///{os.path.join(BACKEND_DIR, 'user.db')}"
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')
    JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY', 'jwt-secret-key-change-in-production')
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=24)
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=30)

    VIDEO_UPLOAD_PATH = os.path.join(BACKEND_DIR, "uploads")

def get_ffmpeg_path(name="ffmpeg"):
    """
    Dynamically locate ffmpeg/ffprobe executable.
    Checks backend/ and backend/bin/ first, then falls back to system PATH.
    """
    ext = ".exe" if os.name == "nt" else ""
    exe_name = f"{name}{ext}"
    
    # Check project root (backend/)
    local_path = os.path.join(BACKEND_DIR, exe_name)
    if os.path.exists(local_path):
        return local_path
        
    # Check backend/bin/
    local_bin_path = os.path.join(BACKEND_DIR, "bin", exe_name)
    if os.path.exists(local_bin_path):
        return local_bin_path
        
    return name