import os
import base64
import hashlib
import secrets
from datetime import timedelta

CORE_DIR = os.path.dirname(os.path.abspath(__file__))
APP_DIR = os.path.dirname(CORE_DIR)
BACKEND_DIR = os.path.dirname(APP_DIR)


def _load_or_create_runtime_secret(filename):
    runtime_dir = os.path.join(BACKEND_DIR, ".runtime")
    os.makedirs(runtime_dir, exist_ok=True)
    secret_path = os.path.join(runtime_dir, filename)
    try:
        with open(secret_path, "r", encoding="utf-8") as secret_file:
            value = secret_file.read().strip()
            if value:
                return value
    except FileNotFoundError:
        pass

    value = secrets.token_urlsafe(48)
    try:
        descriptor = os.open(secret_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as secret_file:
            secret_file.write(value)
        return value
    except FileExistsError:
        with open(secret_path, "r", encoding="utf-8") as secret_file:
            return secret_file.read().strip()


def _encryption_key(secret_key):
    configured = os.environ.get("DATA_ENCRYPTION_KEY")
    if configured:
        key = configured
    else:
        digest = hashlib.sha256(secret_key.encode("utf-8")).digest()
        key = base64.urlsafe_b64encode(digest).decode("ascii")
    try:
        from cryptography.fernet import Fernet
        Fernet(key.encode("ascii"))
    except Exception as exc:
        raise RuntimeError("DATA_ENCRYPTION_KEY must be a valid Fernet key") from exc
    return key


_secret_key = os.environ.get("SECRET_KEY") or _load_or_create_runtime_secret("flask_secret")
_jwt_secret_key = os.environ.get("JWT_SECRET_KEY") or _load_or_create_runtime_secret("jwt_secret")

class Config:
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL",
        f"sqlite:///{os.path.join(BACKEND_DIR, 'user.db')}",
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    SECRET_KEY = _secret_key
    JWT_SECRET_KEY = _jwt_secret_key
    DATA_ENCRYPTION_KEY = _encryption_key(_secret_key)
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=24)
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=30)
    MEDIA_TOKEN_MAX_AGE_SECONDS = int(os.environ.get("MEDIA_TOKEN_MAX_AGE_SECONDS", "7200"))
    MAX_CONTENT_LENGTH = int(os.environ.get("MAX_VIDEO_UPLOAD_BYTES", str(2 * 1024 * 1024 * 1024)))
    ALLOW_INSECURE_LLM_HTTP = os.environ.get("ALLOW_INSECURE_LLM_HTTP") == "1"
    ALLOW_PRIVATE_LLM_NETWORK = os.environ.get("ALLOW_PRIVATE_LLM_NETWORK") == "1"
    LLM_ALLOWED_HOSTS = {
        host.strip().lower()
        for host in os.environ.get("LLM_ALLOWED_HOSTS", "").split(",")
        if host.strip()
    }

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
