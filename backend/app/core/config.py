import os
from datetime import timedelta

CORE_DIR = os.path.dirname(os.path.abspath(__file__))
APP_DIR = os.path.dirname(CORE_DIR)
BACKEND_DIR = os.path.dirname(APP_DIR)

class Config:
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL",
        f"sqlite:///{os.path.join(BACKEND_DIR, 'user.db')}",
    )
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

    env_path = os.environ.get(f"{name.upper()}_PATH")
    if env_path and os.path.exists(env_path):
        return env_path

    env_home = os.environ.get("FFMPEG_HOME")
    if env_home:
        env_home_path = os.path.join(env_home, exe_name)
        if os.path.exists(env_home_path):
            return env_home_path
        env_home_bin_path = os.path.join(env_home, "bin", exe_name)
        if os.path.exists(env_home_bin_path):
            return env_home_bin_path

    common_windows_path = os.path.join(
        "D:\\tools\\ffmpeg\\ffmpeg-8\\ffmpeg-8.1.2-full_build\\bin",
        exe_name,
    )
    if os.path.exists(common_windows_path):
        return common_windows_path

    return name
