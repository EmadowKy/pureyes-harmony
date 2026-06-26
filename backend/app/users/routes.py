from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity, get_jwt
from app.core.db import db
from app.models.user import User
from app.core.response import success, fail
from . import users_bp

def role_required(*roles):
    def decorator(fn):
        from functools import wraps
        @wraps(fn)
        @jwt_required()
        def wrapper(*args, **kwargs):
            claims = get_jwt()
            current_role = claims.get("role")
            if current_role not in roles:
                return fail(message="权限不足", code=2001, http_status=403)
            return fn(*args, **kwargs)
        return wrapper
    return decorator

@users_bp.get("/me")
@jwt_required()
def me():
    emp_id = get_jwt_identity()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    return success(data=user.to_dict())

@users_bp.put("/me")
@jwt_required()
def update_me():
    emp_id = get_jwt_identity()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)

    data = request.get_json() or {}
    if "name" in data:
        user.name = data["name"]
    if "phone" in data:
        user.phone = data["phone"]
    if "avatar" in data:
        user.avatar = data["avatar"]
    if "password" in data and data["password"]:
        if len(data["password"]) < 6:
            return fail(message="password must be at least 6 chars", code=2004, http_status=400)
        user.set_password(data["password"])

    db.session.commit()
    return success(message="user updated", data=user.to_dict())

@users_bp.get("/")
@role_required("admin", "super_admin")
def get_all_users():
    users = User.query.all()
    return success(data=[u.to_dict() for u in users])

@users_bp.post("/")
@role_required("admin", "super_admin")
def create_user():
    data = request.get_json() or {}
    emp_id = data.get("emp_id")
    name = data.get("name", "New User")
    password = data.get("password")

    if not emp_id or not password:
        return fail(message="emp_id and password are required", code=2005, http_status=400)

    if User.query.filter_by(emp_id=emp_id).first():
        return fail(message="emp_id already exists", code=2006, http_status=409)

    user = User(
        emp_id=emp_id,
        name=name,
        phone=data.get("phone"),
        avatar=data.get("avatar"),
        role="user"
    )
    user.set_password(password)
    db.session.add(user)
    db.session.commit()

    return success(message="user created", data=user.to_dict(), http_status=201)

@users_bp.put("/<emp_id>/role")
@role_required("super_admin")
def promote_user(emp_id):
    data = request.get_json() or {}
    new_role = data.get("role")
    
    if new_role not in ["admin", "user"]:
        return fail(message="invalid role", code=2007, http_status=400)

    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
        
    if user.role == "super_admin":
        return fail(message="cannot change super_admin role", code=2008, http_status=403)

    user.role = new_role
    db.session.commit()
    return success(message="role updated", data=user.to_dict())
