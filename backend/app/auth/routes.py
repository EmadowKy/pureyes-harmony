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
from . import auth_bp

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
        additional_claims={"role": user.role, "emp_id": user.emp_id, "name": user.name}
    )
    refresh_token = create_refresh_token(identity=user.emp_id)

    return success(
        message="login success",
        data={
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user": user.to_dict()
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
        additional_claims={"role": user.role, "emp_id": user.emp_id, "name": user.name}
    )
    return success(
        message="token refreshed",
        data={"access_token": new_access_token}
    )

@auth_bp.post("/logout")
@jwt_required()
def logout():
    jti = get_jwt()["jti"]
    TokenBlacklist.add(jti)
    return success(message="logout success")
