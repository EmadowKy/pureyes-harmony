from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.db import db
from app.models.user import User
from app.core.response import success, fail
from app.user_center.permissions import can_view_user, current_user, role_required
from app.user_center.serializers import user_to_dict
from . import users_bp

USER_MUTABLE_FIELDS = {"name", "phone", "avatar"}


def _clean(value):
    return value.strip() if isinstance(value, str) else value


def _apply_user_updates(user, data):
    for field in USER_MUTABLE_FIELDS:
        if field in data:
            setattr(user, field, _clean(data.get(field)))

    if "password" in data and data["password"]:
        password = str(data["password"])
        if len(password) < 6:
            return fail(message="password must be at least 6 chars", code=2004, http_status=400)
        user.set_password(password)
    return None

@users_bp.get("/me")
@jwt_required()
def me():
    emp_id = get_jwt_identity()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    return success(data=user_to_dict(user))

@users_bp.put("/me")
@jwt_required()
def update_me():
    emp_id = get_jwt_identity()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)

    error = _apply_user_updates(user, request.get_json() or {})
    if error:
        return error

    db.session.commit()
    return success(message="user updated", data=user_to_dict(user))


@users_bp.get("/<emp_id>")
@jwt_required()
def get_user(emp_id):
    viewer = current_user()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    if not can_view_user(viewer, emp_id):
        return fail(message="permission denied", code=2001, http_status=403)
    return success(data=user_to_dict(user))

@users_bp.get("/")
@role_required("admin", "super_admin")
def get_all_users():
    keyword = _clean(request.args.get("keyword") or request.args.get("q") or "")
    role = _clean(request.args.get("role") or "")
    is_active = _clean(request.args.get("is_active") or "")

    query = User.query
    if keyword:
        like_pattern = f"%{keyword}%"
        query = query.filter((User.emp_id.ilike(like_pattern)) | (User.name.ilike(like_pattern)))
    if role:
        query = query.filter(User.role == role)
    if is_active:
        if is_active.lower() in {"1", "true", "yes"}:
            query = query.filter(User.is_active.is_(True))
        elif is_active.lower() in {"0", "false", "no"}:
            query = query.filter(User.is_active.is_(False))

    users = query.order_by(User.created_at.desc()).all()
    return success(data=[user_to_dict(u) for u in users])

@users_bp.post("/")
@role_required("admin", "super_admin")
def create_user():
    data = request.get_json() or {}
    emp_id = _clean(data.get("emp_id"))
    name = _clean(data.get("name")) or "New User"
    password = data.get("password")
    phone = _clean(data.get("phone"))
    avatar = _clean(data.get("avatar"))

    if not emp_id or not password:
        return fail(message="emp_id and password are required", code=2005, http_status=400)
    if len(str(password)) < 6:
        return fail(message="password must be at least 6 chars", code=2004, http_status=400)

    if User.query.filter_by(emp_id=emp_id).first():
        return fail(message="emp_id already exists", code=2006, http_status=409)

    user = User(
        emp_id=emp_id,
        name=name,
        phone=phone,
        avatar=avatar,
        role="user"
    )
    user.set_password(password)
    db.session.add(user)
    db.session.commit()

    return success(message="user created", data=user_to_dict(user), http_status=201)

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
    return success(message="role updated", data=user_to_dict(user))


@users_bp.put("/<emp_id>/status")
@role_required("admin", "super_admin")
def update_user_status(emp_id):
    actor = current_user()
    data = request.get_json() or {}
    is_active = data.get("is_active")
    if not isinstance(is_active, bool):
        return fail(message="is_active must be boolean", code=2009, http_status=400)

    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    if user.role == "super_admin":
        return fail(message="cannot disable super_admin", code=2008, http_status=403)
    if actor and actor.emp_id == emp_id and not is_active:
        return fail(message="cannot disable yourself", code=2010, http_status=403)

    user.is_active = is_active
    db.session.commit()
    return success(message="user status updated", data=user_to_dict(user))


@users_bp.put("/<emp_id>")
@role_required("admin", "super_admin")
def update_user(emp_id):
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    if user.role == "super_admin":
        return fail(message="cannot edit super_admin here", code=2008, http_status=403)

    error = _apply_user_updates(user, request.get_json() or {})
    if error:
        return error

    db.session.commit()
    return success(message="user updated", data=user_to_dict(user))
