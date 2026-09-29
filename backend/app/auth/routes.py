from flask import request
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    jwt_required,
    get_jwt_identity,
    get_jwt
)
from app.core.db import db
from app.models.user import User
from app.models.blacklist import TokenBlacklist
from app.core.response import success, fail
from app.user_center.serializers import user_to_dict
from . import auth_bp
from collections import defaultdict, deque
from threading import Lock
from time import monotonic

_capture_attempts = defaultdict(deque)
_capture_attempt_lock = Lock()


@auth_bp.put("/screen-capture")
@jwt_required()
def update_screen_capture():
    """Both enabling and disabling capture require the current user's password."""
    payload = request.get_json(silent=True) or {}
    password = payload.get("password")
    allowed = payload.get("allowed")
    if not isinstance(password, str) or not password or len(password) > 1024 or type(allowed) is not bool:
        return fail(message="请输入当前账号密码并选择截图录屏权限", code=1301, http_status=400)
    user = db.session.get(User, get_jwt_identity())
    if not user or not user.is_active:
        return fail(message="账号不可用", code=1302, http_status=403)
    now = monotonic()
    with _capture_attempt_lock:
        attempts = _capture_attempts[user.emp_id]
        while attempts and attempts[0] <= now - 300:
            attempts.popleft()
        if len(attempts) >= 5:
            return fail(message="验证次数过多，请5分钟后重试", code=1303, http_status=429)
        attempts.append(now)
    if not user.check_password(password):
        return fail(message="当前账号密码不正确，设置未修改", code=1304, http_status=403)
    with _capture_attempt_lock:
        _capture_attempts.pop(user.emp_id, None)
    user.screen_capture_allowed = allowed
    db.session.commit()
    return success(data={"allowed": allowed}, message="截图录屏权限已更新")

@auth_bp.post("/login")
def login():
    payload = request.get_json(silent=True) or {}
    emp_id = (payload.get("emp_id") or "").strip()
    password = payload.get("password") or ""

    if not emp_id or not password:
        return fail(message="emp_id and password are required", code=1101, http_status=400)

    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="invalid emp_id or password", code=1102, http_status=401)

    if not user.is_active:
        return fail(message="user is inactive", code=1103, http_status=403)

    if not user.check_password(password):
        return fail(message="invalid emp_id or password", code=1102, http_status=401)

    access_token = create_access_token(
        identity=user.emp_id,
        additional_claims={
            "role": user.role,
            "emp_id": user.emp_id,
            "name": user.name,
            "auth_version": user.auth_version,
        }
    )
    refresh_token = create_refresh_token(
        identity=user.emp_id,
        additional_claims={"auth_version": user.auth_version},
    )

    return success(
        message="login success",
        data={
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user": user_to_dict(user, include_settings=True)
        }
    )

@auth_bp.post("/refresh")
@jwt_required(refresh=True)
def refresh():
    emp_id = get_jwt_identity()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=1201, http_status=404)
    if not user.is_active:
        return fail(message="user is inactive", code=1202, http_status=403)

    new_access_token = create_access_token(
        identity=user.emp_id,
        additional_claims={
            "role": user.role,
            "emp_id": user.emp_id,
            "name": user.name,
            "auth_version": user.auth_version,
        }
    )
    return success(
        message="token refreshed",
        data={"access_token": new_access_token}
    )

@auth_bp.post("/logout")
@jwt_required()
def logout():
    emp_id = get_jwt_identity()
    jti = get_jwt()["jti"]
    user = User.query.filter_by(emp_id=emp_id).first()
    db.session.add(TokenBlacklist(jti=jti))
    if user:
        user.auth_version = (user.auth_version or 0) + 1
    db.session.commit()
    return success(message="logout success")
