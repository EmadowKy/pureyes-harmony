import hmac
from urllib.parse import urlencode

from flask import current_app, request
from flask_jwt_extended import get_jwt_identity
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer


MEDIA_TOKEN_SALT = "pureyes-media-access-v1"


def path_scope(path):
    normalized = (path or "").replace("\\", "/").lstrip("/")
    return f"path:{normalized}"


def monitor_scope(monitor_id):
    return f"monitor:{int(monitor_id)}"


def _serializer():
    return URLSafeTimedSerializer(current_app.config["SECRET_KEY"], salt=MEDIA_TOKEN_SALT)


def issue_media_token(scope, emp_id=None):
    try:
        identity = emp_id or get_jwt_identity()
    except RuntimeError:
        return ""
    if not identity:
        return ""

    from app.core.db import db
    from app.models.user import User

    user = db.session.get(User, identity)
    if not user or not user.is_active:
        return ""
    return _serializer().dumps({
        "sub": user.emp_id,
        "auth_version": user.auth_version or 0,
        "scope": scope,
    })


def build_media_url(path, scope, emp_id=None):
    token = issue_media_token(scope, emp_id=emp_id)
    if not token:
        return ""
    separator = "&" if "?" in path else "?"
    return f"{path}{separator}{urlencode({'media_token': token})}"


def media_access_identity(scope):
    token = request.args.get("media_token") or ""
    if not token:
        return None
    try:
        payload = _serializer().loads(
            token,
            max_age=int(current_app.config.get("MEDIA_TOKEN_MAX_AGE_SECONDS", 7200)),
        )
    except (BadSignature, SignatureExpired, TypeError, ValueError):
        return None

    if not hmac.compare_digest(str(payload.get("scope") or ""), str(scope)):
        return None

    from app.core.db import db
    from app.models.user import User

    user = db.session.get(User, payload.get("sub"))
    if not user or not user.is_active:
        return None
    if payload.get("auth_version") != (user.auth_version or 0):
        return None
    return user.emp_id


def media_access_allowed(scope):
    return media_access_identity(scope) is not None
